#!/bin/bash
set -uo pipefail

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

    value=$(yq e ".${service}.${field}" "$CONFIG_FILE" 2>/dev/null || echo "null") 

    if [[ -z "${value}" || "${value}" == "null" ]]; then
        echo "[ERROR] not found: ${service}.${field}" >&2
        return 1
    fi

    echo "$value"
    return 0
}

# service 리텐션 실행
_run_service_retention() {
    local service="${1}"
    local script="${SCRIPT_DIR}/${service}_retention.sh"

    if [[ ! -f "${script}" ]]; then
        echo "[ERROR] script not found: ${script}" >&2
        return 1
    fi

    echo "[INFO] ${service} retention 실행"

    if bash "${script}"; then
        echo "[SUCCESS] [${service}] Retention completed."
        return 0
    else
        echo "[ERROR] [${service}] Script failed with exit code $?" >&2
        return 1
    fi
}

# 메인 로직
main() {
    echo "[INFO] retention policy start"

    _check_requirements
    services=$(_get_services)

    for service in ${services};
    do
        echo -e "\n----------------------------------------"
        echo "Service: $service"

        # 1. 상태 값 체크
        local status
        if ! status=$(_get_yaml_value "$service" "status"); then
            echo "[ERROR] [${service}] YAML field 'status' is missing" >&2
            ((error_count++))
            continue
        fi

        if [[ "${status}" != "ON" ]]; then
            echo "[SKIP] [${service}] status is ${status}"
            continue
        fi

        # 2. 실제 스크립트 실행
        if ! _run_service_retention "${service}"; then
            # 실행 실패 시 에러 카운트 증가 후 다음 루프로 진행
            ((error_count++))
        fi

    done

    echo -e "\n----------------------------------------"
    echo "[INFO] retention policy done"
    echo "[RESULT] Total error_count: ${error_count}"
}

########################################
# 실행
########################################
main "$@"
