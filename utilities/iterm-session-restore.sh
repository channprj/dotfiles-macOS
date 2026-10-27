#!/usr/bin/env bash
#
# utilities/iterm-session-restore.sh
#
# Turn on iTerm2 session restoration and the macOS window restoration switch
# it depends on. This writes a few preference keys. It does not copy an
# iTerm plist.
#
# Usage:
#   utilities/iterm-session-restore.sh [--dry-run]
#   utilities/iterm-session-restore.sh --after-quit

set -euo pipefail

LABEL="com.chann.dotfiles.iterm-session-restore"
SCRIPT_PATH="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

# domain|key|bool. Advanced setting names are the iTerm selector with the
# first letter capitalized (RunJobsInServers, not runJobsInServers).
SETTINGS=(
  "NSGlobalDomain|NSQuitAlwaysKeepsWindows|true"
  "com.googlecode.iterm2|NSQuitAlwaysKeepsWindows|true"
  "com.googlecode.iterm2|NoSyncIgnoreSystemWindowRestoration|false"
  "com.googlecode.iterm2|RunJobsInServers|true"
  "com.googlecode.iterm2|KillJobsInServersOnQuit|false"
  "com.googlecode.iterm2|RestoreWindowContents|true"
)

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

bool_to_int() {
  if [[ "$1" == "true" ]]; then
    printf '1'
  else
    printf '0'
  fi
}

iterm_is_running() {
  pgrep -x iTerm2 >/dev/null 2>&1
}

agent_plist() {
  printf '%s' "$HOME/Library/LaunchAgents/${LABEL}.plist"
}

apply_settings() {
  local spec domain key value actual expected

  for spec in "${SETTINGS[@]}"; do
    IFS='|' read -r domain key value <<<"$spec"
    defaults write "$domain" "$key" -bool "$value"
    actual="$(defaults read "$domain" "$key")"
    expected="$(bool_to_int "$value")"
    if [[ "$actual" != "$expected" ]]; then
      printf 'iTerm session restore: %s %s is %s, expected %s\n' \
        "$domain" "$key" "$actual" "$expected" >&2
      return 1
    fi
  done
}

print_plan() {
  local spec domain key value

  printf '%s\n' "iTerm session restore:"
  for spec in "${SETTINGS[@]}"; do
    IFS='|' read -r domain key value <<<"$spec"
    printf '  %s %s = %s\n' "$domain" "$key" "$value"
  done
}

remove_agent() {
  local uid plist domain

  uid="$(id -u)"
  domain="gui/${uid}"
  plist="$(agent_plist)"
  rm -f -- "$plist"
  launchctl bootout "${domain}/${LABEL}" >/dev/null 2>&1 || true
}

schedule_after_quit() {
  local uid plist domain script_path

  uid="$(id -u)"
  domain="gui/${uid}"
  plist="$(agent_plist)"
  script_path="$(xml_escape "$SCRIPT_PATH")"
  mkdir -p -- "$HOME/Library/LaunchAgents"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${script_path}</string>
    <string>--after-quit</string>
  </array>
</dict>
</plist>
EOF
  chmod 644 "$plist"
  launchctl bootout "${domain}/${LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "$domain" "$plist"
}

MODE="apply"
for arg in "$@"; do
  case "$arg" in
    -n | --dry-run) MODE="dry-run" ;;
    --after-quit) MODE="after-quit" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" == "dry-run" ]]; then
  print_plan
  printf '%s\n' "dry-run: no preferences were changed"
  exit 0
fi

if [[ "$MODE" == "after-quit" ]]; then
  while iterm_is_running; do
    sleep 2
  done
  # Let iTerm finish writing its in-memory preferences before replacing them.
  sleep 2
  apply_settings
  remove_agent
  printf '%s\n' "iTerm session restore: applied after iTerm quit"
  exit 0
fi

apply_settings
printf '%s\n' "iTerm session restore: applied"
if iterm_is_running; then
  schedule_after_quit
  printf '%s\n' "iTerm is running. The open app can overwrite these preferences on quit, so they will be written again after it quits."
  printf '%s\n' "The first quit can still end jobs that are already running. Later quits keep them."
fi
