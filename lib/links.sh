# shellcheck shell=bash
#
# Source of truth for the dotfile symlink mapping.
# Sourced by both install.sh and uninstall.sh.
#
# Format: "<repo-relative-source>:<HOME-relative-destination>"
LINKS=(
  # shell
  "sh/.zshrc:.zshrc"
  "sh/.zshenv:.zshenv"
  "sh/.zshalias:.zshalias"
  "sh/.zshfunc:.zshfunc"
  "sh/.zshexec:.zshexec"
  "sh/.zsh-welcome:.zsh-welcome"
  "sh/.direnvrc:.direnvrc"
  "sh/Brewfile:Brewfile"
  # git
  "git/.gitconfig:.gitconfig"
  "git/.gitignore_global:.gitignore_global"
  "git/.tigrc:.tigrc"
  # vim
  "editor/.vimrc:.vimrc"
  "editor/.vim:.vim"
  # ghostty (terminal)
  "editor/ghostty:.config/ghostty/config"
  # gnupg
  "sh/gnupg/gpg-agent.conf:.gnupg/gpg-agent.conf"
  # oh-my-zsh custom theme
  "sh/zsh/custom-zsh-theme/dpoggi-timestamp.zsh-theme:.oh-my-zsh/custom/themes/dpoggi-timestamp.zsh-theme"
)
