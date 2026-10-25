#!/bin/bash
# Install the Tailscale-only pf anchor for SSH, Screen Sharing, and Remote Management.
# See README.md in this directory. This script is not part of ./install.sh.

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LABEL=com.chann.tailscale-ssh-vnc
ANCHOR_LINE='anchor "com.chann.tailscale-ssh-vnc"'
HOOK_LINE='anchor "com.apple.internet-sharing"'
PF_CONF=/etc/pf.conf
ANCHOR_DST=/etc/pf.anchors/com.chann.tailscale-ssh-vnc
LOAD_DST='/Library/Application Support/tailscale-pf/load.sh'
PLIST_DST=/Library/LaunchDaemons/com.chann.tailscale-ssh-vnc.plist
BACKUP=/etc/pf.conf.before-set-tailscale-ssh-vnc

usage() {
  cat <<'EOF'
Usage: scripts/tailscale-pf/set.sh [--yes]
       scripts/tailscale-pf/set.sh --self-test

Installs the Tailscale-only pf rules for tcp/udp 22, 5900, and 3283,
hooks /etc/pf.conf, and reloads pf. Asks for confirmation unless --yes.
Does not change System Settings sharing toggles.
EOF
}

insert_anchor() {
  local src=$1 dst=$2
  if grep -Fqx "$ANCHOR_LINE" "$src"; then
    cp "$src" "$dst"
    return 0
  fi
  if ! awk -v hook="$HOOK_LINE" '
    $0 == hook && !done {
      print "# BEGIN com.chann.tailscale-ssh-vnc"
      print "anchor \"com.chann.tailscale-ssh-vnc\""
      print "load anchor \"com.chann.tailscale-ssh-vnc\" from \"/etc/pf.anchors/com.chann.tailscale-ssh-vnc\""
      print "# END com.chann.tailscale-ssh-vnc"
      done = 1
    }
    { print }
    END { if (!done) exit 2 }
  ' "$src" >"$dst"; then
    rm -f "$dst"
    printf '%s\n' "error: $PF_CONF has no line: $HOOK_LINE" >&2
    return 1
  fi
}

self_test() {
  local stock live twice missing got
  stock=$(mktemp)
  live=$(mktemp)
  twice=$(mktemp)
  missing=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$stock' '$live' '$twice' '$missing'" RETURN

  printf '%s\n' \
    'dummynet-anchor "com.apple/*"' \
    'anchor "com.apple.internet-sharing"' \
    '' \
    'anchor "com.apple/*"' \
    >"$stock"
  printf '%s\n' \
    '# Tailscale-only remote access. See /etc/pf.anchors/com.chann.tailscale-ssh-vnc' \
    'anchor "com.chann.tailscale-ssh-vnc"' \
    'load anchor "com.chann.tailscale-ssh-vnc" from "/etc/pf.anchors/com.chann.tailscale-ssh-vnc"' \
    'anchor "com.apple.internet-sharing"' \
    >"$live"
  printf '%s\n' 'anchor "com.apple/*"' >"$missing"

  insert_anchor "$stock" "$twice"
  got=$(cat "$twice")
  [[ $got == 'dummynet-anchor "com.apple/*"
# BEGIN com.chann.tailscale-ssh-vnc
anchor "com.chann.tailscale-ssh-vnc"
load anchor "com.chann.tailscale-ssh-vnc" from "/etc/pf.anchors/com.chann.tailscale-ssh-vnc"
# END com.chann.tailscale-ssh-vnc
anchor "com.apple.internet-sharing"

anchor "com.apple/*"' ]]

  insert_anchor "$twice" "$stock"
  cmp -s "$twice" "$stock"

  insert_anchor "$live" "$twice"
  cmp -s "$live" "$twice"

  if insert_anchor "$missing" "$twice" 2>/dev/null; then
    printf '%s\n' 'self-test failed: missing hook should error' >&2
    return 1
  fi
  printf '%s\n' 'set.sh self-test ok'
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
[[ -f $SCRIPT_DIR/pf.anchor && -f $SCRIPT_DIR/load.sh && -f $SCRIPT_DIR/com.chann.tailscale-ssh-vnc.plist ]]

printf '%s\n' \
  'This will allow tcp/udp 22, 5900, 3283 only from Tailscale and lo0.' \
  'It rewrites these files from this repo, then reloads pf:' \
  "  $ANCHOR_DST" \
  "  $LOAD_DST" \
  "  $PLIST_DST" \
  "  $PF_CONF" \
  'Apply this from the Mac itself or from an existing Tailscale SSH session.'

if [[ ${1:-} != --yes ]]; then
  printf '%s' "Type yes to apply: "
  read -r answer
  [[ $answer == yes ]] || {
    printf '%s\n' 'cancelled'
    exit 1
  }
fi

install -d -o root -g wheel -m 755 '/Library/Application Support/tailscale-pf'
install -o root -g wheel -m 644 "$SCRIPT_DIR/pf.anchor" "$ANCHOR_DST"
install -o root -g wheel -m 755 "$SCRIPT_DIR/load.sh" "$LOAD_DST"
install -o root -g wheel -m 644 "$SCRIPT_DIR/com.chann.tailscale-ssh-vnc.plist" "$PLIST_DST"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
insert_anchor "$PF_CONF" "$tmp"
if cmp -s "$PF_CONF" "$tmp"; then
  printf '%s\n' 'pf.conf already references the anchor'
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

/sbin/pfctl -E >/dev/null 2>&1 || true
/sbin/pfctl -nf "$PF_CONF"
/sbin/pfctl -f "$PF_CONF"

launchctl enable "system/$LABEL" >/dev/null 2>&1 || true
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap system "$PLIST_DST"
launchctl enable "system/$LABEL"

printf '%s\n' 'loaded anchor:'
/sbin/pfctl -a "$LABEL" -sr
