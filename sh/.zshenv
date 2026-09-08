# Environment shared by interactive and non-interactive Zsh processes.
# Keep this file quiet: prompts, completions, and command hooks belong in .zshrc.

# Force an English locale regardless of what the terminal or system region
# hands down (macOS passes LANG=ko_KR.UTF-8 here).
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export GOPATH="${GOPATH:-$HOME/go}"
export GOENV_ROOT="${GOENV_ROOT:-$HOME/.goenv}"
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk-bundle}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
export ENABLE_BACKGROUND_TASKS="${ENABLE_BACKGROUND_TASKS:-1}"

# Zsh keeps PATH and the `path` array synchronized. The uniqueness attribute
# preserves the incoming system PATH while removing duplicate entries.
typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/.opencode/bin"
  "$HOME/.cargo/bin"
  "$HOME/.npm-global/bin"
  "$BUN_INSTALL/bin"
  "$PNPM_HOME"
  "$GOENV_ROOT/bin"
  "$GOPATH/bin"
  "$ANDROID_HOME/tools"
  "$ANDROID_HOME/platform-tools"
  # pyenv and its shims must precede Homebrew/system Python in non-interactive
  # shells too; interactive initialization still lives in .zshrc.
  "$PYENV_ROOT/bin"
  "$PYENV_ROOT/shims"
  "/opt/homebrew/bin"
  "/opt/homebrew/sbin"
  "/opt/homebrew/opt/libpq/bin"
  "/usr/local/bin"
  "/usr/local/sbin"
  $path
)

[[ -d "/Applications/Keybase.app/Contents/SharedSupport/bin" ]] &&
  path+=("/Applications/Keybase.app/Contents/SharedSupport/bin")

export PATH
[[ -r "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Select the GitHub account when gh runs, including in non-interactive Zsh.
gh() {
  emulate -L zsh

  if (( ! $+commands[gh] )); then
    print -u2 "gh: GitHub CLI is not installed or not in PATH"
    return 127
  fi

  # Explicit credentials and authentication management remain under user control.
  if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ||
        ( "${1:-}" == auth && "${2:-}" != status ) ]]; then
    command gh "$@"
    return $?
  fi
  case "${1:-}" in
    '' | help | --help | -h | --version | version | completion)
      command gh "$@"
      return $?
      ;;
  esac

  local github_host="${GH_HOST:-github.com}"
  local previous_arg="" arg
  for arg in "$@"; do
    if [[ "$previous_arg" == --hostname ||
          ( "$1" == auth && "$previous_arg" == -h ) ]]; then
      github_host="$arg"
    fi
    [[ "$arg" == --hostname=* ]] && github_host="${arg#*=}"
    previous_arg="$arg"
  done
  if [[ "${github_host:l}" != github.com ]]; then
    command gh "$@"
    return $?
  fi

  local github_user=channprj
  local corporate_root="$HOME/workspace/corp"
  corporate_root="${corporate_root:A}"
  if [[ "${PWD:A}" == "$corporate_root" || "${PWD:A}" == "$corporate_root/"* ]]; then
    github_user=chan-park_trueb
  fi

  local active_user=""
  active_user="$(command gh config get user --host github.com 2>/dev/null)" || active_user=""
  if [[ "$active_user" != "$github_user" ]]; then
    command gh auth switch --hostname github.com --user "$github_user" >/dev/null || return $?
  fi

  # Show the stored accounts normally when inspecting authentication status.
  if [[ "$1" == auth ]]; then
    command gh "$@"
    return $?
  fi

  # Pin this process to its account if another terminal switches the shared config.
  local github_token=""
  github_token="$(command gh auth token --hostname github.com --user "$github_user")" || return $?
  if [[ -z "$github_token" ]]; then
    print -u2 "gh: no saved token for $github_user; run gh auth login --hostname github.com"
    return 1
  fi
  GH_TOKEN="$github_token" command gh "$@"
}
