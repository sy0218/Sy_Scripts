#!/bin/bash
. /etc/sy_script
. ${Sy_Dir}/Sy_Scripts/functions.sh

set -e

echo "------------------------------------------"
echo "   Kafka 접속 정보 설정"
echo "------------------------------------------"

# 1. Kafka Bootstrap Server 입력 받기
read -p "Kafka Bootstrap Server를 입력하세요 (예: 192.168.56.60:9092): " BOOTSTRAP_SERVER
if [ -z "${BOOTSTRAP_SERVER}" ]; then
    log_error "Bootstrap Server 주소가 입력되지 않았습니다."
    exit 1
fi

# 2. Schema Registry URL 입력 받기
read -p "Schema Registry URL을 입력하세요 (예: http://192.168.56.60:8081): " SCHEMA_REGISTRY_URL
if [ -z "${SCHEMA_REGISTRY_URL}" ]; then
    log_error "Schema Registry URL이 입력되지 않았습니다."
    exit 1
fi

log_info "연결 설정 완료: [${BOOTSTRAP_SERVER}] / [${SCHEMA_REGISTRY_URL}]"

# ------------------------------------------
# 3. 메인 루프 시작
# ------------------------------------------
while true; do
    echo ""
    echo "------------------------------------------"
    echo "   Kafka & Schema Registry 관리 도구"
    echo "------------------------------------------"
    echo "1) 모든 Subject(스키마) 목록 확인"
    echo "2) 특정 토픽의 최신 스키마 확인"
    echo "3) 특정 토픽의 상세 정보(Describe)"
    echo "4) 모든 토픽 목록 확인"
    echo "5) 특정 토픽 메시지 샘플 조회 (최근 1개)"
    echo "6) 특정 토픽 및 스키마 삭제 후 재생성 (초기화)"
    echo "q) 종료"
    echo "------------------------------------------"
    read -p "번호를 선택하세요: " choice

    case $choice in
        1)
            log_info "Schema Registry Subject 목록 조회..."
            curl -s "${SCHEMA_REGISTRY_URL}/subjects" | jq . || curl -s "${SCHEMA_REGISTRY_URL}/subjects"
            ;;
        2)
            read -p "스키마를 확인할 토픽명을 입력하세요: " target_topic
            if [ -z "${target_topic}" ]; then log_error "토픽명 누락"; continue; fi
            SCHEMA_RES=$(curl -s "${SCHEMA_REGISTRY_URL}/subjects/${target_topic}-value/versions/latest")
            echo "${SCHEMA_RES}" | jq . || echo "${SCHEMA_RES}"
            ;;
        3)
            read -p "상세 정보를 확인할 토픽명을 입력하세요: " target_topic
            if [ -z "${target_topic}" ]; then log_error "토픽명 누락"; continue; fi
            kafka-topics.sh --bootstrap-server "${BOOTSTRAP_SERVER}" --describe --topic "${target_topic}"
            ;;
        4)
            log_info "Kafka 모든 토픽 목록 조회..."
            kafka-topics.sh --bootstrap-server "${BOOTSTRAP_SERVER}" --list
            ;;
        5)
            read -p "데이터를 확인할 토픽명을 입력하세요: " target_topic
            if [ -z "${target_topic}" ]; then log_error "토픽명 누락"; continue; fi
            kafka-console-consumer.sh --bootstrap-server "${BOOTSTRAP_SERVER}" --topic "${target_topic}" --from-beginning --max-messages 1 --timeout-ms 5000 || log_error "데이터 없음"
            ;;
        6)
            read -p "삭제 및 재생성할 토픽명을 입력하세요: " target_topic
            if [ -z "${target_topic}" ]; then log_error "토픽명 누락"; continue; fi
            
            echo -e "\033[31m경고: 토픽 [${target_topic}]과 관련된 모든 데이터와 스키마가 삭제됩니다.\033[0m"
            read -p "정말 진행하시겠습니까? (y/n): " confirm
            
            if [ "$confirm" == "y" ]; then
                log_info "1. 스키마 삭제 (Soft & Hard Delete)"
                # Soft Delete
                curl -s -X DELETE "${SCHEMA_REGISTRY_URL}/subjects/${target_topic}-value" || true
                # Permanent(Hard) Delete
                curl -s -X DELETE "${SCHEMA_REGISTRY_URL}/subjects/${target_topic}-value?permanent=true" || true
                
                log_info "2. Kafka 토픽 삭제"
                kafka-topics.sh --bootstrap-server "${BOOTSTRAP_SERVER}" --delete --topic "${target_topic}" || true
                
                log_info "3. Kafka 토픽 재생성 (Partition: 3, Replication: 1)"
                # 로컬 테스트 환경이면 Replication 3은 안될 수 있어 1로 설정하거나 상황에 맞게 수정하세요
                kafka-topics.sh --bootstrap-server "${BOOTSTRAP_SERVER}" --create --topic "${target_topic}" --partitions 3 --replication-factor 1
                
                log_info "초기화 완료."
            else
                log_info "취소되었습니다."
            fi
            ;;
        q|Q)
            log_info "스크립트를 종료합니다."
            break
            ;;
        *)
            log_error "잘못된 선택입니다."
            ;;
    esac

    echo ""
    read -p $'\e[32m계속하려면 엔터를 누르세요...\e[0m' temp
done
