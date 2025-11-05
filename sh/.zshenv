# autoload
autoload -Uz compinit && compinit

# add local bin to path
export PATH="$HOME/.local/bin:$PATH"

# for dev
export GOROOT_BOOTSTRAP="/usr/local/bin/go"
export ANDROID_HOME="/Users/channprj/Library/Android/sdk"
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk-bundle

# system
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/opt/git/share/git-core/contrib/diff-highlight"
export PATH=$PATH:/Applications/Keybase.app/Contents/SharedSupport/bin
export PATH=$PATH:$HOME/bin

# config
export GREP_OPTIONS='--color=auto'
export GPG_TTY=$(tty)

# brew
eval "$(/opt/homebrew/bin/brew shellenv)"

# direnv
eval "$(direnv hook zsh)"

# pyenv
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# golang
export GOPATH=$HOME/go
export GOROOT=/opt/homebrew/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

# goenv
export GOENV_ROOT="$HOME/.goenv"
export PATH="$GOENV_ROOT/bin:$PATH"
eval "$(goenv init -)"

# rust
export PATH=$PATH:$HOME/.cargo/bin
. "$HOME/.cargo/env"

# node
export PATH=$PATH:$HOME/.npm-global/bin

# psql
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# android
export PATH=${PATH}:${HOME}/library/android/sdk/tools:${PATH}:/Users/channprj/library/android/sdk/platform-tools

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# local
export PATH="$HOME/.local/bin:$PATH"

# uv
. "$HOME/.local/bin/env"
eval "$(uv generate-shell-completion zsh)"
eval "$(uvx --generate-shell-completion zsh)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

