#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO_ROOT/utilities/iterm-session-restore.sh"
TEST_ROOT=$(mktemp -d /tmp/dotfiles-iterm-restore.XXXXXX)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

setup_fakes() {
  local bin="$1"

  mkdir -p "$bin" "$TEST_ROOT/home/Library/LaunchAgents"
  cat >"$bin/defaults" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$DEFAULTS_LOG"
cmd="$1"
shift
case "$cmd" in
  write)
    domain="$1"
    key="$2"
    shift 2
    mkdir -p "$DEFAULTS_STATE"
    printf '%s' "$*" >"$DEFAULTS_STATE/${domain}__${key}"
    ;;
  read)
    domain="$1"
    key="$2"
    file="$DEFAULTS_STATE/${domain}__${key}"
    [[ -f "$file" ]] || exit 1
    if [[ "$(cat "$file")" == *true* ]]; then
      printf '1\n'
    else
      printf '0\n'
    fi
    ;;
  *)
    printf 'unexpected defaults command\n' >&2
    exit 1
    ;;
esac
EOF
  cat >"$bin/pgrep" <<'EOF'
#!/bin/bash
if [[ "${FAKE_ITERM_RUNNING:-0}" == 1 ]]; then
  exit 0
fi
exit 1
EOF
  cat >"$bin/launchctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$LAUNCHCTL_LOG"
exit 0
EOF
  chmod 755 "$bin/defaults" "$bin/pgrep" "$bin/launchctl"
}

run_script() {
  local bin="$1"
  shift
  HOME="$TEST_ROOT/home" \
    PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    FAKE_ITERM_RUNNING="${FAKE_ITERM_RUNNING:-0}" \
    DEFAULTS_LOG="$TEST_ROOT/defaults.log" \
    DEFAULTS_STATE="$TEST_ROOT/state" \
    LAUNCHCTL_LOG="$TEST_ROOT/launchctl.log" \
    "$SCRIPT" "$@"
}

assert_settings_written() {
  local log="$TEST_ROOT/defaults.log"
  local line=""

  for line in \
    "write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool true" \
    "write com.googlecode.iterm2 NSQuitAlwaysKeepsWindows -bool true" \
    "write com.googlecode.iterm2 NoSyncIgnoreSystemWindowRestoration -bool false" \
    "write com.googlecode.iterm2 RunJobsInServers -bool true" \
    "write com.googlecode.iterm2 KillJobsInServersOnQuit -bool false" \
    "write com.googlecode.iterm2 RestoreWindowContents -bool true"; do
    grep -F -x -q "$line" "$log" || fail "missing defaults write: $line"
  done
}

test_apply_writes_preferences_when_iterm_is_closed() {
  local bin="$TEST_ROOT/closed/bin"
  local output=""

  setup_fakes "$bin"
  : >"$TEST_ROOT/defaults.log"
  : >"$TEST_ROOT/launchctl.log"
  output="$(FAKE_ITERM_RUNNING=0 run_script "$bin")"
  [[ "$output" == *"iTerm session restore: applied"* ]] || fail "apply did not report success"
  [[ "$output" != *"after it quits"* ]] || fail "closed iTerm scheduled a second write"
  assert_settings_written
  [[ ! -s "$TEST_ROOT/launchctl.log" ]] || fail "closed iTerm called launchctl"
  [[ ! -e "$TEST_ROOT/home/Library/LaunchAgents/com.chann.dotfiles.iterm-session-restore.plist" ]] ||
    fail "closed iTerm created a LaunchAgent"
}

test_dry_run_does_not_write() {
  local bin="$TEST_ROOT/dry/bin"
  local output=""

  setup_fakes "$bin"
  rm -f -- "$TEST_ROOT/defaults.log" "$TEST_ROOT/launchctl.log"
  output="$(FAKE_ITERM_RUNNING=1 run_script "$bin" --dry-run)"
  [[ "$output" == *"NoSyncIgnoreSystemWindowRestoration = false"* ]] ||
    fail "dry-run did not show the restoration policy"
  [[ "$output" == *"KillJobsInServersOnQuit = false"* ]] ||
    fail "dry-run did not show the quit behavior"
  [[ "$output" == *"dry-run: no preferences were changed"* ]] || fail "dry-run confirmation is missing"
  [[ ! -e "$TEST_ROOT/defaults.log" ]] || fail "dry-run wrote preferences"
  [[ ! -e "$TEST_ROOT/home/Library/LaunchAgents/com.chann.dotfiles.iterm-session-restore.plist" ]] ||
    fail "dry-run created a LaunchAgent"
}

test_running_iterm_schedules_a_second_write() {
  local bin="$TEST_ROOT/running/bin"
  local output=""
  local plist="$TEST_ROOT/home/Library/LaunchAgents/com.chann.dotfiles.iterm-session-restore.plist"

  setup_fakes "$bin"
  : >"$TEST_ROOT/defaults.log"
  : >"$TEST_ROOT/launchctl.log"
  output="$(FAKE_ITERM_RUNNING=1 run_script "$bin")"
  [[ "$output" == *"written again after it quits"* ]] || fail "running iTerm did not explain the second write"
  assert_settings_written
  [[ -f "$plist" ]] || fail "running iTerm did not create a LaunchAgent"
  grep -F -q -- "--after-quit" "$plist" || fail "LaunchAgent does not rerun after quit"
  grep -F -q "bootstrap gui/$(id -u) $plist" "$TEST_ROOT/launchctl.log" ||
    fail "LaunchAgent was not bootstrapped"
}

test_after_quit_rewrites_and_removes_the_agent() {
  local bin="$TEST_ROOT/after/bin"
  local plist="$TEST_ROOT/home/Library/LaunchAgents/com.chann.dotfiles.iterm-session-restore.plist"

  setup_fakes "$bin"
  : >"$TEST_ROOT/defaults.log"
  : >"$TEST_ROOT/launchctl.log"
  mkdir -p "$(dirname "$plist")"
  printf '%s\n' placeholder >"$plist"
  FAKE_ITERM_RUNNING=0 run_script "$bin" --after-quit >/dev/null
  assert_settings_written
  [[ ! -e "$plist" ]] || fail "after-quit left the LaunchAgent plist"
  grep -F -q "bootout gui/$(id -u)/com.chann.dotfiles.iterm-session-restore" "$TEST_ROOT/launchctl.log" ||
    fail "after-quit did not bootout the LaunchAgent"
}

test_apply_writes_preferences_when_iterm_is_closed
test_dry_run_does_not_write
test_running_iterm_schedules_a_second_write
test_after_quit_rewrites_and_removes_the_agent
printf '%s\n' "PASS: iTerm session restore preferences"
