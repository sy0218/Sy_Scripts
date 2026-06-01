#!/bin/bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env"

# --- 필수 환경변수 확인 -------------------------------------------------
for v in HARBOR_URL HARBOR_USER HARBOR_PASSWORD HARBOR_RETENTION_MAP; do
    if [[ -z "${!v}" ]]; then
        echo "[ERROR] env 변수 '$v' 가 비어있습니다. .env 확인하세요." >&2
        exit 1
    fi
done

# 스케줄 cron (6필드, 초 포함). 비우면 "None"(수동 실행). 예: "0 0 0 * * *" = 매일 0시
RETENTION_CRON="${RETENTION_CRON:-}"

IFS=',' read -ra ITEMS <<< "$HARBOR_RETENTION_MAP"

# HARBOR_RETENTION_MAP 에서 프로젝트명 -> 유지 개수 조회
function get_keep_last() {
    local name=$1
    for item in "${ITEMS[@]}"; do
        local project keep
        project=$(echo "$item" | cut -d: -f1 | xargs)   # 앞뒤 공백 제거
        keep=$(echo "$item" | cut -d: -f2 | xargs)
        if [[ "$project" == "$name" ]]; then
            echo "$keep"
            return
        fi
    done
}

# 공통 curl 래퍼: 본문과 HTTP 상태코드를 분리해서 전역변수에 담음
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

echo "$PROJECTS" | jq -c '.[]' | while read -r project
do
    PROJECT_ID=$(echo "$project" | jq -r '.project_id')
    PROJECT_NAME=$(echo "$project" | jq -r '.name')
    echo "----------------------------------"
    echo "Project: $PROJECT_NAME ($PROJECT_ID)"

    KEEP_LAST=$(get_keep_last "$PROJECT_NAME")
    if [[ -z "$KEEP_LAST" ]]; then
        echo "[SKIP] no retention config"
        continue
    fi
    # 숫자인지 검증
    if ! [[ "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] KEEP_LAST 값이 숫자가 아님: '$KEEP_LAST' -> 건너뜀" >&2
        continue
    fi
    echo "KEEP_LAST = $KEEP_LAST"

    # 정책 본문 (POST/PUT 공용)
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

    # 이미 retention 정책이 있는지 확인 (프로젝트당 1개만 가능)
    harbor_curl "${HARBOR_URL}/api/v2.0/projects/${PROJECT_ID}"
    RETENTION_ID=$(echo "$RESP_BODY" | jq -r '.metadata.retention_id // empty')

    if [[ -n "$RETENTION_ID" ]]; then
        # 기존 정책 갱신 (재실행해도 안전)
        echo "기존 정책(id=$RETENTION_ID) 업데이트..."
        harbor_curl -X PUT \
            -H "Content-Type: application/json" \
            "${HARBOR_URL}/api/v2.0/retentions/${RETENTION_ID}" \
            -d "$PAYLOAD"
        SUCCESS_CODE="200"
    else
        # 신규 정책 생성
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
echo "완료."
