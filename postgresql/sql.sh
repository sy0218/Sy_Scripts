#!/usr/bin/bash

# 환경변수 로드
set -a
. ../.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh

# 인자 개수 확인
if [ -z "$1" ]; then
    echo "Usage: ${0} <query>"
    exit 1
fi

POSTGRES_sql_exec "${1}"
