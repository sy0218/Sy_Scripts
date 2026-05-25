import requests
import sys
import os
from dotenv import load_dotenv

current_dir = os.path.dirname(os.path.abspath(__file__))
env_path = os.path.join(current_dir, "..", ".env")
load_dotenv(dotenv_path=env_path)

# ==========================================
# 전역 변수 및 환경 변수
# ==========================================
PIPELINE_KEEP_COUNT = 5  # 보존할 최신 파이프라인 개수

# env 값 가져오기
PRIVATE_TOKEN = os.getenv("GITLAB_TOKEN")
PROJECT_PATH = os.getenv("GITLAB_PROJECT_PATH")
GITLAB_URL = "https://gitlab.com"

# .env 파일 체크
if not PRIVATE_TOKEN or not PROJECT_PATH:
    print("에러: .env 파일을 찾지 못함", file=sys.stderr)
    sys.exit(1)

# 깃랩 API 옵션 조정
SAFE_PROJECT_PATH = PROJECT_PATH.replace("/", "%2F")
BASE_URL = f"{GITLAB_URL}/api/v4/projects/{SAFE_PROJECT_PATH}/pipelines"
HEADERS = {"PRIVATE-TOKEN": PRIVATE_TOKEN}
PARAMS = {"per_page": 100, "sort": "desc"}

def _CI_PIPELINE_DELETE():
    """파이프라인 목록 조회부터 조건에 따른 삭제까지 전담하는 함수"""
    print(f"[{PROJECT_PATH}] 프로젝트 파이프라인 목록 조회 중..")
    response = requests.get(BASE_URL, headers=HEADERS, params=PARAMS)

    if response.status_code != 200:
        print(f"에러코드: {response.status_code}", file=sys.stderr)
        return

    pipelines = response.json()
    pipelines_count = len(pipelines)

    print(f"총 {pipelines_count}개의 파이프라인 존재")

    targets_to_delete = pipelines[PIPELINE_KEEP_COUNT:] if pipelines_count > PIPELINE_KEEP_COUNT else []
    
    if not targets_to_delete:
        print(f"보존 개수({PIPELINE_KEEP_COUNT}개) 이하로 남아 삭제할 파이프라인이 없습니다.")
        return

    print(f"최근 {PIPELINE_KEEP_COUNT}개를 제외한 {len(targets_to_delete)}개의 파이프인 삭제")

    for pipe in targets_to_delete:
        pipe_id = pipe.get("id")
        pipe_status = pipe.get("status")
        pipe_ref = pipe.get("ref")

        delete_url = f"{BASE_URL}/{pipe_id}"
        del_response = requests.delete(delete_url, headers=HEADERS)

        if del_response.status_code == 204:
            print(f"  [성공] #{pipe_id} 삭제 완료 (Branch: {pipe_ref}, 상태: {pipe_status})")
        else:
            print(f"  [실패] #{pipe_id} 삭제 실패 (에러코드: {del_response.status_code})", file=sys.stderr)

    print("삭제 완료")
   
   
def main():
    while True:
        print("\n==========================================")
        print(f" GitLab 관리 도구 (주의: 코드 상단 전역변수 확인!)")
        print("==========================================")
        print(" [1] 구형 파이프라인 목록 조회 및 정리 실행")
        print(" [0] 또는 [EXIT] 프로그램 종료")
        print("==========================================")

        choice = input("원하는 작업 번호를 입력하세요: ").strip().upper()

        if choice in ["0", "EXIT"]:
            print("프로그램을 종료합니다. ㅂㅇㅂㅇ")
            break

        elif choice == "1":
            _CI_PIPELINE_DELETE()
        else:
            print(f"잘못된 입력입니다. 1, 0, EXIT 중 하나를 입력해주세요.")


if __name__ == "__main__":
    main()
