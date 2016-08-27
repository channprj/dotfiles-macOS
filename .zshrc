### oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
ZSH_THEME="dpoggi"

echo "Welcome aboard!";w;

### temp django project DB
export DB_NAME="django"
export DB_ID="django"
export DB_PW="django"

### useful sentence
export MYGIT="https://github.com/channprj"

### alias
alias pp='python'
alias gclone='git clone'
alias gogit='cd ~/git'
alias gotil='cd ~/git/TIL/content/posts'
alias ipconfig='curl ifconfig.co'

### history
HIST_STAMPS="yyyy-mm-dd"
SAVEHIST=500
setopt EXTENDED_HISTORY

# plugins=(git)

### user configuration
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/share/git-core/contrib/diff-highlight/"
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

### nvm
export NVM_DIR=~/.nvm
source $(brew --prefix nvm)/nvm.sh

### pyenv, virtualenv
export PATH="$HOME/.pyenv/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

### autoenv
source /usr/local/opt/autoenv/activate.sh

### travis gem
[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

### powerline: too slow
# . /Users/CHANN/.pyenv/versions/3.4.2/lib/python3.4/site-packages/powerline/bindings/zsh/powerline.zsh

### golang
export GOPATH=$HOME/golang
export GOROOT=/usr/local/bin/go
PATH=$PATH:$GOROOT/bin:$GOPATH/bin
