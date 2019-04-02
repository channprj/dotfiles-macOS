# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/.local/bin:$HOME/bin

export PATH
export PS1="\[\e[0;32m\]\u\e[0m@\[\e[0;36m\]\h:\[\e[0;35m\]\w \e[0;31m$ \[\e[0m\]"

