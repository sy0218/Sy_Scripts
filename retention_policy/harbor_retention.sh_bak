#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

# YAML에서 harbor 설정 로드
HARBOR_URL=$(yq e '.harbor.url' "$CONFIG_FILE")
HARBOR_USER=$(yq e '.harbor.user' "$CONFIG_FILE")
HARBOR_PASSWORD=$(yq e '.harbor.password' "$CONFIG_FILE")
RETENTION_CRON=$(yq e '.harbor.retention_cron' "$CONFIG_FILE")
HARBOR_GC_CRON=$(yq e '.harbor.gc_cron' "$CONFIG_FILE")

# 필수 환경변수 확인
for v in HARBOR_URL HARBOR_USER HARBOR_PASSWORD; do
    if [[ -z "${!v}" || "${!v}" == "null" ]]; then
        echo "[ERROR] '$v' 가 비어있습니다. config.yml을 확인하세요." >&2
        exit 1
    fi
done

# null 값 처리 (비어있으면 빈값으로 대체)
[[ "$RETENTION_CRON" == "null" ]] && RETENTION_CRON=""
[[ "$HARBOR_GC_CRON" == "null" ]] && HARBOR_GC_CRON=""

# HARBOR_RETENTION_MAP 대체: YAML 배열에서 project 일치하는 keep 값 가져오기
function get_keep_last() {
    local name=$1
    # yq로 해당 project를 가진 요소의 keep 값 추출
    local keep
    keep=$(yq e ".harbor.retention_map[] | select(.project == \"$name\") | .keep" "$CONFIG_FILE")
    if [[ -n "$keep" && "$keep" != "null" ]]; then
        echo "$keep"
    fi
}

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

    KEEP_LAST=$(get_keep_last "$PROJECT_NAME")
    if [[ -z "$KEEP_LAST" ]]; then
        echo "[SKIP] no retention config"
        continue
    fi
    
    if ! [[ "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] KEEP_LAST 값이 숫자가 아님: '$KEEP_LAST' -> 건너뜀" >&2
        continue
    fi
    echo "KEEP_LAST = $KEEP_LAST"

    # 정책 본문
    PAYLOAD=$(cat <<EOF
{
  "algorithm":"or",
  "rules":[
    {
      "action":"retain",
      "template":"latestPushedK",
      "params":{ "latestPushedK":${KEEP_LAST} },
      "scope_selectors":{
        "repository":[
          { "kind":"doublestar", "decoration":"repoMatches", "pattern":"**" }
        ]
      },
      "tag_selectors":[
        { "kind":"doublestar", "decoration":"matches", "pattern":"**" }
      ]
    }
  ],
  "trigger":{
    "kind":"Schedule",
    "settings":{ "cron":"${RETENTION_CRON}" },
    "references":{}
  },
  "scope":{ "level":"project", "ref":${PROJECT_ID} }
}
EOF
)

    harbor_curl "${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}"
    RETENTION_ID=$(echo "$RESP_BODY" | jq -r '.metadata.retention_id // empty')

    if [[ -n "$RETENTION_ID" ]]; then
        echo "기존 정책(id=$RETENTION_ID) 업데이트..."
        harbor_curl -X PUT \
            -H "Content-Type: application/json" \
            "${HARBOR_URL}/api/v2.0/retentions/${RETENTION_ID}" \
            -d "$PAYLOAD"
        SUCCESS_CODE="200"
    else
        echo "신규 정책 생성..."
        harbor_curl -X POST \
            -H "Content-Type: application/json" \
            "${HARBOR_URL}/api/v2.0/retentions" \
            -d "$PAYLOAD"
        SUCCESS_CODE="201"
    fi

    if [[ "$RESP_CODE" == "$SUCCESS_CODE" || "$RESP_CODE" == "200" ]]; then
        echo "[OK] 적용 완료 (HTTP $RESP_CODE)"
    else
        echo "[FAIL] 적용 실패 (HTTP $RESP_CODE)" >&2
        echo "$RESP_BODY" >&2
    fi
done

echo "----------------------------------"
echo "retention 완료."

# --- GC 스케줄 ---------------------------
if [[ -n "$HARBOR_GC_CRON" ]]; then
    echo "----------------------------------"
    echo "GC 스케줄 설정: cron='${HARBOR_GC_CRON}'"

    GC_PAYLOAD=$(cat <<EOF
{
  "schedule":{ "type":"Custom", "cron":"${HARBOR_GC_CRON}" },
  "parameters":{ "delete_untagged":true, "dry_run":false }
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
