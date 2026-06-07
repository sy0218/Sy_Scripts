#!/bin/bash
set -euo pipefail

########################################
# 전역 변수
########################################
error_count=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"


########################################
# 함수
########################################

# 의존성 체크(없으면 종료)
_check_requirements() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
        exit 1
    fi

    if ! command -v yq >/dev/null 2>&1; then
        echo "[ERROR] yq command not found" >&2
        exit 1
    fi
}

# config.yml 최상위 key(서비스 목록 추출)
_get_services() {
    yq e 'keys | .[]' "$CONFIG_FILE"
}

# YAML 값 조회 (service + field 통합)
_get_yaml_value() {
    local service="${1}"
    local field="${2}"

    local value
    value=$(yq e ".${service}.${field}" "$CONFIG_FILE")

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "[ERROR] not found: ${service}.${field}" >&2
        return 1
    fi

    echo "$value"
}

# 메인 로직
main() {
    echo "[INFO] retention policy start"

    _check_requirements
    services=$(_get_services)

    for service in ${services};
    do
        echo -e "\nservice: $service"
        
        if ! status=$(_get_yaml_value "${service}" "statuss"); then
            error_count=$((error_count + 1))
            continue # 다음 서비스로 pass..
        fi
        echo "status: $status"

    done

    echo -e "\n[INFO] retention policy done"
    echo "[RESULT] error_count=$error_count"
}

########################################
# 실행
########################################
main "$@"
