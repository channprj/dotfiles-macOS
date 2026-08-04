# shellcheck shell=bash

DOTFILES_LOCK_OWNED=0
DOTFILES_LOCK_DIR="$BACKUP_ROOT/lock"

dotfiles_init_colors() {
  c_reset=''
  c_bold=''
  c_dim=''
  c_red=''
  c_green=''
  c_yellow=''
  c_blue=''
  c_cyan=''
  c_magenta=''

  if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]]; then
    c_reset='\033[0m'
    c_bold='\033[1m'
    c_dim='\033[2m'
    c_red='\033[0;31m'
    c_green='\033[0;32m'
    c_yellow='\033[0;33m'
    c_blue='\033[0;34m'
    c_cyan='\033[0;36m'
    # shellcheck disable=SC2034 # consumed by install.sh and uninstall.sh
    c_magenta='\033[0;35m'
  fi
}

log() { printf '%b\n' "$*"; }
info() { log "${c_blue}[*]${c_reset} $*"; }
ok() { log "${c_green}[+]${c_reset} $*"; }
warn() { log "${c_yellow}[!]${c_reset} $*"; }
err() { log "${c_red}[x]${c_reset} $*" >&2; }
skip() { log "  ${c_dim}skip:${c_reset} $*"; }

dotfiles_plan_heading() {
  printf '\n%b%s%b\n' "${c_bold}${c_blue}" "$1" "$c_reset"
}

dotfiles_plan_item() {
  local color="$1"
  local action="$2"
  local destination="$3"

  printf '  %b%-13s%b %b%s%b\n' \
    "$color" "$action" "$c_reset" "${c_bold}${c_cyan}" "$destination" "$c_reset"
}

dotfiles_plan_detail() {
  local label="$1"
  local value="$2"
  local color="${3:-}"

  printf '    %b%-11s%b %b%s%b\n' \
    "$c_dim" "$label" "$c_reset" "$color" "$value" "$c_reset"
}

dotfiles_path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

dotfiles_validate_field() {
  local field_name="$1"
  local field_value="$2"

  if [[ -z "$field_value" || "$field_value" == *$'\t'* || "$field_value" == *$'\n'* ]]; then
    err "invalid $field_name in static link inventory"
    return 1
  fi
}

