<p align="center">
  <img src="https://github.com/channprj/dotfiles-macOS/raw/main/assets/img/terminal.png" alt="Terminal screenshot" width="600">
</p>

# Dotfiles

macOS용 개인 설정 저장소입니다. 기존 설정을 설치 영수증과 함께 백업한 뒤 저장소
파일을 심링크하며, 언인스톨할 때 설치 전 상태로 되돌립니다. 설정이 바로 호출하는
명령과 코딩 CLI만 없을 때 설치합니다. 나머지 Homebrew 패키지, GUI 앱, 브라우저
설정은 자동 설치하지 않습니다.

구현 계약과 안전 기준은 [PRD](docs/prd/2026-08-04-dotfiles-management-prd.md)에
정리되어 있습니다.

## 빠른 시작

```sh
git clone https://github.com/channprj/dotfiles-macOS.git ~/dotfiles
cd ~/dotfiles

./install.sh --dry-run
./install.sh
```

설치기는 없는 명령만 설치합니다. 이미 있으면 다시 설치하지 않습니다.

| 명령 | 없을 때 |
| --- | --- |
| Zsh 플러그인 3종 | `brew install` |
| `delta`, `git-lfs` | `brew install git-delta`, `brew install git-lfs` |
| `claude`, `codex`, `grok`, `opencode`, `agy` | 각 프로젝트의 공식 설치 스크립트 |

Git 설정은 `pager = delta`와 Git LFS filter를 쓰므로 이 둘이 없으면 `git diff`와
LFS checkout이 바로 실패합니다. Neovim, fzf, ripgrep, fd, curl, C 컴파일러는
그대로 경고만 하고 설치하지 않습니다. `brew bundle`도 실행하지 않습니다.

한 도구가 실패해도 나머지 설치와 심링크는 계속합니다. 끝난 뒤 실패한 도구 이름,
로그 경로, 로그 내용을 출력하고 종료 코드는 1입니다. dry-run은 설치 예정 목록만
보여 줍니다. 이렇게 설치된 명령은 dotfiles 백업 트랜잭션에 포함되지 않고
언인스톨할 때 제거되지 않습니다. Homebrew가 없으면 brew 항목만 실패로 기록합니다.

`--dry-run`은 각 대상의 절대 경로, 저장소 원본, 적용 방식, 현재 파일 종류,
백업 예정 경로를 출력하며 파일, 디렉터리, 백업을 만들지 않습니다. 실제 설치 전
항상 먼저 실행하는 것을 권장합니다. 터미널에서는 작업 종류와 주요 경로를 자동으로
컬러 하이라이트하며, `NO_COLOR=1 ./install.sh --dry-run`으로 색상을 끌 수 있습니다.

## 설치 범위

인자 없는 기본 설치는 다음 설정을 관리합니다.

| 그룹 | 저장소 원본 | 홈 대상 |
| --- | --- | --- |
| Zsh | `.zshrc`, `.zshenv`, `.zprofile`, `.zshalias`, `.zshfunc`, `.zshexec`, `.zsh-welcome` | `~/`의 같은 이름 |
| Direnv | `sh/.direnvrc` | `~/.direnvrc` |
| Git | `.gitconfig`, `.gitconfig-corp`, `.gitignore_global`, `.tigrc` | `~/`의 같은 이름 |
| Vim | `editor/.vimrc`, `editor/.vim` | `~/.vimrc`, `~/.vim` |
| LazyVim | `editor/nvim` | `~/.config/nvim` |
| Herdr | `herdr/config.toml` | `~/.config/herdr/config.toml` |
| Grok | `grok/config.toml`, `grok/statusline.sh` | `~/.grok/config.toml`, `~/.grok/statusline.sh` |

전체 매핑은 [lib/links.sh](lib/links.sh)이 단일 기준입니다.

선택 설정은 모듈을 명시해야 설치합니다.

```sh
./install.sh --module terminal
./install.sh --module terminal --module gnupg
./install.sh --all
```

| 모듈 | 관리 대상 |
| --- | --- |
| `terminal` | Ghostty 설정, `dpoggi-timestamp` Oh My Zsh 테마 |
| `gnupg` | `~/.gnupg/gpg-agent.conf` |
| `brew` | `~/Brewfile` 심링크 |

`--module`은 반복할 수 있고 중복 지정은 한 번만 처리됩니다. 나중에 모듈을
추가하면 기존 활성 설치 영수증에 누적됩니다. `--all`은 세 모듈의 합집합이며
`brew bundle`을 실행하지 않습니다.

## 백업과 설치 영수증

기존 일반 파일, 디렉터리, 외부 심링크는 기본적으로
`~/.dotfiles-backup` 아래로 이동합니다. 이미 이 저장소의 올바른 원본을 가리키는
심링크는 원본이 없는 `adopted` 항목으로 인수합니다.

