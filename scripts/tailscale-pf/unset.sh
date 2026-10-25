#!/bin/bash
# Remove the Tailscale-only pf anchor for SSH, Screen Sharing, and Remote Management.
# See README.md in this directory. Does not disable pf itself.

set -euo pipefail

LABEL=com.chann.tailscale-ssh-vnc
PF_CONF=/etc/pf.conf
ANCHOR_DST=/etc/pf.anchors/com.chann.tailscale-ssh-vnc
LOAD_DIR='/Library/Application Support/tailscale-pf'
PLIST_DST=/Library/LaunchDaemons/com.chann.tailscale-ssh-vnc.plist
BACKUP=/etc/pf.conf.before-unset-tailscale-ssh-vnc

usage() {
  cat <<'EOF'
Usage: scripts/tailscale-pf/unset.sh [--yes]
       scripts/tailscale-pf/unset.sh --self-test

Removes the Tailscale-only anchor from /etc/pf.conf and reloads pf.
SSH, Screen Sharing, and Remote Management then accept any source that
can already route to this Mac. Does not run pfctl -d.
EOF
}

strip_anchor() {
  local src=$1 dst=$2
  awk '
    $0 == "# BEGIN com.chann.tailscale-ssh-vnc" { skip = 1; next }
    $0 == "# END com.chann.tailscale-ssh-vnc" { skip = 0; next }
    skip { next }
    $0 == "# Tailscale-only remote access. See /etc/pf.anchors/com.chann.tailscale-ssh-vnc" { next }
    $0 == "anchor \"com.chann.tailscale-ssh-vnc\"" { next }
    $0 == "load anchor \"com.chann.tailscale-ssh-vnc\" from \"/etc/pf.anchors/com.chann.tailscale-ssh-vnc\"" { next }
    { print }
  ' "$src" >"$dst"
}

self_test() {
  local marked live stock got
  marked=$(mktemp)
  live=$(mktemp)
  stock=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$marked' '$live' '$stock'" RETURN

  printf '%s\n' \
    'dummynet-anchor "com.apple/*"' \
    '# BEGIN com.chann.tailscale-ssh-vnc' \
    'anchor "com.chann.tailscale-ssh-vnc"' \
    'load anchor "com.chann.tailscale-ssh-vnc" from "/etc/pf.anchors/com.chann.tailscale-ssh-vnc"' \
    '# END com.chann.tailscale-ssh-vnc' \
    'anchor "com.apple.internet-sharing"' \
    >"$marked"
  printf '%s\n' \
    'dummynet-anchor "com.apple/*"' \
    '# Tailscale-only remote access. See /etc/pf.anchors/com.chann.tailscale-ssh-vnc' \
    'anchor "com.chann.tailscale-ssh-vnc"' \
    'load anchor "com.chann.tailscale-ssh-vnc" from "/etc/pf.anchors/com.chann.tailscale-ssh-vnc"' \
    'anchor "com.apple.internet-sharing"' \
    >"$live"

  strip_anchor "$marked" "$stock"
  got=$(cat "$stock")
  [[ $got == 'dummynet-anchor "com.apple/*"
anchor "com.apple.internet-sharing"' ]]

  strip_anchor "$live" "$stock"
  got=$(cat "$stock")
  [[ $got == 'dummynet-anchor "com.apple/*"
anchor "com.apple.internet-sharing"' ]]

  strip_anchor "$stock" "$live"
  cmp -s "$stock" "$live"
  printf '%s\n' 'unset.sh self-test ok'
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  --self-test)
    self_test
    exit 0
    ;;
  --yes | '')
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ $(id -u) -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

[[ $(uname -s) == Darwin ]] || {
  printf '%s\n' 'error: macOS only' >&2
  exit 1
}

printf '%s\n' \
  'This removes the Tailscale-only pf filter for tcp/udp 22, 5900, and 3283.' \
  'After reload, those ports accept any source that can reach this Mac,' \
  'including the LAN and any router port forward.' \
  'pf stays enabled. System Settings sharing toggles stay as they are.'

if [[ ${1:-} != --yes ]]; then
  printf '%s' "Type yes to remove the filter: "
  read -r answer
  [[ $answer == yes ]] || {
    printf '%s\n' 'cancelled'
    exit 1
  }
fi

launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
launchctl disable "system/$LABEL" >/dev/null 2>&1 || true

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
strip_anchor "$PF_CONF" "$tmp"
if cmp -s "$PF_CONF" "$tmp"; then
  printf '%s\n' 'pf.conf has no Tailscale anchor hook'
  rm -f "$tmp"
  trap - EXIT
else
  cp -np "$PF_CONF" "$BACKUP"
  chmod 644 "$tmp"
  chown root:wheel "$tmp"
  trap - EXIT
  mv "$tmp" "$PF_CONF"
  printf '%s\n' "updated $PF_CONF (backup: $BACKUP)"
fi

/sbin/pfctl -nf "$PF_CONF"
/sbin/pfctl -f "$PF_CONF"

rm -f "$PLIST_DST" "$ANCHOR_DST" "$LOAD_DIR/load.sh"
rmdir "$LOAD_DIR" 2>/dev/null || true

printf '%s\n' 'filter removed. /var/log/tailscale-pf.log was left in place.'
