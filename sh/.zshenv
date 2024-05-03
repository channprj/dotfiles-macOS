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
# for IntelMac
# export PATH="$HOME/.pyenv/shims:$PATH"
# eval "$(pyenv init -)"
# eval "$(pyenv virtualenv-init -)"
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# autoenv
#source /usr/local/opt/autoenv/activate.sh

# travis gem
#[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

# golang
export GOPATH=$HOME/go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

# goenv
export GOENV_ROOT="$HOME/.goenv"
export PATH="$GOENV_ROOT/bin:$PATH"
eval "$(goenv init -)"

# rust
export PATH=$PATH:$HOME/.cargo/bin

# node
export PATH=$PATH:$HOME/.npm-global/bin

# android
export PATH=${PATH}:${HOME}/library/android/sdk/tools:${PATH}:/Users/channprj/library/android/sdk/platform-tools
