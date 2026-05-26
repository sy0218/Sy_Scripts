#!/bin/bash

# 환경변수 로드
set -a
. ../.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh

create_volumes=(
    dsai-postgres-data
    dsai-neo4j-data
    dsai-neo4j-logs
    dsai-typedb-data
    dsai-prometheus-data
    dsai-loki-data
    dsai-grafana-data
    dsai-alloy-data
    dsai-qm-timescale-data
    dsai-qm-neo4j-data
    dsai-qm-neo4j-logs
    dsai-qm-airflow-logs
    dsai-hf-cache
)

## 볼륨 생성 ##
for docker_volume in "${create_volumes[@]}";
do
    log_info "[RUN] CREATE ${docker_volume}"
        docker volume create "${docker_volume}"
    log_info "[END] OK     ${docker_volume}"
    echo
    echo
done
