#!/bin/bash

# 환경변수 로드
set -a
. ./.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh

# 인자 개수 확인
if [ -z "$1" ]; then
    echo "Usage: ${0} <cmd>"
    exit 1
fi

CMD="$1"

## 전역변수 ##
SERVERS=(ap s1 s2)

## CMD 실행 ###
for SERVER in "${SERVERS[@]}";
do
	log_info "[RUN] ${SERVER} BEGIN ${CMD}"
		ssh -o ConnectTimeout=60 "${SERVER}" "${CMD}"
	log_info "[END] ${SERVER} OK ${CMD}"
	echo
	echo
done
