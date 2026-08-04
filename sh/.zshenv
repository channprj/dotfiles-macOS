# Environment shared by interactive and non-interactive Zsh processes.
# Keep this file quiet: prompts, completions, and command hooks belong in .zshrc.

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export GOPATH="${GOPATH:-$HOME/go}"
export GOENV_ROOT="${GOENV_ROOT:-$HOME/.goenv}"
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
