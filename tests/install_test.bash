#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/dotfiles-install-test.XXXXXX)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

new_case() {
  local name="$1"
  CASE_ROOT="$TEST_ROOT/$name"
  CASE_HOME="$CASE_ROOT/home"
  CASE_BACKUP="$CASE_ROOT/backup"
  mkdir -p "$CASE_HOME"
}

install_case() {
  HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" "$REPO_ROOT/install.sh" "$@"
}

uninstall_case() {
  HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" "$REPO_ROOT/uninstall.sh"
}

active_install_dir() {
  local target=""

  target="$(readlink "$CASE_BACKUP/active")"
  printf '%s/%s' "$CASE_BACKUP" "$target"
}

manifest_value() {
  local manifest="$1"
  local destination="$2"
  local column="$3"
  awk -F '\t' -v destination="$destination" -v column="$column" \
    'NR > 1 && $3 == destination { print $column; exit }' "$manifest"
}

test_dry_run_and_invalid_module_do_not_mutate() {
  local output=""

  new_case dry-run
  printf '%s\n' original >"$CASE_HOME/.zshrc"

  output="$(install_case --dry-run --all)"
  [[ "$output" == *"Install dry-run"* ]] || fail "dry-run heading is missing"
  [[ "$output" == *"$CASE_HOME/.zshrc"* ]] || fail "dry-run destination is missing"
  [[ "$output" == *"$REPO_ROOT/sh/.zshrc"* ]] || fail "dry-run source is missing"
  [[ "$output" == *"move current file, then create symlink"* ]] || fail "dry-run method is missing"
  [[ "$output" == *"$CASE_BACKUP/installations/<new-installation-id>/originals/.zshrc"* ]] ||
    fail "dry-run backup destination is missing"
  [[ "$output" == *"not required (destination is absent)"* ]] ||
    fail "dry-run should explain when a backup is unnecessary"
  [[ "$output" != *$'\033['* ]] || fail "non-terminal dry-run emitted color escapes"
  [[ ! -e "$CASE_BACKUP" ]] || fail "dry-run created the backup root"
  assert_eq original "$(<"$CASE_HOME/.zshrc")" "dry-run changed an existing file"

  if install_case --module unknown >/dev/null 2>&1; then
    fail "unknown module should fail"
  else
    assert_eq 2 "$?" "unknown module exit status"
  fi
  [[ ! -e "$CASE_BACKUP" ]] || fail "invalid module created the backup root"
}

test_dry_run_colors_only_for_terminals() {
  local output=""

  new_case dry-run-color
  output="$(
    TERM=xterm-256color NO_COLOR='' HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" \
      /usr/bin/script -q /dev/null "$REPO_ROOT/install.sh" --dry-run 2>/dev/null
  )"
  [[ "$output" == *$'\033[1m'* ]] || fail "terminal dry-run is missing bold highlighting"
  [[ "$output" == *$'\033[0;32m'* ]] || fail "terminal dry-run is missing action colors"

  output="$(
    TERM=xterm-256color NO_COLOR=1 HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" \
      /usr/bin/script -q /dev/null "$REPO_ROOT/install.sh" --dry-run 2>/dev/null
  )"
  [[ "$output" != *$'\033['* ]] || fail "NO_COLOR did not disable highlighting"
  [[ ! -e "$CASE_BACKUP" ]] || fail "colored dry-run created the backup root"
}

test_default_install_restores_every_original_kind() {
  local manifest=""
  local external_target="$TEST_ROOT/external-gitconfig"

  new_case restore-kinds
  mkdir -p "$CASE_HOME/.vim" "$CASE_BACKUP/legacy"
  printf '%s\n' original-zsh >"$CASE_HOME/.zshrc"
  printf '%s\n' original-vim >"$CASE_HOME/.vim/marker"
  printf '%s\n' external >"$external_target"
  ln -s "$external_target" "$CASE_HOME/.gitconfig"
  printf '%s\n' preserve >"$CASE_BACKUP/legacy/marker"
  ln -s legacy "$CASE_BACKUP/latest"

  install_case >/dev/null
  manifest="$(active_install_dir)/manifest.tsv"
  assert_eq file "$(manifest_value "$manifest" .zshrc 4)" "file kind was not recorded"
  assert_eq directory "$(manifest_value "$manifest" .vim 4)" "directory kind was not recorded"
  assert_eq symlink "$(manifest_value "$manifest" .gitconfig 4)" "symlink kind was not recorded"
  assert_eq absent "$(manifest_value "$manifest" .zshenv 4)" "absent kind was not recorded"
  assert_eq 700 "$(stat -f '%Lp' "$CASE_BACKUP")" "backup root permissions"
  assert_eq 700 "$(stat -f '%Lp' "$(active_install_dir)")" "installation permissions"
  assert_eq 600 "$(stat -f '%Lp' "$manifest")" "manifest permissions"
  [[ -L "$CASE_HOME/.config/nvim" ]] || fail "LazyVim was not linked by default"

  uninstall_case >/dev/null
  assert_eq original-zsh "$(<"$CASE_HOME/.zshrc")" "original file was not restored"
  assert_eq original-vim "$(<"$CASE_HOME/.vim/marker")" "original directory was not restored"
  [[ -L "$CASE_HOME/.gitconfig" ]] || fail "original symlink was not restored"
  assert_eq "$external_target" "$(readlink "$CASE_HOME/.gitconfig")" "original symlink target changed"
  [[ ! -e "$CASE_HOME/.zshenv" ]] || fail "originally absent target was left behind"
  [[ -f "$CASE_BACKUP/legacy/marker" ]] || fail "unrelated backup was removed"
  [[ -L "$CASE_BACKUP/latest" ]] || fail "legacy latest pointer was removed"
}