```text
~/.dotfiles-backup/
├── active -> installations/<installation-id>
└── installations/<installation-id>/
    ├── manifest.tsv
    ├── repository-path
    ├── parents.tsv
    ├── originals/
    └── runs/*.tsv
```

백업 디렉터리는 권한 `0700`, 영수증 파일은 `0600`으로 생성합니다. 저장소를
옮긴 뒤 새 위치에서 `install.sh`를 다시 실행하면 영수증이 소유한 링크만 새
절대 경로로 갱신합니다. 같은 위치에서 반복 실행하면 백업과 링크를 바꾸지
않습니다.

백업 위치를 바꾸려면 설치와 언인스톨에 같은 값을 사용하세요.

```sh
DOTFILES_BACKUP_DIR=/secure/path ./install.sh --dry-run
DOTFILES_BACKUP_DIR=/secure/path ./install.sh
DOTFILES_BACKUP_DIR=/secure/path ./uninstall.sh
```

상대 경로, 심링크인 백업 루트, 관리 대상 내부의 백업 루트는 거부됩니다.

## 언인스톨과 복구

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

언인스톨 dry-run도 제거할 심링크, 복원할 원본 종류, 활성 영수증과 실제 백업
원본 경로, 복구 후 결과를 항목별로 보여줍니다.

언인스톨은 활성 영수증의 기본·선택 모듈 전체를 한 트랜잭션으로 복구합니다.
모든 대상이 기록된 심링크인지 먼저 검사하며, 하나라도 일반 파일로 바뀌었거나
링크 대상이 달라졌으면 아무것도 변경하지 않고 중단합니다. `--force`는
의도적으로 지원하지 않습니다.

충돌이 발생하면 사용자 변경을 별도 경로로 옮긴 뒤 `manifest.tsv`의
`installed_link_target`을 가리키는 심링크를 복원하고 dry-run을 다시 실행하세요.
실패 영수증의 결과가 `recovery-required`이면 `runs/*.tsv`와 `originals/`를
삭제하지 말고 먼저 남은 상태를 확인해야 합니다. 성공한 언인스톨은 소비한 활성
설치만 제거하며 기존 `vim-*`, `latest` 등 무관한 백업은 보존합니다.

## Synthetic로 Claude Code 실행

`synthetic_claude`는 Claude Code를 Synthetic의 Anthropic 호환 endpoint와
지정 모델로 실행합니다. `config`를 실행하면 macOS Keychain의 숨김 입력
프롬프트에서 API 키를 입력하고 저장할 수 있습니다. 같은 명령으로 기존 키를
갱신할 수 있으며, 명령 인자와 셸 기록에 키가 남지 않습니다. 키 설정에는
Claude Code가 설치되어 있지 않아도 됩니다.

```sh
source ~/.zshfunc
synthetic_claude config
synthetic_claude
synthetic_claude --help
```

시작 모델과 Opus 기본 모델은 `hf:zai-org/GLM-5.3-Flash`로 지정합니다.
시작 모델은 Claude 설정에 저장된 모델보다 우선 적용하며, `--model` 옵션을
직접 전달하면 해당 모델을 사용합니다.

`SYNTHETIC_API_KEY`가 이미 설정되어 있으면 해당 값을 우선 사용하고, 없으면
Keychain의 `synthetic.new.api-key` 항목을 자동으로 읽습니다. 일회성 키를 사용할
때만 다음처럼 현재 명령에 환경변수를 지정할 수 있습니다.

```sh
SYNTHETIC_API_KEY='<temporary-key>' synthetic_claude
```

Synthetic 관련 override는 실행한 Claude 자식 프로세스에만 적용됩니다. 명령이
끝나면 기존 셸 환경으로 자동 복귀하므로 별도 reset 명령은 필요하지 않으며,
평소처럼 `claude`를 실행하면 기존 provider 설정을 사용합니다. 저장한 키를
삭제하려면 다음 명령을 실행하세요.

```sh
security delete-generic-password -a "$USER" -s "synthetic.new.api-key"
```

## LazyVim과 패키지 준비

