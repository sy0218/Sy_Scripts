#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

# YAML에서 harbor 기본 설정 로드
HARBOR_URL=$(yq e '.harbor.url' "$CONFIG_FILE")
HARBOR_USER=$(yq e '.harbor.user' "$CONFIG_FILE")
HARBOR_PASSWORD=$(yq e '.harbor.password' "$CONFIG_FILE")
RETENTION_CRON=$(yq e '.harbor.retention_cron' "$CONFIG_FILE")
HARBOR_GC_CRON=$(yq e '.harbor.gc_cron' "$CONFIG_FILE")
HARBOR_GC_DELETE_UNTAGGED=$(yq e '.harbor.delete_untagged' "$CONFIG_FILE")

# 필수 환경변수 확인
for v in HARBOR_URL HARBOR_USER HARBOR_PASSWORD; do
    if [[ -z "${!v}" || "${!v}" == "null" ]]; then
        echo "[ERROR] '$v' 가 비어있습니다. config.yml을 확인하세요." >&2
        exit 1
    fi
done

[[ "$RETENTION_CRON" == "null" ]] && RETENTION_CRON=""
[[ "$HARBOR_GC_CRON" == "null" ]] && HARBOR_GC_CRON=""

# config.yml에 설정이 없거나 null이면 기본값 false 처리
if [[ "$HARBOR_GC_DELETE_UNTAGGED" == "null" || -z "$HARBOR_GC_DELETE_UNTAGGED" ]]; then
    HARBOR_GC_DELETE_UNTAGGED="false"
fi

# 공통 curl 래퍼
RESP_BODY=""
RESP_CODE=""
function harbor_curl() {
    local raw
    raw=$(curl -sk -w $'\n%{http_code}' \
        -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
        "$@")
    RESP_CODE=$(echo "$raw" | tail -n1)
    RESP_BODY=$(echo "$raw" | sed '$d')
}

# 프로젝트 목록 조회
harbor_curl "${HARBOR_URL}/api/v2.0/projects?page=1&page_size=100"
if [[ "$RESP_CODE" != "200" ]]; then
    echo "[ERROR] 프로젝트 목록 조회 실패 (HTTP $RESP_CODE)" >&2
    echo "$RESP_BODY" >&2
    exit 1
fi
PROJECTS="$RESP_BODY"

