# Archived legacy scripts

이 디렉터리의 스크립트는 실행 경로에서 제거한 기록 보관 자료입니다. 자동 설치나
Git hook으로 연결되지 않으며, 현재 환경에서 실행을 지원하지 않습니다.

- `upgrade_pip.py`: 제거된 pip 내부 API를 사용하고 패키지 이름을 셸 문자열로
  조합하므로 실행하지 않습니다.
- `imageoptim-pre-commit.sh`: 이 저장소에서 hook으로 설치되지 않았고 파일명 처리와
  실패 전파가 안전하지 않아 비활성화했습니다.

Git 기록은 `git log --follow -- <path>`로 확인할 수 있습니다.
