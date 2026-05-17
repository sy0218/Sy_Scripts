#!/bin/bash

# 현재 functions.sh 위치 기준 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 환경변수 로드
set -a
. "${SCRIPT_DIR}/.env"
set +a

# 시스템 공통 환경 변수 import
. ${SCRIPT_DIR}/conf/server.properties

# ----------------------------------------
# INFO 로그
# ----------------------------------------
log_info() {
    echo "[INFO ] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ----------------------------------------
# ERROR 로그
# ----------------------------------------
log_error() {
    echo "[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# ----------------------------------------
# PostgreSQL 쿼리
# ----------------------------------------
POSTGRES_sql_exec() {
    PGPASSWORD=$POSTGRES_PASSWORD \
    psql -h $POSTGRES_HOST \
         -p $POSTGRES_PORT \
         -U $POSTGRES_USER \
         -d $POSTGRES_DB \
         -c "$1" -At
}

# ----------------------------------------
# Docker Hub JWT 발급
# ----------------------------------------
DOCKER_get_token() {
    curl -s \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{\"username\":\"$DOCKER_USERNAME\",\"password\":\"$DOCKER_PASSWORD\"}" \
    https://hub.docker.com/v2/users/login/ \
    | jq -r .token
}
