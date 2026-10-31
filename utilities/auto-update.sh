#!/usr/bin/env bash
#
# utilities/auto-update.sh
#
# Keep this checkout current twice a day (09:00 and 21:00 local time) with a
# launchd LaunchAgent. Each run fast-forwards main from origin and reruns
# install.sh. It skips the run and logs why when the tree is dirty, HEAD is
# not main, or main cannot fast-forward. install.sh loads the agent and
# uninstall.sh removes it.
#
# Usage:
#   utilities/auto-update.sh [--dry-run]   write and load the LaunchAgent
#   utilities/auto-update.sh --uninstall   unload and remove the LaunchAgent
#   utilities/auto-update.sh --run         update now (what launchd runs)
#
# Log: ~/Library/Logs/dotfiles/auto-update.log

set -euo pipefail

LABEL="com.chann.dotfiles.auto-update"
DOTFILES_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$DOTFILES_DIR/utilities/auto-update.sh"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/dotfiles"
LOG_FILE="$LOG_DIR/auto-update.log"
LOCK_DIR="$LOG_DIR/auto-update.lock"
BRANCH="main"
HOURS=(9 21)

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

render_plist() {
  local hour=""

  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_escape "$SCRIPT_PATH")</string>
    <string>--run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <array>
PLIST
  for hour in "${HOURS[@]}"; do
    printf '    <dict><key>Hour</key><integer>%s</integer><key>Minute</key><integer>0</integer></dict>\n' "$hour"
  done
  cat <<PLIST
  </array>
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$LOG_FILE")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$LOG_FILE")</string>
</dict>
</plist>
PLIST
}

schedule_text() {
  local hour="" text=""
  for hour in "${HOURS[@]}"; do
    text+="$(printf '%02d:00' "$hour") "
  done
  printf '%s' "${text% }"
}

domain() {
  printf 'gui/%s' "$(id -u)"
}

agent_loaded() {
  launchctl print "$(domain)/${LABEL}" >/dev/null 2>&1
}

install_agent() {
  local tmp=""

  if [[ "${1:-}" == dry-run ]]; then
    printf 'auto-update: would write %s (daily %s) and load %s\n' "$PLIST" "$(schedule_text)" "$LABEL"
    return 0
  fi
  mkdir -p -- "$HOME/Library/LaunchAgents" "$LOG_DIR"
  tmp="$(mktemp "$PLIST.XXXXXX")"
  render_plist >"$tmp"
  chmod 644 "$tmp"
  if [[ -f "$PLIST" ]] && cmp -s "$tmp" "$PLIST" && agent_loaded; then
    rm -f -- "$tmp"
    printf 'auto-update: %s already loaded\n' "$LABEL"
    return 0
  fi
  mv -f -- "$tmp" "$PLIST"
  if [[ "${DOTFILES_AUTO_UPDATE_RUN:-0}" == 1 ]] && agent_loaded; then
    # Booting out the running job would kill this update. launchd reads the
    # new plist at the next login or the next manual install.
    printf 'auto-update: %s changed; it reloads on the next login\n' "$PLIST"
    return 0
  fi
  launchctl bootout "$(domain)/${LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "$(domain)" "$PLIST"
  printf 'auto-update: loaded %s (daily %s, log %s)\n' "$LABEL" "$(schedule_text)" "$LOG_FILE"
}

uninstall_agent() {
  [[ -e "$PLIST" ]] || return 0
  launchctl bootout "$(domain)/${LABEL}" >/dev/null 2>&1 || true
  rm -f -- "$PLIST"
  printf 'auto-update: removed %s\n' "$LABEL"
}

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*"
}

release_lock() {
  rm -rf -- "$LOCK_DIR"
}

acquire_lock() {
  local pid=""

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    trap release_lock EXIT
    return 0
  fi
  pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    log "skip: another update is running (pid $pid)"
    return 1
  fi
  log "removing stale lock (pid ${pid:-unknown})"
  rm -rf -- "$LOCK_DIR"
  acquire_lock
}

run_update() {
  local branch="" before="" after="" login_path=""

  mkdir -p -- "$LOG_DIR"
  # Keep the log small: drop the oldest half once it passes 1 MiB.
  if [[ -f "$LOG_FILE" ]] && (( $(wc -c <"$LOG_FILE") > 1048576 )); then
    tail -c 524288 "$LOG_FILE" >"$LOG_FILE.tmp" && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
  fi
  if [[ -t 1 ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    exec >>"$LOG_FILE" 2>&1
  fi
  acquire_lock || return 0
  log "start: $DOTFILES_DIR"
  cd "$DOTFILES_DIR"
  export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false
  # launchd starts with a bare PATH. Use the login shell's PATH so install.sh
  # finds CLIs in ~/.local/bin and does not reinstall them (their installers
  # append PATH lines to the linked ~/.zprofile and ~/.zshrc).
  login_path="$(/bin/zsh -lc 'printf %s "$PATH"' </dev/null 2>/dev/null || true)"
  [[ -z "$login_path" ]] || export PATH="$login_path"

  branch="$(git symbolic-ref --quiet --short HEAD || true)"
  if [[ "$branch" != "$BRANCH" ]]; then
    log "skip: HEAD is '${branch:-detached}', not $BRANCH"
    return 0
  fi
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    log "skip: working tree has local changes"
    return 0
  fi
  if ! git fetch --quiet origin "$BRANCH" </dev/null; then
    log "fail: git fetch origin $BRANCH"
    return 1
  fi
  before="$(git rev-parse HEAD)"
  if ! git merge --ff-only --quiet "origin/$BRANCH" </dev/null; then
    log "skip: $BRANCH cannot fast-forward to origin/$BRANCH"
    return 0
  fi
  after="$(git rev-parse HEAD)"
  if [[ "$before" == "$after" ]]; then
    log "git: already up to date at ${after:0:7}"
  else
    log "git: ${before:0:7} -> ${after:0:7}"
  fi
  if ! DOTFILES_AUTO_UPDATE_RUN=1 NO_COLOR=1 "$DOTFILES_DIR/install.sh" </dev/null; then
    log "fail: install.sh exited $?"
    return 1
  fi
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    log "warn: install left local changes; later runs skip until they are resolved"
  fi
  log "done"
}

case "${1:-}" in
  "") install_agent ;;
  -n | --dry-run) install_agent dry-run ;;
  --uninstall) uninstall_agent ;;
  --run) run_update ;;
  -h | --help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
