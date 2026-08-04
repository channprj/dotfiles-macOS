#!/usr/bin/env bash
#
# install.sh - Transactionally link managed dotfiles into $HOME.
#
# Usage:
#   ./install.sh [-n|--dry-run] [--module <terminal|gnupg|brew>]... [--all]
#   ./install.sh [-h|--help]

set -o pipefail
umask 077

DOTFILES_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR_PHYSICAL="$(CDPATH='' cd -P -- "$DOTFILES_DIR" && pwd)"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
DRY_RUN=0
INSTALL_TERMINAL=0
INSTALL_GNUPG=0
INSTALL_BREW=0
ACTIVE_INSTALL_DIR=""
ACTIVE_INSTALL_ID=""
INSTALL_DIR=""
INSTALL_ID=""
RUN_ID=""
RUN_RECEIPT=""
MANIFEST_BACKUP=""
MUTATION_COUNT=0
PLAN_CHANGE_COUNT=0
ACTIVE_POINTER_CREATED=0

SELECTED_MODULES=()
SELECTED_SOURCES=()
SELECTED_DESTINATIONS=()
ACTIVE_MODULES=()
ACTIVE_SOURCES=()
ACTIVE_DESTINATIONS=()
ACTIVE_KINDS=()
ACTIVE_BACKUPS=()
ACTIVE_LINK_TARGETS=()
ACTIVE_STATUSES=()
PLAN_MODULES=()
PLAN_SOURCES=()
PLAN_DESTINATIONS=()
PLAN_ACTIONS=()
PLAN_KINDS=()
PLAN_BACKUPS=()
PLAN_OLD_TARGETS=()
PLAN_NEW_TARGETS=()
MUTATION_TYPES=()
MUTATION_DESTINATIONS=()
MUTATION_BACKUPS=()
MUTATION_OLD_TARGETS=()
MUTATION_NEW_TARGETS=()
RUN_CREATED_PARENTS=()
MANAGED_PARENTS=()

# shellcheck source=lib/links.sh
source "$DOTFILES_DIR/lib/links.sh"
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