test_uninstall_dry_run_explains_restore_paths() {
  local install_dir=""
  local output=""

  new_case uninstall-dry-run
  printf '%s\n' original >"$CASE_HOME/.zshrc"
  install_case >/dev/null
  install_dir="$(active_install_dir)"

  output="$(HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" "$REPO_ROOT/uninstall.sh" --dry-run)"
  [[ "$output" == *"Uninstall dry-run"* ]] || fail "uninstall dry-run heading is missing"
  [[ "$output" == *"$CASE_HOME/.zshrc"* ]] || fail "uninstall dry-run destination is missing"
  [[ "$output" == *"$REPO_ROOT/sh/.zshrc"* ]] || fail "uninstall dry-run source is missing"
  [[ "$output" == *"remove managed symlink, then restore original"* ]] ||
    fail "uninstall dry-run restore method is missing"
  [[ "$output" == *"$install_dir/originals/.zshrc"* ]] ||
    fail "uninstall dry-run backup source is missing"
  [[ "$output" == *"destination will be absent"* ]] ||
    fail "uninstall dry-run removal result is missing"
  assert_eq original "$(<"$install_dir/originals/.zshrc")" "uninstall dry-run changed the backup"
  [[ -L "$CASE_HOME/.zshrc" ]] || fail "uninstall dry-run removed a managed link"

  uninstall_case >/dev/null
}

test_adopts_existing_repository_symlink() {
  local manifest=""

  new_case adopted
  ln -s "$REPO_ROOT/sh/.zshrc" "$CASE_HOME/.zshrc"
  install_case >/dev/null
  manifest="$(active_install_dir)/manifest.tsv"
  assert_eq adopted "$(manifest_value "$manifest" .zshrc 4)" "existing repository link was not adopted"
  assert_eq - "$(manifest_value "$manifest" .zshrc 5)" "adopted link should not have a backup"

  uninstall_case >/dev/null
  [[ ! -e "$CASE_HOME/.zshrc" ]] || fail "adopted link was not removed"
}

test_modules_accumulate_and_reinstall_is_idempotent() {
  local manifest=""
  local manifest_hash=""
  local original_count=""

  new_case modules
  install_case --module terminal --module terminal >/dev/null
  [[ -L "$CASE_HOME/.config/ghostty/config" ]] || fail "terminal module was not linked"
  manifest="$(active_install_dir)/manifest.tsv"
  manifest_hash="$(shasum -a 256 "$manifest" | awk '{print $1}')"
  original_count="$(find "$(active_install_dir)/originals" -mindepth 1 -print | wc -l | tr -d ' ')"

  install_case --module terminal >/dev/null
  assert_eq "$manifest_hash" "$(shasum -a 256 "$manifest" | awk '{print $1}')" "idempotent install rewrote manifest"
  assert_eq "$original_count" "$(find "$(active_install_dir)/originals" -mindepth 1 -print | wc -l | tr -d ' ')" "idempotent install changed backups"

  install_case --module gnupg --module brew >/dev/null
  [[ -L "$CASE_HOME/.gnupg/gpg-agent.conf" ]] || fail "gnupg module was not linked"
  [[ -L "$CASE_HOME/Brewfile" ]] || fail "brew module was not linked"
  assert_eq 700 "$(stat -f '%Lp' "$CASE_HOME/.gnupg")" ".gnupg permissions"
  assert_eq 17 "$(awk 'END { print NR - 1 }' "$manifest")" "module manifest row count"

  uninstall_case >/dev/null
  [[ ! -e "$CASE_HOME/.config/ghostty/config" ]] || fail "terminal module was not uninstalled"
  [[ ! -e "$CASE_HOME/.gnupg" ]] || fail "installer-created .gnupg parent was not removed"
  [[ ! -e "$CASE_HOME/Brewfile" ]] || fail "brew module was not uninstalled"
}

test_all_is_the_union_of_modules() {
  local manifest=""

  new_case all-modules
  install_case --all --module terminal >/dev/null
  manifest="$(active_install_dir)/manifest.tsv"
  assert_eq 17 "$(awk 'END { print NR - 1 }' "$manifest")" "--all did not install each mapping once"
  uninstall_case >/dev/null
}

test_repository_relocation_repairs_only_owned_links() {
  local moved_repo="$TEST_ROOT/moved-repo"
  local manifest=""
  local backup_hash=""

  new_case relocation
  printf '%s\n' original >"$CASE_HOME/.zshrc"
  install_case --module terminal >/dev/null
  manifest="$(active_install_dir)/manifest.tsv"
  backup_hash="$(shasum -a 256 "$(active_install_dir)/originals/.zshrc" | awk '{print $1}')"
  ln -s "$REPO_ROOT" "$moved_repo"

  HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" "$moved_repo/install.sh" --module terminal >/dev/null
  assert_eq "$moved_repo/sh/.zshrc" "$(readlink "$CASE_HOME/.zshrc")" "repository relocation did not repair default link"
  assert_eq "$moved_repo/editor/ghostty" "$(readlink "$CASE_HOME/.config/ghostty/config")" "repository relocation did not repair module link"
  assert_eq "$backup_hash" "$(shasum -a 256 "$(active_install_dir)/originals/.zshrc" | awk '{print $1}')" "relocation changed the original backup"
  assert_eq "$moved_repo" "$(<"$(active_install_dir)/repository-path")" "repository path receipt was not updated"

  HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" "$moved_repo/uninstall.sh" >/dev/null
  assert_eq original "$(<"$CASE_HOME/.zshrc")" "relocated uninstall did not restore original"
}

test_install_failure_rolls_back_the_whole_run() {
  local receipt=""

  new_case install-rollback
  printf '%s\n' one >"$CASE_HOME/.zshrc"
  printf '%s\n' two >"$CASE_HOME/.zshenv"
  if HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" DOTFILES_TEST_FAIL_AFTER=2 \
    "$REPO_ROOT/install.sh" >/dev/null 2>&1; then
    fail "injected install failure should fail"
  fi
  assert_eq one "$(<"$CASE_HOME/.zshrc")" "rollback did not restore .zshrc"
  assert_eq two "$(<"$CASE_HOME/.zshenv")" "rollback did not restore .zshenv"
  [[ ! -e "$CASE_BACKUP/active" ]] || fail "failed install activated a receipt"
  receipt="$(find "$CASE_BACKUP/installations" -type f -path '*/runs/*.tsv' -print -quit)"
  assert_eq rolled_back "$(awk -F '\t' '$1 == "# result" { print $2 }' "$receipt")" "rollback receipt result"
}

test_incomplete_rollback_preserves_recovery_data() {
  local receipt=""

  new_case recovery-required
  printf '%s\n' original >"$CASE_HOME/.zshrc"
  if HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" DOTFILES_TEST_FAIL_AFTER=1 DOTFILES_TEST_FAIL_ROLLBACK=1 \
    "$REPO_ROOT/install.sh" >/dev/null 2>&1; then
    fail "incomplete rollback should fail"
  fi
  receipt="$(find "$CASE_BACKUP/installations" -type f -path '*/runs/*.tsv' -print -quit)"
  assert_eq recovery-required "$(awk -F '\t' '$1 == "# result" { print $2 }' "$receipt")" "recovery-required receipt result"
  [[ -e "$receipt" ]] || fail "recovery receipt was removed"
  if install_case --dry-run >/dev/null 2>&1; then
    fail "new install should block on recovery-required receipt"
  fi
}

test_uninstall_conflict_is_zero_mutation() {
  local install_dir=""
  local backup_hash=""
  local other_target=""

  new_case uninstall-conflict
  printf '%s\n' original >"$CASE_HOME/.zshrc"
  install_case >/dev/null
  install_dir="$(active_install_dir)"
  backup_hash="$(shasum -a 256 "$install_dir/originals/.zshrc" | awk '{print $1}')"
  other_target="$(readlink "$CASE_HOME/.zshenv")"
  unlink "$CASE_HOME/.zshrc"
  printf '%s\n' user-change >"$CASE_HOME/.zshrc"

  if uninstall_case >/dev/null 2>&1; then
    fail "uninstall conflict should fail"
  fi
  assert_eq user-change "$(<"$CASE_HOME/.zshrc")" "conflict file was changed"
  assert_eq "$other_target" "$(readlink "$CASE_HOME/.zshenv")" "zero-mutation preflight changed another link"
  assert_eq "$backup_hash" "$(shasum -a 256 "$install_dir/originals/.zshrc" | awk '{print $1}')" "zero-mutation preflight changed backup"
  [[ -L "$CASE_BACKUP/active" ]] || fail "conflict removed active receipt"

  rm "$CASE_HOME/.zshrc"
  ln -s "$(manifest_value "$install_dir/manifest.tsv" .zshrc 6)" "$CASE_HOME/.zshrc"
  uninstall_case >/dev/null
}

test_uninstall_failure_restores_active_installation() {
  local receipt=""

  new_case uninstall-rollback
  printf '%s\n' original >"$CASE_HOME/.zshrc"
  install_case >/dev/null
  if HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_BACKUP" DOTFILES_TEST_UNINSTALL_FAIL_AFTER=2 \
    "$REPO_ROOT/uninstall.sh" >/dev/null 2>&1; then
    fail "injected uninstall failure should fail"
  fi
  [[ -L "$CASE_HOME/.zshrc" && -L "$CASE_HOME/.zshenv" ]] || fail "uninstall rollback did not restore links"
  [[ -L "$CASE_BACKUP/active" ]] || fail "uninstall rollback removed active receipt"
  receipt="$(find "$(active_install_dir)/runs" -type f -name 'uninstall-*.tsv' -print -quit)"
  assert_eq rolled_back "$(awk -F '\t' '$1 == "# result" { print $2 }' "$receipt")" "uninstall rollback receipt result"
  uninstall_case >/dev/null
  assert_eq original "$(<"$CASE_HOME/.zshrc")" "final uninstall did not restore original"
}

test_live_stale_locks_and_incomplete_receipts_block() {
  new_case lock-live
  mkdir -p "$CASE_BACKUP/lock"
  printf '%s\n' "$$" >"$CASE_BACKUP/lock/pid"
  if install_case --dry-run >/dev/null 2>&1; then
    fail "live lock should block install"
  fi

  rm -rf "$CASE_BACKUP/lock"
  mkdir "$CASE_BACKUP/lock"
  printf '%s\n' 99999999 >"$CASE_BACKUP/lock/pid"
  if install_case --dry-run >/dev/null 2>&1; then
    fail "stale lock should block install"
  fi
  [[ -d "$CASE_BACKUP/lock" ]] || fail "stale lock was deleted automatically"

  new_case incomplete-receipt
  mkdir -p "$CASE_BACKUP/installations/broken/runs"
  printf '%s\n' 'module\tsource\tdestination' >"$CASE_BACKUP/installations/broken/runs/run.tsv"
  if install_case --dry-run >/dev/null 2>&1; then
    fail "incomplete receipt should block install"
  fi
  [[ -f "$CASE_BACKUP/installations/broken/runs/run.tsv" ]] || fail "incomplete receipt was deleted"
}

test_unsafe_backup_roots_are_rejected() {
  new_case unsafe-root
  if HOME="$CASE_HOME" DOTFILES_BACKUP_DIR=relative "$REPO_ROOT/install.sh" --dry-run >/dev/null 2>&1; then
    fail "relative backup root should fail"
  fi
  if HOME="$CASE_HOME" DOTFILES_BACKUP_DIR="$CASE_HOME/.config/nvim/backup" \
    "$REPO_ROOT/install.sh" --dry-run >/dev/null 2>&1; then
    fail "backup root nested in a managed target should fail"
  fi
  [[ ! -e "$CASE_HOME/.config" ]] || fail "unsafe backup preflight mutated HOME"
}

test_uninstall_without_active_receipt_is_idempotent() {
  new_case no-active
  uninstall_case >/dev/null
  [[ ! -e "$CASE_BACKUP" ]] || fail "idempotent uninstall created backup root"
}

test_dry_run_and_invalid_module_do_not_mutate
test_dry_run_colors_only_for_terminals
test_default_install_restores_every_original_kind
test_uninstall_dry_run_explains_restore_paths
test_adopts_existing_repository_symlink
test_modules_accumulate_and_reinstall_is_idempotent
test_all_is_the_union_of_modules
test_repository_relocation_repairs_only_owned_links
test_install_failure_rolls_back_the_whole_run
test_incomplete_rollback_preserves_recovery_data
test_uninstall_conflict_is_zero_mutation
test_uninstall_failure_restores_active_installation
test_live_stale_locks_and_incomplete_receipts_block
test_unsafe_backup_roots_are_rejected
test_uninstall_without_active_receipt_is_idempotent

printf '%s\n' 'PASS: transactional install and uninstall preserve every managed state'
