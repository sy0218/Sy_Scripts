#!/usr/bin/bash
. /etc/sy_script
. ${Sy_Dir}/Sy_Scripts/functions.sh
. ${Sy_Dir}/Sy_Scripts/conf/server.properties

# 인자가 없거나 공백이면 종료
if [ -z "$1" ]; then
    echo "${0} 인자가 없습니다. 스크립트를 종료합니다. (ex. start, stop, status)"
    exit 1
fi

KAFKA_OPT=${1}

for ip in ${kafka_ip}
do
        kafka_ctl "${ip}" "${KAFKA_OPT}"
	echo
	echo
done
