#!/bin/bash
# Install the pf anchor for SSH, Screen Sharing, and Remote Management.
# See README.md in this directory. This script is not part of ./install.sh.

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LABEL=com.chann.tailscale-ssh-vnc
ANCHOR_LINE='anchor "com.chann.tailscale-ssh-vnc"'
HOOK_SHARING='anchor "com.apple.internet-sharing"'
HOOK_APPLE='anchor "com.apple/*"'
PF_CONF=/etc/pf.conf
ANCHOR_DST=/etc/pf.anchors/com.chann.tailscale-ssh-vnc
LOAD_DST='/Library/Application Support/tailscale-pf/load.sh'
PLIST_DST=/Library/LaunchDaemons/com.chann.tailscale-ssh-vnc.plist
BACKUP=/etc/pf.conf.before-set-tailscale-ssh-vnc

copy_backup_once() {
  local src=$1 dst=$2
  if [[ -e $dst ]]; then
    return 0
  fi
  cp -p "$src" "$dst"
}

usage() {
  cat <<'EOF'
Usage: scripts/tailscale-pf/set.sh [--yes]
       scripts/tailscale-pf/set.sh --self-test

Installs pf rules for TCP/UDP 22 (SSH), 5900 (Screen Sharing), and 3283
(Apple Remote Management). Allows lo0, Tailscale, and iptime Wi-Fi
(192.168.0.0/24). Hooks /etc/pf.conf and reloads pf. Asks for confirmation
unless --yes.
Does not change System Settings sharing toggles.
Does not cover Microsoft RDP (3389).
EOF
}

insert_before() {
  local src=$1 dst=$2 hook=$3
  awk -v hook="$hook" '
    $0 == hook && !done {
      print "# BEGIN com.chann.tailscale-ssh-vnc"
      print "anchor \"com.chann.tailscale-ssh-vnc\""
      print "load anchor \"com.chann.tailscale-ssh-vnc\" from \"/etc/pf.anchors/com.chann.tailscale-ssh-vnc\""
      print "# END com.chann.tailscale-ssh-vnc"
      done = 1
    }
    { print }
    END { if (!done) exit 2 }
  ' "$src" >"$dst"
}

insert_anchor() {
  local src=$1 dst=$2
  if grep -Fqx "$ANCHOR_LINE" "$src"; then
    cp "$src" "$dst"
    return 0
  fi
  if insert_before "$src" "$dst" "$HOOK_SHARING"; then
    return 0
  fi
  if insert_before "$src" "$dst" "$HOOK_APPLE"; then
    if [[ $src == "$PF_CONF" ]]; then
      printf '%s\n' "pf.conf has no $HOOK_SHARING; inserting before $HOOK_APPLE" >&2
    fi
    return 0
  fi
  rm -f "$dst"
  printf '%s\n' "error: $PF_CONF has neither line:" "  $HOOK_SHARING" "  $HOOK_APPLE" >&2
  return 1
}

self_test() {
  local stock live twice missing modern err got
  stock=$(mktemp)
  live=$(mktemp)
  twice=$(mktemp)
  missing=$(mktemp)
  modern=$(mktemp)
  err=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$stock' '$live' '$twice' '$missing' '$modern' '$err'" RETURN

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
  printf '%s\n' \
    'scrub-anchor "com.apple/*"' \
    'nat-anchor "com.apple/*"' \
    'rdr-anchor "com.apple/*"' \
    'dummynet-anchor "com.apple/*"' \
    >"$missing"
  printf '%s\n' \
    'dummynet-anchor "com.apple/*"' \
    'anchor "com.apple/*"' \
    'load anchor "com.apple" from "/etc/pf.anchors/com.apple"' \
    >"$modern"

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

  insert_anchor "$modern" "$stock"
  got=$(cat "$stock")
  [[ $got == 'dummynet-anchor "com.apple/*"
# BEGIN com.chann.tailscale-ssh-vnc
anchor "com.chann.tailscale-ssh-vnc"
load anchor "com.chann.tailscale-ssh-vnc" from "/etc/pf.anchors/com.chann.tailscale-ssh-vnc"
# END com.chann.tailscale-ssh-vnc
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"' ]]

  insert_anchor "$stock" "$twice"
  cmp -s "$stock" "$twice"

  if insert_anchor "$missing" "$twice" 2>"$err"; then
    printf '%s\n' 'self-test failed: missing hook should error' >&2
    return 1
  fi
  grep -F 'has neither line:' "$err" >/dev/null
  grep -F "$HOOK_SHARING" "$err" >/dev/null
  grep -F "$HOOK_APPLE" "$err" >/dev/null

  local backup_src backup_dst
  backup_src=$(mktemp)
  backup_dst=$(mktemp)
  printf 'new\n' >"$backup_src"
  printf 'old\n' >"$backup_dst"
  copy_backup_once "$backup_src" "$backup_dst"
  [[ $(cat "$backup_dst") == old ]]
  rm -f "$backup_dst"
  copy_backup_once "$backup_src" "$backup_dst"
  [[ $(cat "$backup_dst") == new ]]
  rm -f "$backup_src" "$backup_dst"

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
  'This allows TCP/UDP 22 (SSH), 5900 (Screen Sharing), and 3283 (Apple Remote Management)' \
  'only from lo0, Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48), and iptime Wi-Fi (192.168.0.0/24).' \
  'Microsoft RDP (3389) is unchanged.' \
  'It rewrites these files from this repo, then reloads pf:' \
  "  $ANCHOR_DST" \
  "  $LOAD_DST" \
  "  $PLIST_DST" \
  "  $PF_CONF" \
  'pfctl prints an -f warning twice and "No ALTQ support". Those lines are normal.' \
  'Apply this from the Mac itself or from an existing Tailscale SSH session.'

if [[ ${1:-} != --yes ]]; then
  printf '%s' "Type yes to apply: "
  read -r answer
  [[ $answer == yes ]] || {
    printf '%s\n' 'cancelled'
    exit 1
  }
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
insert_anchor "$PF_CONF" "$tmp"

install -d -o root -g wheel -m 755 '/Library/Application Support/tailscale-pf'
install -o root -g wheel -m 644 "$SCRIPT_DIR/pf.anchor" "$ANCHOR_DST"
install -o root -g wheel -m 755 "$SCRIPT_DIR/load.sh" "$LOAD_DST"
install -o root -g wheel -m 644 "$SCRIPT_DIR/com.chann.tailscale-ssh-vnc.plist" "$PLIST_DST"

if cmp -s "$PF_CONF" "$tmp"; then
  printf '%s\n' 'pf.conf already references the anchor'
  rm -f "$tmp"
  trap - EXIT
else
  copy_backup_once "$PF_CONF" "$BACKUP"
  chmod 644 "$tmp"
  chown root:wheel "$tmp"
  trap - EXIT
  mv "$tmp" "$PF_CONF"
  printf '%s\n' "updated $PF_CONF (backup: $BACKUP)"
fi

"$LOAD_DST"

launchctl enable "system/$LABEL" >/dev/null 2>&1 || true
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap system "$PLIST_DST"
launchctl enable "system/$LABEL"
