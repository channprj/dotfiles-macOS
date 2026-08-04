# shellcheck shell=bash
#
# Static source-of-truth for managed symlinks.
# Format: "<repo-relative-source>:<HOME-relative-destination>"

# shellcheck disable=SC2034
LINKS_DEFAULT=(
  "sh/.zshrc:.zshrc"
  "sh/.zshenv:.zshenv"
  "sh/.zshalias:.zshalias"
  "sh/.zshfunc:.zshfunc"
  "sh/.zshexec:.zshexec"
  "sh/.zsh-welcome:.zsh-welcome"
  "sh/.direnvrc:.direnvrc"
  "git/.gitconfig:.gitconfig"
  "git/.gitignore_global:.gitignore_global"
  "git/.tigrc:.tigrc"
  "editor/.vimrc:.vimrc"
  "editor/.vim:.vim"
  "editor/nvim:.config/nvim"
)

# shellcheck disable=SC2034
LINKS_TERMINAL=(
  "editor/ghostty:.config/ghostty/config"
  "sh/zsh/custom-zsh-theme/dpoggi-timestamp.zsh-theme:.oh-my-zsh/custom/themes/dpoggi-timestamp.zsh-theme"
)

# shellcheck disable=SC2034
LINKS_GNUPG=(
  "sh/gnupg/gpg-agent.conf:.gnupg/gpg-agent.conf"
)

# shellcheck disable=SC2034
LINKS_BREW=(
  "sh/Brewfile:Brewfile"
)
