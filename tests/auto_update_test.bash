#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/dotfiles-auto-update.XXXXXX)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
LABEL="com.chann.dotfiles.auto-update"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

git_quiet() {
  git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@" >/dev/null
}

# A bare origin plus a clone whose install.sh only records that it ran.
new_repo() {
  local name="$1"

  CASE="$TEST_ROOT/$name"
  mkdir -p "$CASE/seed/utilities" "$CASE/seed/lib" "$CASE/home" "$CASE/bin"
  cp "$REPO_ROOT/utilities/auto-update.sh" "$CASE/seed/utilities/"
  : >"$CASE/seed/lib/links.sh"
  : >"$CASE/seed/lib/transaction.sh"
  cat >"$CASE/seed/install.sh" <<'STUB'
#!/bin/bash
printf 'install %s stdin=%s\n' "$*" "$(cat | wc -c | tr -d ' ')" >>"$INSTALL_LOG"
STUB
  chmod +x "$CASE/seed/install.sh"
  git_quiet -C "$CASE/seed" init -q -b main
  git_quiet -C "$CASE/seed" add -A
  git_quiet -C "$CASE/seed" commit -q -m seed
  git_quiet clone -q --bare "$CASE/seed" "$CASE/origin.git"
  git_quiet clone -q "$CASE/origin.git" "$CASE/home/dotfiles"
  cat >"$CASE/bin/launchctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$LAUNCHCTL_LOG"
[[ "$1" != print ]] || [[ -f "$LAUNCHCTL_LOG.loaded" ]]
[[ "$1" != bootstrap ]] || : >"$LAUNCHCTL_LOG.loaded"
[[ "$1" != bootout ]] || rm -f "$LAUNCHCTL_LOG.loaded"
STUB
  chmod +x "$CASE/bin/launchctl"
  export INSTALL_LOG="$CASE/install.log" LAUNCHCTL_LOG="$CASE/launchctl.log"
  : >"$INSTALL_LOG"
  : >"$LAUNCHCTL_LOG"
}

auto_update() {
  HOME="$CASE/home" PATH="$CASE/bin:$PATH" /bin/bash "$CASE/home/dotfiles/utilities/auto-update.sh" "$@"
}

push_change() {
  git_quiet -C "$CASE/seed" commit -q --allow-empty -m "$1"
  git_quiet -C "$CASE/seed" push -q "$CASE/origin.git" main
}

update_log() {
  cat "$CASE/home/Library/Logs/dotfiles/auto-update.log"
}

test_agent_install_is_idempotent_and_uninstall_removes_it() {
  new_repo agent
  local plist="$CASE/home/Library/LaunchAgents/$LABEL.plist"

  auto_update --dry-run | grep -q 'would write' || fail "dry-run did not describe the agent"
  [[ ! -e "$plist" ]] || fail "dry-run wrote the plist"
  auto_update >/dev/null
  [[ -f "$plist" ]] || fail "agent plist was not written"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$plist" >/dev/null || fail "agent plist is invalid"
  fi
  grep -q "<integer>9</integer>" "$plist" || fail "09:00 schedule missing"
  grep -q "<integer>21</integer>" "$plist" || fail "21:00 schedule missing"
  grep -q "$CASE/home/dotfiles/utilities/auto-update.sh" "$plist" || fail "plist does not run this checkout"
  [[ "$(grep -c '^bootstrap' "$LAUNCHCTL_LOG")" == 1 ]] || fail "agent was not bootstrapped once"
  auto_update | grep -q 'already loaded' || fail "second install was not a no-op"
  [[ "$(grep -c '^bootstrap' "$LAUNCHCTL_LOG")" == 1 ]] || fail "second install reloaded the agent"
  auto_update --uninstall >/dev/null
  [[ ! -e "$plist" ]] || fail "uninstall left the plist"
  grep -q "^bootout gui/$(id -u)/$LABEL" "$LAUNCHCTL_LOG" || fail "uninstall did not boot out the agent"
}

test_run_fast_forwards_and_installs() {
  new_repo run
  push_change second
  auto_update --run
  [[ "$(git -C "$CASE/home/dotfiles" log -1 --format=%s)" == second ]] || fail "run did not fast-forward"
  grep -q '^install  stdin=0$' "$INSTALL_LOG" || fail "run did not install non-interactively"
  update_log | grep -q 'done' || fail "run did not log completion"
}

test_run_skips_dirty_tree_and_other_branches() {
  new_repo skip
  push_change second
  printf 'local\n' >>"$CASE/home/dotfiles/install.sh"
  auto_update --run
  update_log | grep -q 'skip: working tree has local changes' || fail "dirty tree was not skipped"
  grep -q 'local' "$CASE/home/dotfiles/install.sh" || fail "local change was clobbered"
  git -C "$CASE/home/dotfiles" checkout -q -- install.sh
  git -C "$CASE/home/dotfiles" checkout -q -b topic
  auto_update --run
  update_log | grep -q "skip: HEAD is 'topic'" || fail "non-main branch was not skipped"
  [[ ! -s "$INSTALL_LOG" ]] || fail "skipped runs still installed"
  [[ "$(git -C "$CASE/home/dotfiles" log -1 --format=%s)" == seed ]] || fail "skipped run moved HEAD"
}

test_run_skips_when_another_run_holds_the_lock() {
  new_repo lock
  mkdir -p "$CASE/home/Library/Logs/dotfiles/auto-update.lock"
  printf '%s\n' "$$" >"$CASE/home/Library/Logs/dotfiles/auto-update.lock/pid"
  auto_update --run
  update_log | grep -q 'skip: another update is running' || fail "concurrent run was not skipped"
  [[ ! -s "$INSTALL_LOG" ]] || fail "locked run still installed"
}

test_piped_install_clones_then_runs_the_checkout() {
  new_repo bootstrap
  rm -rf "$CASE/home/dotfiles"
  HOME="$CASE/home" DOTFILES_REPO_URL="$CASE/origin.git" \
    /bin/bash -s -- --dry-run <"$REPO_ROOT/install.sh" >/dev/null
  [[ -f "$CASE/home/dotfiles/utilities/auto-update.sh" ]] || fail "bootstrap did not clone into ~/dotfiles"
  grep -q '^install --dry-run stdin=0$' "$INSTALL_LOG" || fail "bootstrap did not exec the checkout with its args"

  push_change second
  HOME="$CASE/home" DOTFILES_REPO_URL="$CASE/origin.git" \
    /bin/bash -s <"$REPO_ROOT/install.sh" >/dev/null
  [[ "$(git -C "$CASE/home/dotfiles" log -1 --format=%s)" == second ]] || fail "bootstrap did not update the existing checkout"
}

test_agent_install_is_idempotent_and_uninstall_removes_it
test_run_fast_forwards_and_installs
test_run_skips_dirty_tree_and_other_branches
test_run_skips_when_another_run_holds_the_lock
test_piped_install_clones_then_runs_the_checkout
printf '%s\n' 'PASS: auto-update tests'