selected_index_for() {
  local destination="$1"
  local index=0

  while (( index < ${#SELECTED_DESTINATIONS[@]} )); do
    if [[ "${SELECTED_DESTINATIONS[$index]}" == "$destination" ]]; then
      printf '%s' "$index"
      return 0
    fi
    index=$((index + 1))
  done
  printf '%s' '-1'
}

active_index_for() {
  local destination="$1"
  local index=0

  while (( index < ${#ACTIVE_DESTINATIONS[@]} )); do
    if [[ "${ACTIVE_DESTINATIONS[$index]}" == "$destination" ]]; then
      printf '%s' "$index"
      return 0
    fi
    index=$((index + 1))
  done
  printf '%s' '-1'
}

parent_is_managed() {
  local path="$1"
  local existing=""

  for existing in "${MANAGED_PARENTS[@]}" "${RUN_CREATED_PARENTS[@]}"; do
    [[ "$existing" == "$path" ]] && return 0
  done
  return 1
}

managed_parent_exists() {
  local path="$1"
  local existing=""

  for existing in "${MANAGED_PARENTS[@]}"; do
    [[ "$existing" == "$path" ]] && return 0
  done
  return 1
}

add_selected_group() {
  local module="$1"
  shift
  local entry=""
  local source=""
  local destination=""
  local existing_index=0

  for entry in "$@"; do
    source="${entry%%:*}"
    destination="${entry#*:}"
    existing_index="$(selected_index_for "$destination")"
    if (( existing_index >= 0 )); then
      if [[ "${SELECTED_SOURCES[$existing_index]}" != "$source" ]]; then
        err "duplicate destination has different sources: ~/$destination"
        return 1
      fi
      continue
    fi
    SELECTED_MODULES+=("$module")
    SELECTED_SOURCES+=("$source")
    SELECTED_DESTINATIONS+=("$destination")
  done
}

parse_args() {
  local module=""

  while (( $# > 0 )); do
    case "$1" in
      -n | --dry-run)
        DRY_RUN=1
        shift
        ;;
      --module)
        if (( $# < 2 )); then
          err "--module requires terminal, gnupg, or brew"
          return 2
        fi
        module="$2"
        case "$module" in
          terminal) INSTALL_TERMINAL=1 ;;
          gnupg) INSTALL_GNUPG=1 ;;
          brew) INSTALL_BREW=1 ;;
          *)
            err "unknown module: $module"
            return 2
            ;;
        esac
        shift 2
        ;;
      --all)
        INSTALL_TERMINAL=1
        INSTALL_GNUPG=1
        INSTALL_BREW=1
        shift
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
  done
}

load_active_manifest() {
  local module=""
  local source=""
  local destination=""
  local original_kind=""
  local backup_path=""
  local installed_target=""
  local status=""
  local duplicate_index=0

  [[ -n "$ACTIVE_INSTALL_DIR" ]] || return 0
  while IFS=$'\t' read -r module source destination original_kind backup_path installed_target status; do
    [[ "$module" == module ]] && continue
    [[ -n "$module" ]] || continue
    dotfiles_validate_field module "$module" || return 1
    dotfiles_validate_relative_path source "$source" || return 1
    dotfiles_validate_relative_path destination "$destination" || return 1
    dotfiles_validate_field original_kind "$original_kind" || return 1
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
        err "unsafe backup path in manifest: $backup_path"
        return 1
      }
    fi
    duplicate_index="$(active_index_for "$destination")"
    (( duplicate_index < 0 )) || {
      err "duplicate destination in active manifest: ~/$destination"
      return 1
    }
    ACTIVE_MODULES+=("$module")
    ACTIVE_SOURCES+=("$source")
    ACTIVE_DESTINATIONS+=("$destination")
    ACTIVE_KINDS+=("$original_kind")
    ACTIVE_BACKUPS+=("$backup_path")
    ACTIVE_LINK_TARGETS+=("$installed_target")
    ACTIVE_STATUSES+=("$status")
  done <"$ACTIVE_INSTALL_DIR/manifest.tsv"

  (( ${#ACTIVE_DESTINATIONS[@]} > 0 )) || {
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

merge_active_inventory() {
  local index=0
  local selected_index=0

  while (( index < ${#ACTIVE_DESTINATIONS[@]} )); do
    selected_index="$(selected_index_for "${ACTIVE_DESTINATIONS[$index]}")"
    if (( selected_index < 0 )); then
      SELECTED_MODULES+=("${ACTIVE_MODULES[$index]}")
      SELECTED_SOURCES+=("${ACTIVE_SOURCES[$index]}")
      SELECTED_DESTINATIONS+=("${ACTIVE_DESTINATIONS[$index]}")
    fi
    index=$((index + 1))
  done
}

validate_source() {
  local relative_source="$1"
  local source="$DOTFILES_DIR/$relative_source"
  local source_parent=""

  dotfiles_validate_relative_path source "$relative_source" || return 1
  if ! dotfiles_path_exists "$source"; then
    err "missing source in repository: $relative_source"
    return 1
  fi
  source_parent="$(CDPATH='' cd -P -- "$(dirname -- "$source")" && pwd)" || return 1
  case "$source_parent/" in
    "$DOTFILES_DIR_PHYSICAL/"*) ;;
    *)
      err "source escapes repository: $relative_source"
      return 1
      ;;
  esac
}

build_plan() {
  local index=0
  local active_index=0
  local module=""
  local source=""
  local destination=""
  local source_absolute=""
  local destination_absolute=""
  local current_target=""
  local action=""
  local original_kind=""
  local backup_path="-"
  local old_target="-"
  PLAN_CHANGE_COUNT=0

  while (( index < ${#SELECTED_DESTINATIONS[@]} )); do
    module="${SELECTED_MODULES[$index]}"
    source="${SELECTED_SOURCES[$index]}"
    destination="${SELECTED_DESTINATIONS[$index]}"
    source_absolute="$DOTFILES_DIR/$source"
    destination_absolute="$HOME/$destination"

    dotfiles_validate_field module "$module" || return 1
    dotfiles_validate_relative_path destination "$destination" || return 1
    validate_source "$source" || return 1
    dotfiles_check_backup_overlap "$destination_absolute" || return 1

    active_index="$(active_index_for "$destination")"
    action=""
    backup_path="-"
    old_target="-"

    if (( active_index >= 0 )); then
      original_kind="${ACTIVE_KINDS[$active_index]}"
      backup_path="${ACTIVE_BACKUPS[$active_index]}"
      old_target="${ACTIVE_LINK_TARGETS[$active_index]}"
      if [[ ! -L "$destination_absolute" ]]; then
        err "managed target was replaced; refusing to overwrite: ~/$destination"
        return 1
      fi
      current_target="$(readlink "$destination_absolute")" || return 1
      if [[ "$current_target" != "$old_target" ]]; then
        err "managed symlink changed outside the installer: ~/$destination"
        return 1
      fi
      if [[ "$old_target" == "$source_absolute" ]]; then
        action="unchanged"
      else
        action="relink"
        PLAN_CHANGE_COUNT=$((PLAN_CHANGE_COUNT + 1))
      fi
    elif [[ -L "$destination_absolute" ]]; then
      current_target="$(readlink "$destination_absolute")" || return 1
      if [[ "$current_target" == "$source_absolute" ]]; then
        action="adopt"
        original_kind="adopted"
        PLAN_CHANGE_COUNT=$((PLAN_CHANGE_COUNT + 1))
      else
        action="backup-link"
        original_kind="symlink"
        backup_path="originals/$destination"
        old_target="$current_target"
        PLAN_CHANGE_COUNT=$((PLAN_CHANGE_COUNT + 1))
      fi
    elif [[ -d "$destination_absolute" ]]; then
      action="backup-link"
      original_kind="directory"
      backup_path="originals/$destination"
      PLAN_CHANGE_COUNT=$((PLAN_CHANGE_COUNT + 1))
    elif [[ -e "$destination_absolute" ]]; then
      action="backup-link"
      original_kind="file"
      backup_path="originals/$destination"
      PLAN_CHANGE_COUNT=$((PLAN_CHANGE_COUNT + 1))
    else
      action="link"
      original_kind="absent"
      PLAN_CHANGE_COUNT=$((PLAN_CHANGE_COUNT + 1))
    fi

    PLAN_MODULES+=("$module")
    PLAN_SOURCES+=("$source")
    PLAN_DESTINATIONS+=("$destination")
    PLAN_ACTIONS+=("$action")
    PLAN_KINDS+=("$original_kind")
    PLAN_BACKUPS+=("$backup_path")
    PLAN_OLD_TARGETS+=("$old_target")
    PLAN_NEW_TARGETS+=("$source_absolute")
    index=$((index + 1))
  done

}

print_apply_plan() {
  local index=0
  local action=""

  while (( index < ${#PLAN_DESTINATIONS[@]} )); do
    action="${PLAN_ACTIONS[$index]}"
    case "$action" in
      unchanged) skip "$HOME/${PLAN_DESTINATIONS[$index]} already managed" ;;
      adopt) info "adopt ~/${PLAN_DESTINATIONS[$index]}" ;;
      relink) info "repair ~/${PLAN_DESTINATIONS[$index]} for repository relocation" ;;
      backup-link) info "backup and link ~/${PLAN_DESTINATIONS[$index]}" ;;
      link) info "link ~/${PLAN_DESTINATIONS[$index]}" ;;
    esac
    index=$((index + 1))
  done
}

planned_installation_dir() {
  if [[ -n "$ACTIVE_INSTALL_DIR" ]]; then
    printf '%s' "$ACTIVE_INSTALL_DIR"
  else
    printf '%s/installations/<new-installation-id>' "$BACKUP_ROOT"
  fi
}

print_dry_run_plan() {
  local index=0
  local action=""
  local destination=""
  local backup=""
  local installation_dir=""

  installation_dir="$(planned_installation_dir)"
  dotfiles_plan_heading "Install dry-run"
  dotfiles_plan_detail repository "$DOTFILES_DIR" "$c_magenta"
  dotfiles_plan_detail "backup root" "$BACKUP_ROOT" "$c_yellow"
  dotfiles_plan_detail receipt "$installation_dir/manifest.tsv"
  dotfiles_plan_detail changes "$PLAN_CHANGE_COUNT of ${#PLAN_DESTINATIONS[@]} managed targets"
  log ""

  while (( index < ${#PLAN_DESTINATIONS[@]} )); do
    action="${PLAN_ACTIONS[$index]}"
    destination="$HOME/${PLAN_DESTINATIONS[$index]}"
    backup="${PLAN_BACKUPS[$index]}"

    case "$action" in
      unchanged)
        dotfiles_plan_item "$c_dim" UNCHANGED "$destination"
        dotfiles_plan_detail module "${PLAN_MODULES[$index]}"
        dotfiles_plan_detail source "${PLAN_NEW_TARGETS[$index]}" "$c_magenta"
        dotfiles_plan_detail method "keep existing managed symlink"
        dotfiles_plan_detail current "${PLAN_KINDS[$index]}"
        if [[ "$backup" == - ]]; then
          dotfiles_plan_detail backup "not required (original: ${PLAN_KINDS[$index]})"
        else
          dotfiles_plan_detail backup "retained at $installation_dir/$backup" "$c_yellow"
        fi
        ;;
      adopt)
        dotfiles_plan_item "$c_cyan" ADOPT "$destination"
        dotfiles_plan_detail module "${PLAN_MODULES[$index]}"
        dotfiles_plan_detail source "${PLAN_NEW_TARGETS[$index]}" "$c_magenta"
        dotfiles_plan_detail method "record existing symlink without replacing it"
        dotfiles_plan_detail current "symlink already points to source"
        dotfiles_plan_detail backup "not required (existing repository symlink)"
        ;;
      relink)
        dotfiles_plan_item "$c_yellow" RELINK "$destination"
        dotfiles_plan_detail module "${PLAN_MODULES[$index]}"
        dotfiles_plan_detail source "${PLAN_NEW_TARGETS[$index]}" "$c_magenta"
        dotfiles_plan_detail method "replace owned symlink after repository relocation"
        dotfiles_plan_detail previous "${PLAN_OLD_TARGETS[$index]}"
        if [[ "$backup" == - ]]; then
          dotfiles_plan_detail backup "not required (original: ${PLAN_KINDS[$index]})"
        else
          dotfiles_plan_detail backup "retained at $installation_dir/$backup" "$c_yellow"
        fi
        ;;
      backup-link)
        dotfiles_plan_item "$c_yellow" "BACKUP + LINK" "$destination"
        dotfiles_plan_detail module "${PLAN_MODULES[$index]}"
        dotfiles_plan_detail source "${PLAN_NEW_TARGETS[$index]}" "$c_magenta"
        dotfiles_plan_detail method "move current ${PLAN_KINDS[$index]}, then create symlink"
        dotfiles_plan_detail current "${PLAN_KINDS[$index]}"
        dotfiles_plan_detail backup "$installation_dir/$backup" "$c_yellow"
        ;;
      link)
        dotfiles_plan_item "$c_green" LINK "$destination"
        dotfiles_plan_detail module "${PLAN_MODULES[$index]}"
        dotfiles_plan_detail source "${PLAN_NEW_TARGETS[$index]}" "$c_magenta"
        dotfiles_plan_detail method "create symlink (destination -> source)"
        dotfiles_plan_detail current absent
        dotfiles_plan_detail backup "not required (destination is absent)"
        ;;
    esac
    index=$((index + 1))
  done
}

record_created_parent() {
  local parent_relative="$1"

  if parent_is_managed "$parent_relative"; then
    return 0
  fi
  RUN_CREATED_PARENTS+=("$parent_relative")
  printf '# parent\t%s\n' "$parent_relative" >>"$RUN_RECEIPT"
}

ensure_home_parent() {
  local destination="$1"
  local parent=""
  local candidate=""
  local relative=""
  local missing=()
  local index=0

  parent="$(dirname -- "$destination")" || return 1
  candidate="$parent"
  case "$parent/" in
    "$HOME/"*) ;;
    *) err "destination parent escapes HOME: $parent"; return 1 ;;
  esac

  while [[ "$candidate" != "$HOME" && ! -d "$candidate" ]]; do
    if dotfiles_path_exists "$candidate"; then
      err "destination parent is not a directory: $candidate"
      return 1
    fi
    missing+=("$candidate")
    candidate="$(dirname -- "$candidate")"
  done

  index=$((${#missing[@]} - 1))
  while (( index >= 0 )); do
    candidate="${missing[$index]}"
    mkdir "$candidate" || return 1
    relative="${candidate#"$HOME/"}"
    if [[ "$relative" == .gnupg ]]; then
      chmod 0700 "$candidate" || return 1
    else
      chmod 0755 "$candidate" || return 1
    fi
    record_created_parent "$relative" || return 1
    index=$((index - 1))
  done
}

record_mutation() {
  MUTATION_TYPES+=("$1")
  MUTATION_DESTINATIONS+=("$2")
  MUTATION_BACKUPS+=("$3")
  MUTATION_OLD_TARGETS+=("$4")
  MUTATION_NEW_TARGETS+=("$5")
}

maybe_inject_failure() {
  local fail_after="${DOTFILES_TEST_FAIL_AFTER:-}"

  MUTATION_COUNT=$((MUTATION_COUNT + 1))
  if [[ -n "$fail_after" && "$fail_after" =~ ^[0-9]+$ ]] && (( MUTATION_COUNT == fail_after )); then
    err "injected install failure after mutation $MUTATION_COUNT"
    return 1
  fi
}

apply_plan() {
  local index=0
  local action=""
  local destination_absolute=""
  local backup_absolute=""
  local backup_parent=""

  while (( index < ${#PLAN_DESTINATIONS[@]} )); do
    action="${PLAN_ACTIONS[$index]}"
    destination_absolute="$HOME/${PLAN_DESTINATIONS[$index]}"
    backup_absolute="-"
    if [[ "${PLAN_BACKUPS[$index]}" != - ]]; then
      backup_absolute="$INSTALL_DIR/${PLAN_BACKUPS[$index]}"
    fi

    case "$action" in
      unchanged | adopt)
        ;;
      backup-link)
        backup_parent="$(dirname -- "$backup_absolute")"
        mkdir -p "$backup_parent" || return 1
        chmod 0700 "$INSTALL_DIR/originals" "$backup_parent" 2>/dev/null || true
        if dotfiles_path_exists "$backup_absolute"; then
          err "backup path already exists: $backup_absolute"
          return 1
        fi
        mv "$destination_absolute" "$backup_absolute" || return 1
        record_mutation backup "$destination_absolute" "$backup_absolute" "${PLAN_OLD_TARGETS[$index]}" "${PLAN_NEW_TARGETS[$index]}"
        ensure_home_parent "$destination_absolute" || return 1
        ln -s "${PLAN_NEW_TARGETS[$index]}" "$destination_absolute" || return 1
        maybe_inject_failure || return 1
        ;;
      link)
        ensure_home_parent "$destination_absolute" || return 1
        record_mutation link "$destination_absolute" - - "${PLAN_NEW_TARGETS[$index]}"
        ln -s "${PLAN_NEW_TARGETS[$index]}" "$destination_absolute" || return 1
        maybe_inject_failure || return 1
        ;;
      relink)
        unlink "$destination_absolute" || return 1
        record_mutation relink "$destination_absolute" - "${PLAN_OLD_TARGETS[$index]}" "${PLAN_NEW_TARGETS[$index]}"
        ln -s "${PLAN_NEW_TARGETS[$index]}" "$destination_absolute" || return 1
        maybe_inject_failure || return 1
        ;;
      *)
        err "unknown install action: $action"
        return 1
        ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tapplied\n' \
      "${PLAN_MODULES[$index]}" "${PLAN_SOURCES[$index]}" "${PLAN_DESTINATIONS[$index]}" \
      "$action" "${PLAN_KINDS[$index]}" "${PLAN_BACKUPS[$index]}" \
      "${PLAN_OLD_TARGETS[$index]}" "${PLAN_NEW_TARGETS[$index]}" >>"$RUN_RECEIPT"
    index=$((index + 1))
  done
}

rollback_install() {
  local index=$((${#MUTATION_TYPES[@]} - 1))
  local mutation_type=""
  local destination=""
  local backup=""
  local old_target=""
  local new_target=""
  local current_target=""
  local rollback_failed=0
  local parent_relative=""
  local parent_absolute=""

  warn "install failed; rolling back this run"
  while (( index >= 0 )); do
    mutation_type="${MUTATION_TYPES[$index]}"
    destination="${MUTATION_DESTINATIONS[$index]}"
    backup="${MUTATION_BACKUPS[$index]}"
    old_target="${MUTATION_OLD_TARGETS[$index]}"
    new_target="${MUTATION_NEW_TARGETS[$index]}"

    if [[ "${DOTFILES_TEST_FAIL_ROLLBACK:-0}" == 1 ]]; then
      rollback_failed=1
      index=$((index - 1))
      continue
    fi

    if [[ -L "$destination" ]]; then
      current_target="$(readlink "$destination")" || current_target=""
      if [[ "$current_target" == "$new_target" ]]; then
        unlink "$destination" || rollback_failed=1
      elif [[ "$mutation_type" != relink || "$current_target" != "$old_target" ]]; then
        rollback_failed=1
      fi
    elif dotfiles_path_exists "$destination"; then
      rollback_failed=1
    fi

    case "$mutation_type" in
      backup)
        if ! dotfiles_path_exists "$destination" && dotfiles_path_exists "$backup"; then
          mv "$backup" "$destination" || rollback_failed=1
        elif ! dotfiles_path_exists "$destination"; then
          rollback_failed=1
        fi
        ;;
      relink)
        if ! dotfiles_path_exists "$destination"; then
          ln -s "$old_target" "$destination" || rollback_failed=1
        fi
        ;;
      link)
        ;;
    esac
    index=$((index - 1))
  done

  index=$((${#RUN_CREATED_PARENTS[@]} - 1))
  while (( index >= 0 )); do
    parent_relative="${RUN_CREATED_PARENTS[$index]}"
    parent_absolute="$HOME/$parent_relative"
    rmdir "$parent_absolute" 2>/dev/null || true
    index=$((index - 1))
  done

  if [[ -n "$MANIFEST_BACKUP" && -f "$MANIFEST_BACKUP" ]]; then
    mv "$MANIFEST_BACKUP" "$INSTALL_DIR/manifest.tsv" || rollback_failed=1
  fi
  if (( ACTIVE_POINTER_CREATED )) && [[ -L "$BACKUP_ROOT/active" ]]; then
    if [[ "$(readlink "$BACKUP_ROOT/active")" == "installations/$INSTALL_ID" ]]; then
      unlink "$BACKUP_ROOT/active" || rollback_failed=1
    else
      rollback_failed=1
    fi
  fi

  if (( rollback_failed )); then
    dotfiles_receipt_result "$RUN_RECEIPT" recovery-required
    err "rollback is incomplete; preserve and inspect: $RUN_RECEIPT"
    return 1
  fi

  dotfiles_receipt_result "$RUN_RECEIPT" rolled_back
  ok "install rollback restored the previous state"
  return 0
}

update_active_arrays() {
  local index=0
  local active_index=0

  while (( index < ${#PLAN_DESTINATIONS[@]} )); do
    active_index="$(active_index_for "${PLAN_DESTINATIONS[$index]}")"
    if (( active_index >= 0 )); then
      ACTIVE_MODULES[$active_index]="${PLAN_MODULES[$index]}"
      ACTIVE_SOURCES[$active_index]="${PLAN_SOURCES[$index]}"
      ACTIVE_LINK_TARGETS[$active_index]="${PLAN_NEW_TARGETS[$index]}"
      ACTIVE_STATUSES[$active_index]=linked
    else
      ACTIVE_MODULES+=("${PLAN_MODULES[$index]}")
      ACTIVE_SOURCES+=("${PLAN_SOURCES[$index]}")
      ACTIVE_DESTINATIONS+=("${PLAN_DESTINATIONS[$index]}")
      ACTIVE_KINDS+=("${PLAN_KINDS[$index]}")
      ACTIVE_BACKUPS+=("${PLAN_BACKUPS[$index]}")
      ACTIVE_LINK_TARGETS+=("${PLAN_NEW_TARGETS[$index]}")
      ACTIVE_STATUSES+=(linked)
    fi
    index=$((index + 1))
  done

  for index in "${!RUN_CREATED_PARENTS[@]}"; do
    if ! managed_parent_exists "${RUN_CREATED_PARENTS[$index]}"; then
      MANAGED_PARENTS+=("${RUN_CREATED_PARENTS[$index]}")
    fi
  done
}

commit_active_receipt() {
  local manifest_tmp="$INSTALL_DIR/manifest.tsv.tmp-$$"
  local repository_tmp="$INSTALL_DIR/repository-path.tmp-$$"
  local parents_tmp="$INSTALL_DIR/parents.tsv.tmp-$$"
  local active_tmp="$BACKUP_ROOT/active.tmp-$$"
  local index=0

  update_active_arrays
  dotfiles_write_manifest_header >"$manifest_tmp" || return 1
  while (( index < ${#ACTIVE_DESTINATIONS[@]} )); do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${ACTIVE_MODULES[$index]}" "${ACTIVE_SOURCES[$index]}" "${ACTIVE_DESTINATIONS[$index]}" \
      "${ACTIVE_KINDS[$index]}" "${ACTIVE_BACKUPS[$index]}" \
      "${ACTIVE_LINK_TARGETS[$index]}" "${ACTIVE_STATUSES[$index]}" >>"$manifest_tmp"
    index=$((index + 1))
  done
  printf '%s\n' "$DOTFILES_DIR" >"$repository_tmp" || return 1
  : >"$parents_tmp" || return 1
  for index in "${!MANAGED_PARENTS[@]}"; do
    printf '%s\n' "${MANAGED_PARENTS[$index]}" >>"$parents_tmp"
  done
  chmod 0600 "$manifest_tmp" "$repository_tmp" "$parents_tmp" || return 1

  if [[ -f "$INSTALL_DIR/manifest.tsv" ]]; then
    MANIFEST_BACKUP="$INSTALL_DIR/manifest.tsv.before-$RUN_ID"
    cp "$INSTALL_DIR/manifest.tsv" "$MANIFEST_BACKUP" || return 1
    chmod 0600 "$MANIFEST_BACKUP" || return 1
  fi

  mv "$repository_tmp" "$INSTALL_DIR/repository-path" || return 1
  mv "$parents_tmp" "$INSTALL_DIR/parents.tsv" || return 1
  mv "$manifest_tmp" "$INSTALL_DIR/manifest.tsv" || return 1

  if [[ -z "$ACTIVE_INSTALL_ID" ]]; then
    ln -s "installations/$INSTALL_ID" "$active_tmp" || return 1
    mv -f "$active_tmp" "$BACKUP_ROOT/active" || return 1
    ACTIVE_POINTER_CREATED=1
  fi

  dotfiles_receipt_result "$RUN_RECEIPT" complete || return 1
  if [[ -n "$MANIFEST_BACKUP" ]]; then
    rm -f "$MANIFEST_BACKUP"
    MANIFEST_BACKUP=""
  fi
}

prepare_transaction() {
  local index=0

  if [[ -n "$ACTIVE_INSTALL_DIR" ]]; then
    INSTALL_DIR="$ACTIVE_INSTALL_DIR"
    INSTALL_ID="$ACTIVE_INSTALL_ID"
  else
    INSTALL_ID="$(dotfiles_new_id install "$BACKUP_ROOT/installations")"
    INSTALL_DIR="$BACKUP_ROOT/installations/$INSTALL_ID"
    mkdir "$INSTALL_DIR" || return 1
    chmod 0700 "$INSTALL_DIR" || return 1
    mkdir "$INSTALL_DIR/originals" "$INSTALL_DIR/runs" || return 1
    chmod 0700 "$INSTALL_DIR/originals" "$INSTALL_DIR/runs" || return 1
  fi

  [[ -d "$INSTALL_DIR/runs" ]] || mkdir "$INSTALL_DIR/runs" || return 1
  chmod 0700 "$INSTALL_DIR" "$INSTALL_DIR/runs" || return 1
  RUN_ID="$(dotfiles_new_id run "$INSTALL_DIR/runs")"
  RUN_RECEIPT="$INSTALL_DIR/runs/$RUN_ID.tsv"
  dotfiles_write_run_header >"$RUN_RECEIPT" || return 1
  while (( index < ${#PLAN_DESTINATIONS[@]} )); do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tplanned\n' \
      "${PLAN_MODULES[$index]}" "${PLAN_SOURCES[$index]}" "${PLAN_DESTINATIONS[$index]}" \
      "${PLAN_ACTIONS[$index]}" "${PLAN_KINDS[$index]}" "${PLAN_BACKUPS[$index]}" \
      "${PLAN_OLD_TARGETS[$index]}" "${PLAN_NEW_TARGETS[$index]}" >>"$RUN_RECEIPT"
    index=$((index + 1))
  done
  chmod 0600 "$RUN_RECEIPT" || return 1
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
  load_active_manifest || return 1

  add_selected_group default "${LINKS_DEFAULT[@]}" || return 1
  if (( INSTALL_TERMINAL )); then
    add_selected_group terminal "${LINKS_TERMINAL[@]}" || return 1
  fi
  if (( INSTALL_GNUPG )); then
    add_selected_group gnupg "${LINKS_GNUPG[@]}" || return 1
  fi
  if (( INSTALL_BREW )); then
    add_selected_group brew "${LINKS_BREW[@]}" || return 1
  fi
  merge_active_inventory || return 1

  build_plan || return 1
  if (( DRY_RUN )); then
    print_dry_run_plan
  else
    info "dotfiles repo: $DOTFILES_DIR"
    info "backup root: $BACKUP_ROOT"
    print_apply_plan
  fi
  dotfiles_warn_lazyvim_dependencies

  if (( DRY_RUN )); then
    warn "dry-run mode: no filesystem changes were made"
    return 0
  fi
  if (( PLAN_CHANGE_COUNT == 0 )); then
    ok "install already matches the active receipt"
    return 0
  fi

  dotfiles_acquire_lock install || return 1
  dotfiles_check_incomplete_receipts || return 1
  if ! prepare_transaction; then
    if [[ -n "$RUN_RECEIPT" && -f "$RUN_RECEIPT" ]]; then
      dotfiles_receipt_result "$RUN_RECEIPT" recovery-required
      err "transaction setup is incomplete; inspect: $RUN_RECEIPT"
    fi
    return 1
  fi
  if ! apply_plan; then
    rollback_install || true
    return 1
  fi
  if ! commit_active_receipt; then
    err "could not commit active receipt"
    rollback_install || true
    return 1
  fi

  ok "install complete: $INSTALL_ID"
}

main "$@"
