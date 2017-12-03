# system
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/share/git-core/contrib/diff-highlight/"

# config
export GREP_OPTIONS='--color=auto'

# pyenv
export PATH="$HOME/.pyenv/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# autoenv
#source /usr/local/opt/autoenv/activate.sh

# travis gem
#[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

# golang
export GOPATH=$HOME/Go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

