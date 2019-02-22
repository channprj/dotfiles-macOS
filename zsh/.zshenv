# for dev
export GOROOT_BOOTSTRAP="/usr/local/bin/go"
export ANDROID_HOME="/Users/chann/Library/Android/sdk"
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk-bundle

# system
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/share/git-core/contrib/diff-highlight/"

# config
export GREP_OPTIONS='--color=auto'
export GPG_TTY=$(tty)

# pyenv
export PATH="$HOME/.pyenv/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# autoenv
#source /usr/local/opt/autoenv/activate.sh

# travis gem
#[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

# golang
export GOPATH=$HOME/go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

# rust
export PATH=$PATH:$HOME/.cargo/bin

# android
export PATH=${PATH}:/Users/chann/library/android/sdk/tools:${PATH}:/Users/chann/library/android/sdk/platform-tools

# eosio
export PATH="/usr/local/opt/llvm@4/bin:$PATH"

