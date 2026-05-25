#!/bin/bash

# 환경변수 로드
set -a
. ../.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh

harbor_dir="/Users/jsy_project/infra/harbor"

if [ -d "$harbor_dir" ]; then
    log_info "디렉토리 이동합니다: ${harbor_dir}"
    cd "${harbor_dir}" || exit 1

    log_info "Docker Compose -d 시작"
    docker compose up -d
else
    log_error "디렉토리를 찾을 수 없습니다: ${harbor_dir}"
fi
