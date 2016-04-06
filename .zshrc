### oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
ZSH_THEME="dpoggi"

echo "Welcome aboard!";w;

### temp project DB
export DB_NAME="db_name"
export DB_ID="db_id"
export DB_PW="db_pw"

### useful sentence
export MYGIT="https://github.com/channprj"

### alias
alias pp='python'
alias gclone='git clone'
alias gogit='cd ~/git'
alias gotil='cd ~/git/TIL'

### history
HIST_STAMPS="yyyy-mm-dd"
# HISTSIZE=1000                # lines of history to maintain memory
SAVEHIST=500                 # lines of history to maintain in history file.
setopt EXTENDED_HISTORY      # save timestamp and runtime information

# plugins=(git)

### user configuration
export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

### nvm init
export NVM_DIR=~/.nvm
source $(brew --prefix nvm)/nvm.sh

### pyenv init
export PATH="$HOME/.pyenv/shims:$PATH"
eval "$(pyenv init -)"

### virtualenv init
eval "$(pyenv virtualenv-init -)"

### autoenv automatically execute
source /usr/local/opt/autoenv/activate.sh

### travis gem init
[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

### powerline: too slow
# . /Users/CHANN/.pyenv/versions/3.4.2/lib/python3.4/site-packages/powerline/bindings/zsh/powerline.zsh

### golang init
export GOPATH=$HOME/golang
export GOROOT=/usr/local/bin/go
PATH=$PATH:$GOROOT/bin:$GOPATH/bin
