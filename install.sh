#!/usr/bin/env bash
#
# install.sh - Symlink dotfiles from this repo into $HOME.
#
# Each existing destination is moved to ~/.dotfiles-backup/<timestamp>/
# preserving its directory structure, then replaced by a symlink to the
# matching file/directory inside this repo. Re-running is safe: links that
# already point at the repo are left alone.
#
# Usage:
#   ./install.sh             install symlinks (with backups)
#   ./install.sh --dry-run   print what would happen without changing anything
#   ./install.sh --help      show this help text

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
LATEST_LINK="$BACKUP_ROOT/latest"

DRY_RUN=0

# Mapping lives in lib/links.sh so install.sh and uninstall.sh share one source of truth.
# shellcheck source=lib/links.sh
source "$DOTFILES_DIR/lib/links.sh"

c_reset='\033[0m'
c_dim='\033[2m'
c_red='\033[0;31m'
c_green='\033[0;32m'
c_yellow='\033[0;33m'
c_blue='\033[0;34m'

log()  { printf '%b\n' "$*"; }
info() { log "${c_blue}[*]${c_reset} $*"; }
ok()   { log "${c_green}[+]${c_reset} $*"; }
warn() { log "${c_yellow}[!]${c_reset} $*"; }
err()  { log "${c_red}[x]${c_reset} $*" >&2; }
skip() { log "  ${c_dim}skip:${c_reset} $*"; }

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

run() {
  if (( DRY_RUN )); then
    log "  ${c_dim}dry-run:${c_reset} $*"
  else
    "$@"
  fi
}

# Args
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    usage; exit 0 ;;
    *)            err "unknown argument: $arg"; usage; exit 2 ;;
  esac
done

if (( DRY_RUN )); then
  warn "dry-run mode: no filesystem changes will be made"
fi

info "dotfiles repo: $DOTFILES_DIR"
info "backup target: $BACKUP_DIR"

backup_path_for() {
  # Given a HOME-relative destination like ".config/ghostty/config",
  # return the full path inside the timestamped backup dir.
  printf '%s/%s' "$BACKUP_DIR" "$1"
}

ensure_parent() {
  local target="$1"
  local parent
  parent="$(dirname "$target")"
  [[ -d "$parent" ]] && return 0
  run mkdir -p "$parent"
}

backup_existing() {
  local dest_abs="$1" dest_rel="$2"
  local bk
  bk="$(backup_path_for "$dest_rel")"
  ensure_parent "$bk"
  # Use mv to preserve the original; avoids data duplication and
  # cleanly removes the original from $HOME in one step.
  run mv "$dest_abs" "$bk"
  ok "backed up ~/$dest_rel -> $bk"
}

link_one() {
  local rel_src="$1" rel_dst="$2"
  local src="$DOTFILES_DIR/$rel_src"
  local dst="$HOME/$rel_dst"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    warn "missing source in repo: $rel_src (skipping)"
    return 0
  fi

  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst")"
    if [[ "$current" == "$src" ]]; then
      skip "~/$rel_dst already linked"
      return 0
    fi
    # Existing symlink points elsewhere -> back it up so uninstall can restore.
    backup_existing "$dst" "$rel_dst"
  elif [[ -e "$dst" ]]; then
    backup_existing "$dst" "$rel_dst"
  fi

  ensure_parent "$dst"
  run ln -s "$src" "$dst"
  ok "linked ~/$rel_dst -> $src"
}

# Make sure the backup root exists (real run only; dry-run shouldn't touch FS).
if ! (( DRY_RUN )); then
  mkdir -p "$BACKUP_ROOT"
fi

for entry in "${LINKS[@]}"; do
  src="${entry%%:*}"
  dst="${entry#*:}"
  link_one "$src" "$dst"
done

# Update the "latest" pointer only if we created the backup dir (i.e. at
# least one file was moved). Otherwise leave the previous latest in place
# so uninstall can still find the truly-original state.
if (( DRY_RUN )); then
  info "dry-run finished"
elif [[ -d "$BACKUP_DIR" ]]; then
  ln -sfn "$BACKUP_DIR" "$LATEST_LINK"
  ok "backup pointer: $LATEST_LINK -> $BACKUP_DIR"
else
  info "no files needed backup (nothing changed)"
fi

ok "install complete"
