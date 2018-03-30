# zsh and oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
export UPDATE_ZSH_DAYS=13
ZSH_THEME="dpoggi-timestamp"
source $ZSH/oh-my-zsh.sh

# zsh options
HISTFILE=~/.zsh_history
HIST_STAMPS="yyyy-mm-dd"
SAVEHIST=10000
HISTSIZE=10000
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

# plugins
plugins=(git, github, brew)

# performance tweaks
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zshcache  # specify cache file to use (not added to repo: separate file for each machine)


# welcome message
echo "--------------------------------------------------------------------------------"
w
#screenfetch -E
echo "--------------------------------------------------------------------------------"

# env
source ~/.zshenv

# aliases
source ~/.zshalias

# functions
source ~/.zshfunc


# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh


# serverless
# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh

# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
[[ -f /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh ]] && . /usr/local/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh

