#!/usr/bin/env bash
#
# uninstall.sh - Remove the active dotfiles installation and restore originals.
#
# Usage:
#   ./uninstall.sh [-n|--dry-run]
#   ./uninstall.sh [-h|--help]

set -o pipefail
umask 077

DOTFILES_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
DRY_RUN=0
ACTIVE_INSTALL_DIR=""
ACTIVE_INSTALL_ID=""
RUN_ID=""
RUN_RECEIPT=""
MUTATION_COUNT=0

MANIFEST_MODULES=()
MANIFEST_SOURCES=()
MANIFEST_DESTINATIONS=()
MANIFEST_KINDS=()
MANIFEST_BACKUPS=()
MANIFEST_LINK_TARGETS=()
MANAGED_PARENTS=()
MUTATION_DESTINATIONS=()
MUTATION_BACKUPS=()
MUTATION_LINK_TARGETS=()
MUTATION_RESTORED=()

# shellcheck source=lib/transaction.sh
source "$DOTFILES_DIR/lib/transaction.sh"
dotfiles_init_colors

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cleanup() {
  dotfiles_release_lock
}
trap cleanup EXIT
trap 'exit 130' INT TERM

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -n | --dry-run)
        DRY_RUN=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        err "unknown argument: $1"
        return 2
        ;;
    esac
    shift
  done
}

