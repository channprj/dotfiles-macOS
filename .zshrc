### zsh and oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
export UPDATE_ZSH_DAYS=13
ZSH_THEME="dpoggi"
ENABLE_CORRECTION="true"

### welcome message
echo "---------------";
echo "Welcome aboard!"
echo "---------------";
w;

### alias
alias pp='python'
alias gclone='git clone'
alias gogit='cd ~/git'
alias gotil='cd ~/git/TIL/content/posts'
alias ipconfig='curl ifconfig.co'

export UPDATE_ZSH_DAYS=13
ENABLE_CORRECTION="true"

### history
HIST_STAMPS="yyyy-mm-dd"
SAVEHIST=1000
setopt EXTENDED_HISTORY

plugins=(git)

### ohmyzsh
source $ZSH/oh-my-zsh.sh

### path
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/share/git-core/contrib/diff-highlight/"

### nvm
#export NVM_DIR=~/.nvm
#source $(brew --prefix nvm)/nvm.sh

### pyenv, virtualenv
export PATH="$HOME/.pyenv/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

### autoenv
source /usr/local/opt/autoenv/activate.sh

### travis gem
#[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

### powerline: too slow
# . /Users/CHANN/.pyenv/versions/3.4.2/lib/python3.4/site-packages/powerline/bindings/zsh/powerline.zsh

### golang
export GOPATH=$HOME/Go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

### fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
