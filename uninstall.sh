#!/usr/bin/env bash
#
# uninstall.sh - Reverse what install.sh did.
#
# For each mapping, if the destination is a symlink pointing back into this
# repo it is removed. Then, if the most-recent backup directory
# (~/.dotfiles-backup/latest) holds the original file, it is moved back
# into place. Anything we did not create or back up is left alone.
#
# Usage:
#   ./uninstall.sh             remove symlinks and restore latest backup
#   ./uninstall.sh --dry-run   print what would happen without changing anything
#   ./uninstall.sh --help      show this help text

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
LATEST_LINK="$BACKUP_ROOT/latest"

DRY_RUN=0

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

# Resolve the backup directory we should restore from. The "latest" symlink
# is written by install.sh after each run; if it is missing we degrade
# gracefully and only remove our symlinks.
BACKUP_DIR=""
if [[ -L "$LATEST_LINK" ]]; then
  BACKUP_DIR="$(readlink "$LATEST_LINK")"
  # readlink may return a relative path on some platforms; normalize.
  if [[ "$BACKUP_DIR" != /* ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$BACKUP_DIR"
  fi
  info "restoring from: $BACKUP_DIR"
elif [[ -d "$BACKUP_ROOT" ]]; then
  warn "no $LATEST_LINK pointer; will not restore backups"
else
  warn "no backups found under $BACKUP_ROOT; will only remove symlinks"
fi

unlink_if_ours() {
  local rel_src="$1" rel_dst="$2"
  local src="$DOTFILES_DIR/$rel_src"
  local dst="$HOME/$rel_dst"

  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst")"
    if [[ "$current" == "$src" ]]; then
      run rm "$dst"
      ok "removed symlink ~/$rel_dst"
      return 0
    fi
    skip "~/$rel_dst is a symlink we did not create"
    return 1
  fi

  if [[ -e "$dst" ]]; then
    skip "~/$rel_dst is not a symlink we created"
    return 1
  fi

  skip "~/$rel_dst absent"
  return 0
}

restore_backup() {
  local rel_dst="$1"
  local dst="$HOME/$rel_dst"
  local src="$BACKUP_DIR/$rel_dst"

  [[ -z "$BACKUP_DIR" ]] && return 0
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    skip "no backup for ~/$rel_dst"
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    warn "~/$rel_dst still occupied; leaving backup at $src"
    return 0
  fi

  local parent
  parent="$(dirname "$dst")"
  if [[ ! -d "$parent" ]]; then
    run mkdir -p "$parent"
  fi

  run mv "$src" "$dst"
  ok "restored ~/$rel_dst from backup"
}

for entry in "${LINKS[@]}"; do
  src="${entry%%:*}"
  dst="${entry#*:}"
  if unlink_if_ours "$src" "$dst"; then
    restore_backup "$dst"
  fi
done

# Clean up the now-empty timestamped backup dir (if every file was restored).
if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] && ! (( DRY_RUN )); then
  if find "$BACKUP_DIR" -mindepth 1 -print -quit | grep -q .; then
    info "backup retained (some files remain): $BACKUP_DIR"
  else
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    # The "latest" symlink now dangles - remove it if it points at the gone dir.
    if [[ -L "$LATEST_LINK" ]] && [[ ! -e "$LATEST_LINK" ]]; then
      rm "$LATEST_LINK"
    fi
    ok "removed empty backup dir"
  fi
fi

ok "uninstall complete"
