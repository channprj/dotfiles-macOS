# default locale
export LC_ALL=en_US.UTF-8

# zsh and oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
export UPDATE_ZSH_DAYS=13
ZSH_THEME="dpoggi"

# zsh options
HISTFILE=~/.zsh_history
HIST_STAMPS="yyyy-mm-dd"
SAVEHIST=5000
HISTSIZE=5000
setopt EXTENDED_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE
setopt HIST_NO_STORE
setopt HIST_VERIFY
setopt EXTENDED_HISTORY
setopt HIST_SAVE_NO_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
zstyle ':completion:*' verbose yes
# zstyle ':completion:*:descriptions' format $'%F{green}%d'
# zstyle ':completion:*:messages' format $'%F{yellow}%d'
zstyle ':completion:*:descriptions' format $'\e[00;32m%d'
zstyle ':completion:*:messages' format $'\e[00;33m%d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:manuals' separate-sections true

# plugins
plugins=(
  git
  github
  brew
  docker
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# performance tweaks
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zshcache  # specify cache file to use (not added to repo: separate file for each machine)

# welcome message
echo "\n"
figlet -f "ANSI Shadow" "  CHANN" | lolcat
echo "\t\t\t...with Macbook Pro 16' M2 Pro"
echo "--------------------------------------------------------------------------------"
# neofetch -E
w
echo "--------------------------------------------------------------------------------"

# end of zsh
source $ZSH/oh-my-zsh.sh
autoload -U compinit && compinit

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# iterm2 shell integration
# refer: https://www.iterm2.com/documentation-shell-integration.html
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# aliases
source ~/.zshalias
source ~/.zshalias-company

# env
source ~/.zshenv

# functions
source ~/.zshfunc