dotfiles_validate_relative_path() {
  local field_name="$1"
  local field_value="$2"

  dotfiles_validate_field "$field_name" "$field_value" || return 1
  case "/$field_value/" in
    *'/../'* | *'/./'*)
      err "$field_name must not contain '.' or '..': $field_value"
      return 1
      ;;
  esac
  if [[ "$field_value" == /* ]]; then
    err "$field_name must be relative: $field_value"
    return 1
  fi
}

dotfiles_validate_backup_root() {
  local probe="$BACKUP_ROOT"
  local parent=""

  if [[ -z "$BACKUP_ROOT" || "$BACKUP_ROOT" != /* || "$BACKUP_ROOT" == / || "$BACKUP_ROOT" == "$HOME" ]]; then
    err "unsafe backup root: ${BACKUP_ROOT:-<empty>}"
    return 1
  fi
  if [[ -L "$BACKUP_ROOT" ]]; then
    err "backup root must not be a symlink: $BACKUP_ROOT"
    return 1
  fi
  if dotfiles_path_exists "$BACKUP_ROOT" && [[ ! -d "$BACKUP_ROOT" ]]; then
    err "backup root is not a directory: $BACKUP_ROOT"
    return 1
  fi

  while ! dotfiles_path_exists "$probe"; do
    parent="$(dirname "$probe")"
    if [[ "$parent" == "$probe" ]]; then
      err "cannot resolve a writable parent for backup root: $BACKUP_ROOT"
      return 1
    fi
    probe="$parent"
  done

  if [[ ! -d "$probe" || ! -w "$probe" ]]; then
    err "backup root parent is not writable: $probe"
    return 1
  fi
}

dotfiles_check_backup_overlap() {
  local destination="$1"

  case "$BACKUP_ROOT/" in
    "$destination/"*)
      err "backup root is inside managed destination: $destination"
      return 1
      ;;
  esac
  case "$destination/" in
    "$BACKUP_ROOT/"*)
      err "managed destination is inside backup root: $destination"
      return 1
      ;;
  esac
}

dotfiles_validate_platform() {
  if [[ "$(uname -s)" != Darwin ]]; then
    err "this installer currently supports macOS only"
    return 1
  fi
}

dotfiles_secure_backup_root() {
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    mkdir -p "$BACKUP_ROOT" || {
      err "could not create backup root: $BACKUP_ROOT"
      return 1
    }
  fi
  chmod 0700 "$BACKUP_ROOT" || {
    err "could not secure backup root: $BACKUP_ROOT"
    return 1
  }
  if [[ ! -d "$BACKUP_ROOT/installations" ]]; then
    mkdir "$BACKUP_ROOT/installations" || return 1
  fi
  chmod 0700 "$BACKUP_ROOT/installations" || return 1
}

dotfiles_lock_status() {
  local lock_pid=""

  [[ -d "$DOTFILES_LOCK_DIR" ]] || return 0
  if [[ -f "$DOTFILES_LOCK_DIR/pid" ]]; then
    IFS= read -r lock_pid <"$DOTFILES_LOCK_DIR/pid" || lock_pid=""
  fi
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    err "dotfiles operation is busy (pid $lock_pid): $DOTFILES_LOCK_DIR"
  else
    err "stale dotfiles lock requires manual inspection: $DOTFILES_LOCK_DIR"
  fi
  return 1
}

dotfiles_acquire_lock() {
  local command_name="$1"

  dotfiles_secure_backup_root || return 1
  dotfiles_lock_status || return 1
  if ! mkdir "$DOTFILES_LOCK_DIR" 2>/dev/null; then
    err "could not acquire dotfiles lock: $DOTFILES_LOCK_DIR"
    return 1
  fi
  DOTFILES_LOCK_OWNED=1
  printf '%s\n' "$$" >"$DOTFILES_LOCK_DIR/pid" || return 1
  printf '%s\n' "$command_name" >"$DOTFILES_LOCK_DIR/command" || return 1
  chmod 0600 "$DOTFILES_LOCK_DIR/pid" "$DOTFILES_LOCK_DIR/command" || return 1
}

dotfiles_release_lock() {
  local lock_pid=""

  (( DOTFILES_LOCK_OWNED )) || return 0
  if [[ -f "$DOTFILES_LOCK_DIR/pid" ]]; then
    IFS= read -r lock_pid <"$DOTFILES_LOCK_DIR/pid" || lock_pid=""
  fi
  if [[ "$lock_pid" == "$$" ]]; then
    rm -f "$DOTFILES_LOCK_DIR/pid" "$DOTFILES_LOCK_DIR/command"
    rmdir "$DOTFILES_LOCK_DIR" 2>/dev/null || true
  fi
  DOTFILES_LOCK_OWNED=0
}

dotfiles_check_incomplete_receipts() {
  local receipt=""
  local result=""

  [[ -d "$BACKUP_ROOT/installations" ]] || return 0
  while IFS= read -r receipt; do
    [[ -n "$receipt" ]] || continue
    result="$(awk -F '\t' '$1 == "# result" { value = $2 } END { print value }' "$receipt")"
    case "$result" in
      complete | rolled_back)
        ;;
      *)
        err "incomplete transaction receipt requires inspection: $receipt"
        return 1
        ;;
    esac
  done < <(find "$BACKUP_ROOT/installations" -type f -path '*/runs/*.tsv' -print 2>/dev/null | LC_ALL=C sort)
}

dotfiles_resolve_active_installation() {
  local active_link="$BACKUP_ROOT/active"
  local active_target=""

  ACTIVE_INSTALL_DIR=""
  ACTIVE_INSTALL_ID=""

  if [[ ! -L "$active_link" ]]; then
    if dotfiles_path_exists "$active_link"; then
      err "active receipt pointer is not a symlink: $active_link"
      return 1
    fi
    return 0
  fi

  active_target="$(readlink "$active_link")" || return 1
  case "$active_target" in
    installations/*)
      ;;
    *)
      err "active receipt pointer has an unsafe target: $active_target"
      return 1
      ;;
  esac
  if [[ "$active_target" == *'/../'* || "$active_target" == *$'\t'* || "$active_target" == *$'\n'* ]]; then
    err "active receipt pointer has an unsafe target: $active_target"
    return 1
  fi

  ACTIVE_INSTALL_DIR="$BACKUP_ROOT/$active_target"
  ACTIVE_INSTALL_ID="${active_target#installations/}"
  if [[ -z "$ACTIVE_INSTALL_ID" || "$ACTIVE_INSTALL_ID" == */* || "$ACTIVE_INSTALL_ID" == . || "$ACTIVE_INSTALL_ID" == .. ]]; then
    err "active receipt pointer has an invalid installation id: $ACTIVE_INSTALL_ID"
    return 1
  fi
  if [[ ! -d "$ACTIVE_INSTALL_DIR" || ! -f "$ACTIVE_INSTALL_DIR/manifest.tsv" ]]; then
    err "active receipt is incomplete: $ACTIVE_INSTALL_DIR"
    return 1
  fi
}

dotfiles_new_id() {
  local prefix="$1"
  local parent="$2"
  local base=""
  local candidate=""
  local suffix=0

  base="${prefix}-$(date +%Y%m%d-%H%M%S)-$$"
  candidate="$base"

  while dotfiles_path_exists "$parent/$candidate"; do
    suffix=$((suffix + 1))
    candidate="$base-$suffix"
  done
  printf '%s' "$candidate"
}

dotfiles_write_manifest_header() {
  printf 'module\tsource\tdestination\toriginal_kind\tbackup_path\tinstalled_link_target\tstatus\n'
}

dotfiles_write_run_header() {
  printf 'module\tsource\tdestination\taction\toriginal_kind\tbackup_path\told_link_target\tnew_link_target\tstatus\n'
}

dotfiles_receipt_result() {
  local receipt="$1"
  local result="$2"

  printf '# result\t%s\n' "$result" >>"$receipt" || return 1
  chmod 0600 "$receipt" || return 1
}

dotfiles_warn_lazyvim_dependencies() {
  local dependency=""
  local missing=()

  for dependency in nvim git tree-sitter curl fzf rg fd cc; do
    command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
  done
  if (( ${#missing[@]} > 0 )); then
    warn "LazyVim optional/runtime dependencies missing: ${missing[*]}"
    warn "configuration links will still be installed"
  fi
}
