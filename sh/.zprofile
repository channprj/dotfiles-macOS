# Login shells only. Interactive setup stays in .zshrc.
# /etc/zprofile runs path_helper after .zshenv and moves system paths ahead of
# the user paths. Codex and Grok both start commands with `zsh -lc`, so apply
# .zshenv again and both CLIs keep the same PATH as an interactive shell.
# ~/.local/bin holds the codex and grok symlinks; ~/.grok/bin is added there.

[[ -r "$HOME/.orbstack/shell/init.zsh" ]] &&
  source "$HOME/.orbstack/shell/init.zsh"
[[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]] &&
  source "${ZDOTDIR:-$HOME}/.zshenv"
