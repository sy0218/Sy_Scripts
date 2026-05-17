#!/bin/bash

# 환경변수 로드
set -a
. ../.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh

# ----------------------------------------
# Docker Hub JWT 토큰 발급
# ----------------------------------------
docker_login() {

    TOKEN=$(DOCKER_get_token)

    if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
        log_error "Docker Hub login failed"
        exit 1
    fi
}

# ----------------------------------------
# 레포 목록 조회
# ----------------------------------------
repo_list() {

    log_info "Repository List"

    curl -s \
    -H "Authorization: JWT $TOKEN" \
    https://hub.docker.com/v2/repositories/$DOCKER_USERNAME/ \
    | jq -r '.results[].name'

    echo
}

# ----------------------------------------
# 레포 삭제
# ----------------------------------------
repo_delete() {

    echo
    read -p "삭제할 레포 입력 (공백 기준) > " -a RM_REPOS

    echo
    echo "=== DELETE TARGET ==="

    for REPO in "${RM_REPOS[@]}"
    do
        echo "- $REPO"
    done

    echo
    read -p "정말 삭제할까요? [y/N] : " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "취소됨"
        return
    fi

    echo
    log_info "Deleting repositories..."

    for REPO in "${RM_REPOS[@]}"
    do
        HTTP_CODE=$(curl -s \
        -o /dev/null \
        -w "%{http_code}" \
        -X DELETE \
        -H "Authorization: JWT $TOKEN" \
        https://hub.docker.com/v2/repositories/$DOCKER_USERNAME/$REPO/)

        if [[ "$HTTP_CODE" == "202" || "$HTTP_CODE" == "204" ]]; then
            log_info "Deleted: $REPO"
        else
            log_error "Failed: $REPO (HTTP $HTTP_CODE)"
        fi
    done

    echo
}

# ----------------------------------------
# 메뉴 출력
# ----------------------------------------
show_menu() {

    echo "================================="
    echo " Docker Hub Manager"
    echo "================================="
    echo "1. 레포 목록 조회"
    echo "2. 레포 삭제"
    echo "0. 종료"
    echo "================================="
    echo
}

# ----------------------------------------
# 메인
# ----------------------------------------
docker_login

while true
do
    show_menu
    read -p "메뉴 선택 > " MENU

    case $MENU in
        1)
            repo_list
            ;;
        2)
            repo_delete
            ;;
        0)
            log_info "Exit"
            exit 0
            ;;
        *)
            log_error "잘못된 메뉴입니다"
            ;;
    esac

done
