#!/bin/bash
set -euo pipefail

# ==========================================
# .env 로드 (스크립트와 같은 디렉토리)
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env"

# 필수 env 체크
for v in GITLAB_PRIVATE_TOKEN GITLAB_PROJECT_PATH GITLAB_URL GITLAB_RETENTION_COUNT;
do
    [[ -z "${!v}" ]] && {
        echo "[ERROR] $v is empty" >&2
        exit 1
    }
done

SAFE_PROJECT_PATH="${GITLAB_PROJECT_PATH//\//%2F}"
BASE_URL="${GITLAB_URL}/api/v4/projects/${SAFE_PROJECT_PATH}/pipelines"

echo "[INFO] ${GITLAB_PROJECT_PATH} pipeline 조회 중..."

response="$(curl -sS -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
    "${BASE_URL}?per_page=100&sort=desc")"

total_count="$(jq 'length' <<< "$response")"

echo "[INFO] total: ${total_count}, keep: ${GITLAB_RETENTION_COUNT}"

if (( total_count <= GITLAB_RETENTION_COUNT )); then
    echo "[INFO] 삭제 대상 없음"
    exit 0
fi

deleted=0
skipped=0
failed=0

is_active_status() {
    case "$1" in
        running|pending|created|preparing|waiting_for_resource)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

jq -r ".[$GITLAB_RETENTION_COUNT:][] | [.id, .status, .ref] | @tsv" <<< "$response" |
while IFS=$'\t' read -r id status ref; do

    if is_active_status "$status"; then
        echo "[SKIP] #$id ($status / $ref)"
        ((skipped++))
        continue
    fi

    code="$(curl -sS -o /dev/null -w '%{http_code}' \
        -X DELETE \
        -H "PRIVATE-TOKEN: ${GITLAB_PRIVATE_TOKEN}" \
        "${BASE_URL}/${id}")"

    if [[ "$code" == "204" ]]; then
        echo "[OK] #$id deleted"
        ((deleted++))
    else
        echo "[FAIL] #$id code=$code" >&2
        ((failed++))
    fi
done

echo ""
echo "[DONE] deleted=$deleted skipped=$skipped failed=$failed"
