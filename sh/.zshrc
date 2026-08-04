# Interactive shell configuration. Environment and PATH defaults live in .zshenv.

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
export UPDATE_ZSH_DAYS=13
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

ZSH_THEME="dpoggi"
[[ -r "$ZSH_CUSTOM/themes/dpoggi-timestamp.zsh-theme" ]] &&
  ZSH_THEME="dpoggi-timestamp"

HISTFILE="$HOME/.zsh_history"
HIST_STAMPS="yyyy-mm-dd"
SAVEHIST=5000
HISTSIZE=5000
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_NO_STORE
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format $'\e[00;32m%d'
zstyle ':completion:*:messages' format $'\e[00;33m%d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.zshcache"

# Homebrew changes PATH and architecture-specific prefixes. It is optional.
if (( $+commands[brew] )); then
  eval "$(brew shellenv)"
fi

plugins=()
_dotfiles_add_omz_plugin() {
  local plugin="$1"
  if [[ -d "$ZSH/plugins/$plugin" || -d "$ZSH_CUSTOM/plugins/$plugin" ]]; then
    plugins+=("$plugin")
  fi
}
for plugin in git github brew docker zsh-completions; do
  _dotfiles_add_omz_plugin "$plugin"
done
if [[ -t 0 && -o zle ]]; then
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    _dotfiles_add_omz_plugin "$plugin"
  done
fi
unset plugin
unfunction _dotfiles_add_omz_plugin

# Oh My Zsh initializes completion. The fallback handles a minimal machine
# without Oh My Zsh, so compinit is executed exactly once either way.
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit
  compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"
fi

# Optional interactive integrations.
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
if (( $+commands[pyenv] )); then
  eval "$(pyenv init -)"
  _dotfiles_init="$(pyenv virtualenv-init - 2>/dev/null)" && eval "$_dotfiles_init"
fi
if (( $+commands[goenv] )); then
  eval "$(goenv init -)"
fi
[[ -r "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
[[ -r "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env"
if (( $+commands[uv] )); then
  eval "$(uv generate-shell-completion zsh)"
fi
if (( $+commands[uvx] )); then
  eval "$(uvx --generate-shell-completion zsh)"
fi
unset _dotfiles_init

if [[ -t 0 ]] && (( $+commands[tty] )); then
  GPG_TTY="$(tty 2>/dev/null)" && export GPG_TTY
fi

[[ -r "$HOME/.zshalias" ]] && source "$HOME/.zshalias"
[[ -r "$HOME/.zshalias-company" ]] && source "$HOME/.zshalias-company"
[[ -r "$HOME/.zshfunc" ]] && source "$HOME/.zshfunc"
[[ -r "$HOME/.zshexec" ]] && source "$HOME/.zshexec"
[[ -r "$HOME/.zsh-welcome" ]] && source "$HOME/.zsh-welcome"

[[ -t 0 && -o zle && -r "$HOME/.fzf.zsh" ]] && source "$HOME/.fzf.zsh"
[[ -r "$HOME/.iterm2_shell_integration.zsh" ]] && source "$HOME/.iterm2_shell_integration.zsh"
[[ -r "$HOME/.orbstack/shell/init.zsh" ]] && source "$HOME/.orbstack/shell/init.zsh"
[[ -r "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc" ]] &&
  source "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"
[[ -r "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc" ]] &&
  source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"
[[ -r "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# Preserve the existing Markdowner launcher policy.
export EDITOR="mdner --wait"
export VISUAL="mdner --wait"
