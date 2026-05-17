# 💾 Sy_Scripts

- 서버 운영하면서 귀찮아서 만든 **개인 운영용 쉘 스크립트 모음**
- 원격 서버 명령 실행, 파일 배포, 시간 동기화, 로그 정리, PostgreSQL 쿼리, Docker Hub 레포 관리 같은 반복 작업을 자동화하기 위해 작성됨

---
<br>

---
## 📁 디렉터리 구조

```bash
Sy_Scripts/
├── README.md
├── .gitignore                # .env, 로그, 캐시, 실행파일 제외
├── functions.sh              # 공통 함수 / 환경변수 / 서버 설정 로드
├── cmd_all.sh                # 여러 서버에 동일 명령 실행
├── scp_all.sh                # 여러 서버에 파일/디렉터리 복사
├── sync_time_clock.sh        # 서버 시간 / 하드웨어 클럭 동기화
├── clean_old_logs.sh         # 오래된 로그 파일 정리
├── conf/
│   └── server.properties     # 서버 IP / PostgreSQL 설정
├── docker/
│   └── control_docker.sh     # Docker Hub 레포 목록 조회 / 삭제
└── postgresql/
    └── sql.sh                # PostgreSQL 쿼리 실행
```
---
<br>

## ⚠️ 무조건 필요한 설정 (안 하면 안 됨)
### 1️⃣ 작업 디렉터리 고정
- 현재 스크립트들은 `.env`의 `MY_DIR` 값을 기준으로 공통 함수를 로드함
- 프로젝트 루트에 `.env` 파일이 필요함

```bash
cat .env
MY_DIR=/work/jsy
```
- `functions.sh`는 자기 위치 기준으로 `.env`, `conf/server.properties`를 로드함
- `cmd_all.sh`, `scp_all.sh`, `sync_time_clock.sh`, `clean_old_logs.sh`는 현재 디렉터리의 `./.env`를 먼저 로드함
- `docker/control_docker.sh`, `postgresql/sql.sh`는 상위 디렉터리의 `../.env`를 먼저 로드함
- 작업 디렉터리가 바뀌면 `.env`의 `MY_DIR`만 먼저 확인하면 됨
---
### 2️⃣ 모든 스크립트 공통 헤더 (필수)
- 스크립트 위치에 따라 `.env` 경로만 맞춰서 사용
```bash
#!/bin/bash

# 환경변수 로드
set -a
. ./.env
set +a

# 공통 함수 로드
. ${MY_DIR}/Sy_Scripts/functions.sh
```

- 하위 디렉터리 스크립트는 아래처럼 상위 `.env`를 로드함
```bash
set -a
. ../.env
set +a

. ${MY_DIR}/Sy_Scripts/functions.sh
```
---
<br>

## 🧩 서버 설정 파일
- `conf/server.properties`
- 서버 IP와 PostgreSQL 접속 정보를 한 군데 모아둠
```bash
# Server
SERVER_IPS=(
  "192.168.56.60"
  "192.168.56.61"
  "192.168.56.62"
)

# PostgreSQL
POSTGRES_HOST="192.168.122.59"
POSTGRES_PORT="5432"
POSTGRES_DB="job_pro"
POSTGRES_USER="sjj"
POSTGRES_PASSWORD="<password>"
```
- `functions.sh`에서 이 파일을 로드함
- PostgreSQL 관련 함수는 여기 있는 값을 사용함
- 실제 파일에는 비밀번호가 들어가 있으니 공개 저장소에 올릴 때는 분리하거나 마스킹 필요
---
<br>

## 🛠 공통 함수 (functions.sh)
- `.env`와 `conf/server.properties`를 로드하고, 자주 쓰는 함수들을 정의함
- 현재 포함된 기능
  - `log_info` : INFO 로그 출력
  - `log_error` : ERROR 로그 출력
  - `POSTGRES_sql_exec` : PostgreSQL 쿼리 실행
  - `DOCKER_get_token` : Docker Hub JWT 토큰 발급
- 예시 살짝만..
```bash
#!/bin/bash

# 현재 functions.sh 위치 기준 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 환경변수 로드
set -a
. "${SCRIPT_DIR}/.env"
set +a

# 시스템 공통 환경 변수 import
. ${SCRIPT_DIR}/conf/server.properties

log_info() {
    echo "[INFO ] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

POSTGRES_sql_exec() {
    PGPASSWORD=$POSTGRES_PASSWORD \
    psql -h $POSTGRES_HOST \
         -p $POSTGRES_PORT \
         -U $POSTGRES_USER \
         -d $POSTGRES_DB \
         -c "$1" -At
}

DOCKER_get_token() {
    curl -s \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{\"username\":\"$DOCKER_USERNAME\",\"password\":\"$DOCKER_PASSWORD\"}" \
    https://hub.docker.com/v2/users/login/ \
    | jq -r .token
}
```
---
<br>

## ✍️ 스크립트 작성 예제 ( cmd_all.sh )
```bash
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
```

- 실행 예시
```bash
./cmd_all.sh "hostname"
./cmd_all.sh "df -h"
```

- 현재 스크립트별 역할
```bash
./cmd_all.sh "<cmd>"
# ap, s1, s2 서버에 동일 명령 실행

./scp_all.sh "<src_path>" "<dst_path>"
# sn1, sn2, sn3, m1, m2, s1 서버로 파일/디렉터리 복사

./sync_time_clock.sh
# s1, s2 서버 시간을 현재 서버 시간으로 맞추고 hwclock 저장
# 이후 ap, s1, s2 시간을 출력해서 확인

./clean_old_logs.sh
# /work/jsy/job_project/logs 에서 5일 지난 파일 삭제

./postgresql/sql.sh "<query>"
# conf/server.properties의 PostgreSQL 정보로 쿼리 실행

./docker/control_docker.sh
# Docker Hub 로그인 후 레포 목록 조회 / 레포 삭제 메뉴 실행
```
---
<br>

## ❗ 주의사항 (미래의 나에게)
- 경로 하드코딩 금지 → `MY_DIR` 기준으로 맞추기
- 서버 IP / DB 접속 정보 직접 쓰지 말고 `conf/server.properties` 사용
- 민감정보는 `.env`나 별도 비공개 설정으로 분리하기
- `.env`는 `.gitignore`에 포함되어 있으니 저장소에는 안 올라감
- echo 말고 가능하면 `log_info` / `log_error`
- 하위 디렉터리에서 실행하는 스크립트는 `.env` 상대경로 조심하기
- Docker Hub 기능은 `curl`, `jq` 필요
- PostgreSQL 기능은 `psql` 필요
- 원격 실행 / 복사는 SSH alias 또는 접속 가능한 호스트명이 먼저 잡혀 있어야 함
- 삭제 계열 스크립트는 실행 전에 대상 경로 한 번 더 확인하기
---