load_manifest() {
  local module=""
  local source=""
  local destination=""
  local original_kind=""
  local backup_path=""
  local installed_target=""
  local status=""
  local seen=""

  while IFS=$'\t' read -r module source destination original_kind backup_path installed_target status; do
    [[ "$module" == module ]] && continue
    [[ -n "$module" ]] || continue
    dotfiles_validate_field module "$module" || return 1
    dotfiles_validate_relative_path source "$source" || return 1
    dotfiles_validate_relative_path destination "$destination" || return 1
    dotfiles_validate_field installed_link_target "$installed_target" || return 1
    [[ "$installed_target" == /* ]] || {
      err "installed link target must be absolute: $installed_target"
      return 1
    }
    case "$module" in
      default | terminal | gnupg | brew) ;;
      *) err "invalid module in active manifest: $module"; return 1 ;;
    esac
    case "$original_kind" in
      absent | file | directory | symlink | adopted) ;;
      *) err "invalid original kind in active manifest: $original_kind"; return 1 ;;
    esac
    [[ "$status" == linked ]] || {
      err "invalid active manifest status for ~/$destination: $status"
      return 1
    }
    if [[ "$backup_path" != - ]]; then
      dotfiles_validate_relative_path backup_path "$backup_path" || return 1
      [[ "$backup_path" == originals/* ]] || {
        err "unsafe backup path in active manifest: $backup_path"
        return 1
      }
    fi
    for seen in "${MANIFEST_DESTINATIONS[@]}"; do
      [[ "$seen" != "$destination" ]] || {
        err "duplicate destination in active manifest: ~/$destination"
        return 1
      }
    done
    MANIFEST_MODULES+=("$module")
    MANIFEST_SOURCES+=("$source")
    MANIFEST_DESTINATIONS+=("$destination")
    MANIFEST_KINDS+=("$original_kind")
    MANIFEST_BACKUPS+=("$backup_path")
    MANIFEST_LINK_TARGETS+=("$installed_target")
  done <"$ACTIVE_INSTALL_DIR/manifest.tsv"

  (( ${#MANIFEST_DESTINATIONS[@]} > 0 )) || {
    err "active manifest has no managed targets: $ACTIVE_INSTALL_DIR/manifest.tsv"
    return 1
  }

  if [[ -f "$ACTIVE_INSTALL_DIR/parents.tsv" ]]; then
    while IFS= read -r destination; do
      [[ -n "$destination" ]] || continue
      dotfiles_validate_relative_path parent "$destination" || return 1
      MANAGED_PARENTS+=("$destination")
    done <"$ACTIVE_INSTALL_DIR/parents.tsv"
  fi
}

validate_original_backup() {
  local index="$1"
  local kind="${MANIFEST_KINDS[$index]}"
  local backup_path="${MANIFEST_BACKUPS[$index]}"
  local backup_absolute=""

  case "$kind" in
    absent | adopted)
      [[ "$backup_path" == - ]] || {
        err "unexpected backup for ~/${MANIFEST_DESTINATIONS[$index]}"
        return 1
      }
      return 0
      ;;
  esac

  [[ "$backup_path" != - ]] || {
    err "missing backup receipt for ~/${MANIFEST_DESTINATIONS[$index]}"
    return 1
  }
  backup_absolute="$ACTIVE_INSTALL_DIR/$backup_path"
  if ! dotfiles_path_exists "$backup_absolute"; then
    err "original backup is missing: $backup_absolute"
    return 1
  fi
  case "$kind" in
    file) [[ -f "$backup_absolute" && ! -L "$backup_absolute" ]] ;;
    directory) [[ -d "$backup_absolute" && ! -L "$backup_absolute" ]] ;;
    symlink) [[ -L "$backup_absolute" ]] ;;
  esac || {
    err "original backup kind changed: $backup_absolute"
    return 1
  }
}

preflight_uninstall() {
  local index=0
  local destination_absolute=""
  local current_target=""

  while (( index < ${#MANIFEST_DESTINATIONS[@]} )); do
    destination_absolute="$HOME/${MANIFEST_DESTINATIONS[$index]}"
    dotfiles_check_backup_overlap "$destination_absolute" || return 1
    if [[ ! -L "$destination_absolute" ]]; then
      err "uninstall conflict: managed link was replaced or removed: ~/${MANIFEST_DESTINATIONS[$index]}"
      return 1
    fi
    current_target="$(readlink "$destination_absolute")" || return 1
    if [[ "$current_target" != "${MANIFEST_LINK_TARGETS[$index]}" ]]; then
      err "uninstall conflict: symlink target changed: ~/${MANIFEST_DESTINATIONS[$index]}"
      return 1
    fi
    validate_original_backup "$index" || return 1
    index=$((index + 1))
  done
}

print_plan() {
  local index=0

  while (( index < ${#MANIFEST_DESTINATIONS[@]} )); do
    if [[ "${MANIFEST_BACKUPS[$index]}" == - ]]; then
      info "remove managed link ~/${MANIFEST_DESTINATIONS[$index]}"
    else
      info "remove link and restore ~/${MANIFEST_DESTINATIONS[$index]}"
    fi
    index=$((index + 1))
  done
}

prepare_uninstall_receipt() {
  local index=0
  local action=""

  RUN_ID="$(dotfiles_new_id uninstall "$ACTIVE_INSTALL_DIR/runs")"
  RUN_RECEIPT="$ACTIVE_INSTALL_DIR/runs/$RUN_ID.tsv"
  dotfiles_write_run_header >"$RUN_RECEIPT" || return 1
  while (( index < ${#MANIFEST_DESTINATIONS[@]} )); do
    action=remove
    [[ "${MANIFEST_BACKUPS[$index]}" != - ]] && action=restore
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tplanned\n' \
      "${MANIFEST_MODULES[$index]}" "${MANIFEST_SOURCES[$index]}" \
      "${MANIFEST_DESTINATIONS[$index]}" "$action" "${MANIFEST_KINDS[$index]}" \
      "${MANIFEST_BACKUPS[$index]}" "${MANIFEST_LINK_TARGETS[$index]}" - >>"$RUN_RECEIPT"
    index=$((index + 1))
  done
  chmod 0600 "$RUN_RECEIPT" || return 1
}

maybe_inject_failure() {
  local fail_after="${DOTFILES_TEST_UNINSTALL_FAIL_AFTER:-}"

  MUTATION_COUNT=$((MUTATION_COUNT + 1))
  if [[ -n "$fail_after" && "$fail_after" =~ ^[0-9]+$ ]] && (( MUTATION_COUNT == fail_after )); then
    err "injected uninstall failure after mutation $MUTATION_COUNT"
    return 1
  fi
}

apply_uninstall() {
  local index=0
  local destination_absolute=""
  local backup_absolute="-"

  while (( index < ${#MANIFEST_DESTINATIONS[@]} )); do
    destination_absolute="$HOME/${MANIFEST_DESTINATIONS[$index]}"
    backup_absolute="-"
    if [[ "${MANIFEST_BACKUPS[$index]}" != - ]]; then
      backup_absolute="$ACTIVE_INSTALL_DIR/${MANIFEST_BACKUPS[$index]}"
    fi

    unlink "$destination_absolute" || return 1
    MUTATION_DESTINATIONS+=("$destination_absolute")
    MUTATION_BACKUPS+=("$backup_absolute")
    MUTATION_LINK_TARGETS+=("${MANIFEST_LINK_TARGETS[$index]}")
    MUTATION_RESTORED+=(0)

    if [[ "$backup_absolute" != - ]]; then
      mv "$backup_absolute" "$destination_absolute" || return 1
      MUTATION_RESTORED[$((${#MUTATION_RESTORED[@]} - 1))]=1
    fi
    maybe_inject_failure || return 1

    printf '%s\t%s\t%s\trestore\t%s\t%s\t%s\t-\tapplied\n' \
      "${MANIFEST_MODULES[$index]}" "${MANIFEST_SOURCES[$index]}" \
      "${MANIFEST_DESTINATIONS[$index]}" "${MANIFEST_KINDS[$index]}" \
      "${MANIFEST_BACKUPS[$index]}" "${MANIFEST_LINK_TARGETS[$index]}" >>"$RUN_RECEIPT"
    index=$((index + 1))
  done
}

rollback_uninstall() {
  local index=$((${#MUTATION_DESTINATIONS[@]} - 1))
  local destination=""
  local backup=""
  local link_target=""
  local current_target=""
  local rollback_failed=0

  warn "uninstall failed; restoring the active installation"
  while (( index >= 0 )); do
    destination="${MUTATION_DESTINATIONS[$index]}"
    backup="${MUTATION_BACKUPS[$index]}"
    link_target="${MUTATION_LINK_TARGETS[$index]}"

    if [[ "${DOTFILES_TEST_FAIL_ROLLBACK:-0}" == 1 ]]; then
      rollback_failed=1
      index=$((index - 1))
      continue
    fi

    if (( MUTATION_RESTORED[$index] )); then
      if dotfiles_path_exists "$backup"; then
        rollback_failed=1
      elif dotfiles_path_exists "$destination"; then
        mv "$destination" "$backup" || rollback_failed=1
      else
        rollback_failed=1
      fi
    elif dotfiles_path_exists "$destination"; then
      if [[ -L "$destination" ]]; then
        current_target="$(readlink "$destination")" || current_target=""
        [[ "$current_target" == "$link_target" ]] || rollback_failed=1
      else
        rollback_failed=1
      fi
    fi

    if ! dotfiles_path_exists "$destination"; then
      ln -s "$link_target" "$destination" || rollback_failed=1
    fi
    index=$((index - 1))
  done

  if (( rollback_failed )); then
    dotfiles_receipt_result "$RUN_RECEIPT" recovery-required
    err "uninstall rollback is incomplete; preserve and inspect: $RUN_RECEIPT"
    return 1
  fi

  dotfiles_receipt_result "$RUN_RECEIPT" rolled_back
  ok "uninstall rollback restored the active installation"
}

remove_created_parents() {
  local index=$((${#MANAGED_PARENTS[@]} - 1))
  local parent_absolute=""

  while (( index >= 0 )); do
    parent_absolute="$HOME/${MANAGED_PARENTS[$index]}"
    rmdir "$parent_absolute" 2>/dev/null || true
    index=$((index - 1))
  done
}

remove_consumed_installation() {
  local active_target=""

  case "$ACTIVE_INSTALL_DIR/" in
    "$BACKUP_ROOT/installations/"*) ;;
    *) err "refusing to remove unsafe installation path: $ACTIVE_INSTALL_DIR"; return 1 ;;
  esac
  [[ "$ACTIVE_INSTALL_DIR" != "$BACKUP_ROOT/installations" ]] || return 1

  active_target="$(readlink "$BACKUP_ROOT/active")" || return 1
  [[ "$active_target" == "installations/$ACTIVE_INSTALL_ID" ]] || {
    err "active receipt changed during uninstall"
    return 1
  }
  unlink "$BACKUP_ROOT/active" || return 1
  if ! find "$ACTIVE_INSTALL_DIR" -depth -delete; then
    err "originals were restored, but consumed receipt cleanup failed: $ACTIVE_INSTALL_DIR"
    return 1
  fi
}

main() {
  parse_args "$@" || {
    usage >&2
    return 2
  }
  dotfiles_validate_platform || return 1
  [[ -d "$HOME" && "$HOME" == /* ]] || {
    err "HOME must be an existing absolute directory: $HOME"
    return 1
  }
  dotfiles_validate_backup_root || return 1
  dotfiles_lock_status || return 1
  dotfiles_check_incomplete_receipts || return 1
  dotfiles_resolve_active_installation || return 1

  if [[ -z "$ACTIVE_INSTALL_DIR" ]]; then
    ok "no active dotfiles installation"
    return 0
  fi

  load_manifest || return 1
  preflight_uninstall || return 1
  info "active installation: $ACTIVE_INSTALL_ID"
  print_plan
  if (( DRY_RUN )); then
    warn "dry-run mode: no filesystem changes were made"
    return 0
  fi

  dotfiles_acquire_lock uninstall || return 1
  dotfiles_check_incomplete_receipts || return 1
  preflight_uninstall || return 1
  prepare_uninstall_receipt || return 1
  if ! apply_uninstall; then
    rollback_uninstall || true
    return 1
  fi

  if ! dotfiles_receipt_result "$RUN_RECEIPT" complete; then
    rollback_uninstall || true
    return 1
  fi
  remove_created_parents
  remove_consumed_installation || return 1
  ok "uninstall complete; originals restored"
}

main "$@"
