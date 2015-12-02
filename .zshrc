export ZSH=$HOME/.oh-my-zsh
ZSH_THEME="dpoggi"

## History
HIST_STAMPS="yyyy-mm-dd"
#HISTSIZE=1000                # lines of history to maintain memory
SAVEHIST=500                 # lines of history to maintain in history file.
setopt EXTENDED_HISTORY      # save timestamp and runtime information

plugins=(git)

export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

# pyenv init
export PATH="$HOME/.pyenv/shims:$PATH"
eval "$(pyenv init -)"

# virtualenv init
eval "$(pyenv virtualenv-init -)"

# autoenv automatically execute
source /usr/local/opt/autoenv/activate.sh

# added by travis gem
[ -f /Users/CHANN/.travis/travis.sh ] && source /Users/CHANN/.travis/travis.sh
