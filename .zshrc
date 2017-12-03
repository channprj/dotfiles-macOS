### zsh and oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
export UPDATE_ZSH_DAYS=13
ZSH_THEME="dpoggi-timestamp"
source $ZSH/oh-my-zsh.sh
#ZSH_THEME="dpoggi"
#ZSH_THEME="bullet-train"
#ZSH_THEME="powerlevel9k/powerlevel9k"
#ENABLE_CORRECTION="true"

# option for ZSH_THEME="bullet-train"
#BULLETTRAIN_PROMPT_ORDER=(
#  time
#  context
#  dir
#  virtualenv
#  git
#)
#BULLETTRAIN_VIRTUALENV_BG=cyan

# welcome message
echo "--------------------------------------------------------------------------------"
w
#screenfetch -E
echo "--------------------------------------------------------------------------------"

# aliases
source ~/.zshalias

plugins=(
	git
)

### history
HIST_STAMPS="yyyy-mm-dd"
SAVEHIST=1000
setopt EXTENDED_HISTORY

plugins=(git)

