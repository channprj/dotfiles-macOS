<p align="center">
  <img src="https://github.com/channprj/dotfiles-macOS/raw/main/assets/img/terminal.png" alt="screenshot" width="600px">
</p>

# Dotfiles

My personal macOS dotfiles, symlinked into `$HOME` by a small install script.

## Quick start

```sh
git clone https://github.com/channprj/dotfiles-macOS.git ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run   # preview
./install.sh             # apply
```

Re-running `install.sh` is safe: links that already point at the repo are
left alone. The repo can live anywhere — the scripts auto-detect their
own location.

## What gets linked

| Source in repo                                             | Destination                                                |
| ---------------------------------------------------------- | ---------------------------------------------------------- |
| `sh/.zshrc`, `.zshenv`, `.zshalias`, `.zshfunc`, `.zshexec` | `~/.zshrc`, `~/.zshenv`, `~/.zshalias`, ...                |
| `sh/.zsh-welcome`, `sh/.direnvrc`, `sh/Brewfile`           | `~/.zsh-welcome`, `~/.direnvrc`, `~/Brewfile`              |
| `sh/gnupg/gpg-agent.conf`                                  | `~/.gnupg/gpg-agent.conf`                                  |
| `sh/zsh/custom-zsh-theme/dpoggi-timestamp.zsh-theme`       | `~/.oh-my-zsh/custom/themes/dpoggi-timestamp.zsh-theme`    |
| `git/.gitconfig`, `git/.gitignore_global`, `git/.tigrc`    | `~/.gitconfig`, `~/.gitignore_global`, `~/.tigrc`          |
| `editor/.vimrc`, `editor/.vim`                             | `~/.vimrc`, `~/.vim`                                       |
| `editor/ghostty`                                           | `~/.config/ghostty/config`                                 |

The full list lives in [`lib/links.sh`](lib/links.sh) and is shared by
`install.sh` and `uninstall.sh`.

## Backups

Anything `install.sh` is about to replace is moved to:

```
~/.dotfiles-backup/<timestamp>/
```

with the original directory structure preserved. A `~/.dotfiles-backup/latest`
symlink always points at the most recent backup so `uninstall.sh` knows
where to restore from.

Custom backup root:

```sh
DOTFILES_BACKUP_DIR=/somewhere/else ./install.sh
```

## Uninstall

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

`uninstall.sh` only removes symlinks that point back into this repo, then
restores the originals from `~/.dotfiles-backup/latest`. Anything it did
not place is left untouched.

## Reference

- https://github.com/ohmyzsh/ohmyzsh/wiki/External-themes#dpoggi-newline-timestamp
- https://github.com/ohmyzsh/ohmyzsh/issues/7688#issuecomment-476947050
- https://gist.github.com/webframp/75c680930b6b2caba9a1be6ec23477c1
- https://github.com/simnalamburt/.dotfiles
- https://github.com/malkoG/dotfiles
