#!/bin/bash

# 환경변수 로드
set -a
. ./.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh


## 전역변수 ##
SERVERS=(s1 s2)
ALL_SERVERS=(ap s1 s2)

for SERVER in "${SERVERS[@]}";
do
        log_info "[Start] ${SERVER} time and clock rsync ..."

        ssh ${SERVER} "date -s \"$(date '+%Y-%m-%d %H:%M:%S')\" && hwclock -w"

        log_info "[End] ${SERVER} time and clock rsync ..."
        echo ""
done

for SERVER in "${ALL_SERVERS[@]}";
do
    log_info ">>> ${SERVER}:"
    ssh ${SERVER} "date '+%Y-%m-%d %H:%M:%S'"
done