echo "$PROJECTS" | jq -c '.[]' | while read -r project; do
    PROJECT_ID=$(echo "$project" | jq -r '.project_id')
    PROJECT_NAME=$(echo "$project" | jq -r '.name')
    echo "----------------------------------"
    echo "Project: $PROJECT_NAME ($PROJECT_ID)"

    # 1. config.yml에서 현재 project에 해당하는 rules 배열을 JSON으로 추출
    PROJECT_CONFIG_JSON=$(yq e ".harbor.retention_map[] | select(.project == \"$PROJECT_NAME\")" -o=json "$CONFIG_FILE")

    if [[ -z "$PROJECT_CONFIG_JSON" || "$PROJECT_CONFIG_JSON" == "null" ]]; then
        echo "[SKIP] 명시된 보관 설정(retention_map)이 없습니다."
        continue
    fi

    # 2. 개별 규칙들을 Harbor API 규격에 맞는 JSON Rule 배열로 동적 생성
    HARBOR_RULES=$(echo "$PROJECT_CONFIG_JSON" | jq -c '
      [ .rules[] |
        if .only_untagged == true then
          (
            # [규칙 A] 캐시 레포: 태그가 있는 것(**)은 개수 제한 없이 무조건 다 보관 (최대치 부여)
            {
              "action": "retain",
              "template": "latestPushedK",
              "params": { "latestPushedK": 99999 },
              "scope_selectors": { "repository": [{ "kind": "doublestar", "decoration": "repoMatches", "pattern": .repo }] },
              "tag_selectors": [{ "kind": "doublestar", "decoration": "matches", "pattern": "**" }]
            },
            # [규칙 B] 캐시 레포: 태그가 없는 것(untagged)만 설정된 keep 개수만큼 보관
            {
              "action": "retain",
              "template": "latestPushedK",
              "params": { "latestPushedK": (.keep | tonumber) },
              "scope_selectors": { "repository": [{ "kind": "doublestar", "decoration": "repoMatches", "pattern": .repo }] },
              "tag_selectors": [{ "kind": "doublestar", "decoration": "matches", "pattern": "untagged" }]
            }
          )
        else
          # [규칙 C] 일반 레포: 태그 유무 상관없이 전체 이미지 중 최신 keep 개수만큼 보관
          {
            "action": "retain",
            "template": "latestPushedK",
            "params": { "latestPushedK": (.keep | tonumber) },
            "scope_selectors": { "repository": [{ "kind": "doublestar", "decoration": "repoMatches", "pattern": .repo }] },
            "tag_selectors": [{ "kind": "doublestar", "decoration": "matches", "pattern": "**" }]
          }
        end
      ]
    ')

    if [[ "$HARBOR_RULES" == "[]" || -z "$HARBOR_RULES" ]]; then
        echo "[SKIP] 설정된 레포지토리 규칙이 없습니다."
        continue
    fi

    # 3. 전체 페이로드 조립
    PAYLOAD=$(jq -n \
      --argjson rules "$HARBOR_RULES" \
      --arg cron "$RETENTION_CRON" \
      --argjson pid "$PROJECT_ID" \
      '{
        "algorithm": "or",
        "rules": $rules,
        "trigger": {
          "kind": "Schedule",
          "settings": { "cron": $cron },
          "references": {}
        },
        "scope": { "level": "project", "ref": $pid }
      }')

    # 기존 정책 존재 여부 확인
    harbor_curl "${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}"
    RETENTION_ID=$(echo "$RESP_BODY" | jq -r '.metadata.retention_id // empty')

    if [[ -n "$RETENTION_ID" ]]; then
        echo "기존 정책(id=$RETENTION_ID) 업데이트 중..."
        harbor_curl -X PUT \
            -H "Content-Type: application/json" \
            "${HARBOR_URL}/api/v2.0/retentions/${RETENTION_ID}" \
            -d "$PAYLOAD"
        SUCCESS_CODE="200"
    else
        echo "신규 정책 생성 중..."
        harbor_curl -X POST \
            -H "Content-Type: application/json" \
            "${HARBOR_URL}/api/v2.0/retentions" \
            -d "$PAYLOAD"
        SUCCESS_CODE="201"
    fi

    if [[ "$RESP_CODE" == "$SUCCESS_CODE" || "$RESP_CODE" == "200" ]]; then
        echo "[OK] 정책 적용 완료 (HTTP $RESP_CODE)"
    else
        echo "[FAIL] 정책 적용 실패 (HTTP $RESP_CODE)" >&2
        echo "$RESP_BODY" >&2
    fi
done

echo "----------------------------------"
echo "retention 정책 동기화 완료."

# --- GC 스케줄 설정 ---------------------------
if [[ -n "$HARBOR_GC_CRON" ]]; then
    echo "----------------------------------"
    echo "GC 스케줄 설정: cron='${HARBOR_GC_CRON}', delete_untagged=${HARBOR_GC_DELETE_UNTAGGED}"

    # config.yml에서 가져온 delete_untagged 옵션을 주입
    GC_PAYLOAD=$(cat <<EOF
{
  "schedule":{ "type":"Custom", "cron":"${HARBOR_GC_CRON}" },
  "parameters":{ "delete_untagged":${HARBOR_GC_DELETE_UNTAGGED}, "dry_run":false, "workers":1 }
}
EOF
)

    harbor_curl -X PUT \
        -H "Content-Type: application/json" \
        "${HARBOR_URL}/api/v2.0/system/gc/schedule" \
        -d "$GC_PAYLOAD"

    if [[ "$RESP_CODE" == "404" || "$RESP_CODE" == "400" ]]; then
        echo "기존 GC 스케줄 없음 -> 신규 생성(POST)..."
        harbor_curl -X POST \
            -H "Content-Type: application/json" \
            "${HARBOR_URL}/api/v2.0/system/gc/schedule" \
            -d "$GC_PAYLOAD"
    fi

    if [[ "$RESP_CODE" == "200" || "$RESP_CODE" == "201" ]]; then
        echo "[OK] GC 스케줄 적용 완료 (HTTP $RESP_CODE)"
    elif [[ "$RESP_CODE" == "403" ]]; then
        echo "[FAIL] GC 스케줄 실패: admin 권한 필요 (HTTP 403). HARBOR_USER 확인." >&2
        echo "$RESP_BODY" >&2
    else
        echo "[FAIL] GC 스케줄 적용 실패 (HTTP $RESP_CODE)" >&2
        echo "$RESP_BODY" >&2
    fi
else
    echo "[SKIP] HARBOR_GC_CRON 미설정 -> GC 스케줄 건너뜀"
fi

echo "----------------------------------"
echo "완료."