[LazyVim Starter](https://github.com/LazyVim/starter)의 고정 스냅샷과
`lazy-lock.json`, 로컬 `ambiwidth=single` 옵션을 추적합니다. 설치기는 구성만
연결하고 Neovim이나 플러그인을 실행하지 않습니다.

필요하면 패키지를 수동으로 준비합니다.

```sh
xcode-select --install
brew bundle --file sh/Brewfile
nvim
```

Neovim, Git, tree-sitter CLI, C 컴파일러, curl, fzf, ripgrep, fd가 주요 런타임
도구이며 lazygit은 선택 도구입니다. 자세한 현재 요구사항은
[LazyVim 설치 문서](https://www.lazyvim.org/installation)를 확인하세요.

## Herdr 설정과 세션 정리

기본 설치는 검토된 `herdr/config.toml`을 `~/.config/herdr/config.toml`로 연결합니다.
세션 상태, 로그, lock, backup과 Herdr가 생성·갱신하는 agent integration 파일은
machine-local runtime 자료이므로 추적하지 않습니다.

`hsa`는 현재 디렉터리 이름의 Herdr 세션에 연결합니다. 다음 명령은 같은 세션을
중지한 뒤 삭제합니다.

```sh
hsa delete
hsa delete --force  # 비대화형 실행 또는 확인 생략
hsa delete -f
```

기본 실행은 `y` 또는 `Y` 확인이 필요합니다. 실행 중 세션의 stop이 실패하면
delete를 호출하지 않으며, 이미 없는 세션은 성공으로 처리합니다.

## Grok 설정

기본 설치는 `grok/config.toml`과 `grok/statusline.sh`를 `~/.grok/`로 연결합니다.
상태줄 스크립트는 실행할 때 `~/.grok/auth.json`을 읽습니다. 그 파일과
`mcp_credentials.json`, 세션, 메모리, 로그, `trusted_folders.toml`은 이 저장소에
넣지 않습니다. MCP 헤더나 토큰을 `config.toml`에 적지 마세요.

## iTerm 세션 복원

`./install.sh`는 심링크와 함께 iTerm 탭 복원에 필요한 설정만 넣습니다.
iTerm 전체 설정 파일은 복사하지 않습니다. 심링크가 이미 맞아도 설치를 다시
실행하면 이 설정은 다시 맞춥니다. 언인스톨은 이 값을 되돌리지 않습니다.

- macOS `NSQuitAlwaysKeepsWindows`를 켭니다. 시스템 설정의 "응용 프로그램 종료 시 윈도우 닫기"가 꺼집니다. 이 값은 iTerm만이 아니라 모든 앱에 적용됩니다.
- iTerm은 시스템 윈도우 복원을 따르고, 세션 복원을 켜며, `Cmd-Q`가 실행 중인 작업을 종료하지 않습니다.

설정만 다시 맞추려면 다음을 실행합니다.

```sh
./utilities/iterm-session-restore.sh --dry-run
./utilities/iterm-session-restore.sh
```

iTerm이 켜져 있으면 종료할 때 예전 값을 덮어쓸 수 있습니다. 스크립트는 그때를
위해 종료 뒤에 한 번 더 씁니다. 그 첫 종료는 이미 켜져 있던 작업을 끝낼 수
있습니다. 다음 실행부터 탭이 돌아오고, 그 다음 `Cmd-Q`부터 작업이 유지됩니다.
재부팅하면 작업은 사라지고 탭과 작업 폴더만 돌아옵니다.

## 자동 설치하지 않는 자료

- `browser-extensions/`: Vimium, Safari CSS 등 브라우저에서 수동 가져오기
- `keyboard/`: 키보드 펌웨어와 macOS 키 매핑 자료
- `utilities/`: BetterTouchTool preset과 iTerm 키맵. 세션 복원 값만 설치기가 넣습니다.
- `agents/`: Codex/Claude 설정과 별도의 스킬 설치 자료
- `archive/`: 기본 설치에서 제외한 Vim 테마와 지원 종료 스크립트

`.reviews/`, `.diff-summaries/`, `.zshalias-company`, `.netrwhist` 같은 ignored
로컬 자료는 설치 정리나 언인스톨 대상이 아닙니다.

## 검증과 보안

```sh
brew install shellcheck gitleaks
./tests/run.sh
./scripts/check-secrets.sh
```

테스트는 macOS 기본 Bash 3.2에서 설치·롤백·충돌 차단·저장소 이동, Zsh 최소
환경 시작, Herdr 상태 행렬과 대화형 확인, LazyVim 스냅샷을 검증합니다. GitHub
Actions에서도 `macos-latest` 테스트와 전체 Git 이력 시크릿 스캔을 실행합니다.

시크릿 사고 대응 절차는 [SECURITY.md](SECURITY.md)를 따릅니다.

## 참고

- [Oh My Zsh external themes](https://github.com/ohmyzsh/ohmyzsh/wiki/External-themes#dpoggi-newline-timestamp)
- [dpoggi timestamp discussion](https://github.com/ohmyzsh/ohmyzsh/issues/7688#issuecomment-476947050)
- [simnalamburt/.dotfiles](https://github.com/simnalamburt/.dotfiles)
- [malkoG/dotfiles](https://github.com/malkoG/dotfiles)
