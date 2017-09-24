### zsh and oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
export UPDATE_ZSH_DAYS=13
ZSH_THEME="dpoggi-timestamp"
#ZSH_THEME="dpoggi"
#ZSH_THEME="bullet-train"
#ZSH_THEME="powerlevel9k/powerlevel9k"
#ENABLE_CORRECTION="true"

### option for ZSH_THEME="bullet-train"
#BULLETTRAIN_PROMPT_ORDER=(
#  time
#  context
#  dir
#  virtualenv
#  git
#)
#BULLETTRAIN_VIRTUALENV_BG=cyan

### welcome message
echo "--------------------------------------------------------------------------------"
w
#screenfetch -E
echo "--------------------------------------------------------------------------------"


### alias
alias pp="python"
alias go_git="cd ~/git"
alias go_key="cd ~/key"
alias go_til="cd ~/git/TIL/content/posts"
alias flushdns="sudo killall -HUP mDNSResponder"  # for Sierra
alias clean_launchpad="defaults write com.apple.dock ResetLaunchPad -bool true; killall Dock"  # for Sierra
alias ipconfig="curl ifconfig.co"
alias chrome="/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"
alias chrome-canary="/Applications/Google\ Chrome\ Canary.app/Contents/MacOS/Google\ Chrome\ Canary"
alias chromium="/Applications/Chromium.app/Contents/MacOS/Chromium"
alias rm_ds="find . -name '.DS_Store' -type f -delete -print"  # remove .DS_Store recursively

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
#. /Users/CHANN/.pyenv/versions/3.4.2/lib/python3.4/site-packages/powerline/bindings/zsh/powerline.zsh

### golang
export GOPATH=$HOME/Go
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

### fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

