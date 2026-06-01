#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env"

error_count=0

echo "[INFO] retention policy start"

# env에서 *_RETENTION_STATUS만 추출
grep -E '_RETENTION_STATUS=' "${SCRIPT_DIR}/.env" | while IFS='=' read -r key value;
do
    service="${key%_RETENTION_STATUS}"
    service="$(echo "$service" | tr '[:upper:]' '[:lower:]')"
    status="${value//\"/}"

    if [[ "$status" != "ON" ]]; then
        echo "[SKIP] $service retention OFF"
        continue
    fi

    script="${SCRIPT_DIR}/${service}_retention.sh"

    if [[ ! -f "$script" ]]; then
        echo "[WARN] script not found: $script"
        ((error_count++)) || true
        continue
    fi

    echo "[INFO] $service retention 실행"

    if bash "$script"; then
        echo "[OK] $service 완료"
    else
        echo "[ERROR] $service 실패" >&2
        ((error_count++)) || true
    fi
    
done

echo "[INFO] retention policy done"
echo "[RESULT] error_count=$error_count"
