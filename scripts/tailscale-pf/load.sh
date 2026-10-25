#!/bin/sh
# Reload the installed pf.conf and say what the Tailscale anchor actually allows.
# This does not copy pf.anchor. Update installed files with set.sh.
set -eu

ANCHOR=com.chann.tailscale-ssh-vnc

line_matches() {
  found=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    piece_ok=1
    for part in "$@"; do
      case $line in
        *"$part"*) ;;
        *) piece_ok=0; break ;;
      esac
    done
    if [ "$piece_ok" = 1 ]; then
      found=1
      break
    fi
  done <<EOF
$rules
EOF
  [ "$found" = 1 ]
}

summarize() {
  rules=$1
  ok=1
  count=0

  if [ -z "$rules" ]; then
    printf '%s\n' 'tailscale-pf: anchor has no rules' >&2
    return 1
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    count=$((count + 1))
    case $line in
      *3389*)
        printf '%s\n' 'tailscale-pf: Microsoft RDP port 3389 is outside this anchor' >&2
        ok=0
        ;;
      *"port = 22 "*|*"port = 22"|*"port = 5900 "*|*"port = 5900"|*"port = 3283 "*|*"port = 3283") ;;
      *)
        printf '%s\n' "tailscale-pf: unexpected rule: $line" >&2
        ok=0
        ;;
    esac
  done <<EOF
$rules
EOF

  if [ "$count" -ne 24 ]; then
    printf '%s\n' "tailscale-pf: expected 24 expanded rules, found $count" >&2
    ok=0
  fi

  for port in 22 5900 3283; do
    line_matches "pass in quick on lo0 proto tcp" "port = $port " "flags S/SA" || {
      printf '%s\n' "tailscale-pf: missing lo0 TCP pass for $port" >&2
      ok=0
    }
    line_matches "pass in quick on lo0 proto udp" "port = $port " || {
      printf '%s\n' "tailscale-pf: missing lo0 UDP pass for $port" >&2
      ok=0
    }
    line_matches "pass in quick inet proto tcp from <chann_tailscale4>" "port = $port " "flags any" || {
      printf '%s\n' "tailscale-pf: missing Tailscale IPv4 TCP pass for $port" >&2
      ok=0
    }
    line_matches "pass in quick inet proto udp from <chann_tailscale4>" "port = $port " || {
      printf '%s\n' "tailscale-pf: missing Tailscale IPv4 UDP pass for $port" >&2
      ok=0
    }
    line_matches "pass in quick inet6 proto tcp from <chann_tailscale6>" "port = $port " "flags any" || {
      printf '%s\n' "tailscale-pf: missing Tailscale IPv6 TCP pass for $port" >&2
      ok=0
    }
    line_matches "pass in quick inet6 proto udp from <chann_tailscale6>" "port = $port " || {
      printf '%s\n' "tailscale-pf: missing Tailscale IPv6 UDP pass for $port" >&2
      ok=0
    }
    line_matches "block drop in quick proto tcp" "port = $port" || {
      printf '%s\n' "tailscale-pf: missing TCP block for $port" >&2
      ok=0
    }
    line_matches "block drop in quick proto udp" "port = $port" || {
      printf '%s\n' "tailscale-pf: missing UDP block for $port" >&2
      ok=0
    }
  done

  if [ "$ok" != 1 ]; then
    printf '%s\n' 'tailscale-pf: kernel rules do not match the anchor' >&2
    printf '%s\n' "$rules" >&2
    return 1
  fi

  printf '%s\n' \
    'tailscale-pf: loaded.' \
    'Allowed: lo0 and Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48).' \
    'Ports: 22 SSH, 5900 Screen Sharing (VNC), 3283 Apple Remote Management.' \
    'Other sources to those ports are blocked.' \
    'pf expanded the anchor to 18 pass rules and 6 block rules.' \
    'The -f and ALTQ lines above are warnings, not a failed load.' \
    'Microsoft RDP (3389) is not covered.'
}

loaded_rules() {
  cat <<'EOF'
pass in quick on lo0 proto tcp from any to any port = 22 flags S/SA keep state
pass in quick on lo0 proto tcp from any to any port = 5900 flags S/SA keep state
pass in quick on lo0 proto tcp from any to any port = 3283 flags S/SA keep state
pass in quick on lo0 proto udp from any to any port = 22 keep state
pass in quick on lo0 proto udp from any to any port = 5900 keep state
pass in quick on lo0 proto udp from any to any port = 3283 keep state
pass in quick inet proto tcp from <chann_tailscale4> to any port = 22 flags any keep state
pass in quick inet proto tcp from <chann_tailscale4> to any port = 5900 flags any keep state
pass in quick inet proto tcp from <chann_tailscale4> to any port = 3283 flags any keep state
pass in quick inet proto udp from <chann_tailscale4> to any port = 22 keep state
pass in quick inet proto udp from <chann_tailscale4> to any port = 5900 keep state
pass in quick inet proto udp from <chann_tailscale4> to any port = 3283 keep state
pass in quick inet6 proto tcp from <chann_tailscale6> to any port = 22 flags any keep state
pass in quick inet6 proto tcp from <chann_tailscale6> to any port = 5900 flags any keep state
pass in quick inet6 proto tcp from <chann_tailscale6> to any port = 3283 flags any keep state
pass in quick inet6 proto udp from <chann_tailscale6> to any port = 22 keep state
pass in quick inet6 proto udp from <chann_tailscale6> to any port = 5900 keep state
pass in quick inet6 proto udp from <chann_tailscale6> to any port = 3283 keep state
block drop in quick proto tcp from any to any port = 22
block drop in quick proto tcp from any to any port = 5900
block drop in quick proto tcp from any to any port = 3283
block drop in quick proto udp from any to any port = 22
block drop in quick proto udp from any to any port = 5900
block drop in quick proto udp from any to any port = 3283
EOF
}

self_test() {
  got=$(summarize "$(loaded_rules)")
  printf '%s\n' "$got" | grep -Fqx 'tailscale-pf: loaded.'
  printf '%s\n' "$got" | grep -Fqx 'Ports: 22 SSH, 5900 Screen Sharing (VNC), 3283 Apple Remote Management.'
  printf '%s\n' "$got" | grep -Fqx 'Microsoft RDP (3389) is not covered.'

  if summarize '' >/dev/null 2>&1; then
    printf '%s\n' 'self-test failed: empty rules should error' >&2
    return 1
  fi

  if summarize "$(loaded_rules)
pass in quick inet proto tcp from <chann_tailscale4> to any port = 3389 flags any keep state" >/dev/null 2>&1; then
    printf '%s\n' 'self-test failed: port 3389 should error' >&2
    return 1
  fi

  if summarize "$(printf '%s\n' "$(loaded_rules)" | grep -v 'block drop in quick proto tcp from any to any port = 22$')" >/dev/null 2>&1; then
    printf '%s\n' 'self-test failed: missing block should error' >&2
    return 1
  fi

  printf '%s\n' 'load.sh self-test ok'
}

case ${1:-} in
  --self-test)
    self_test
    exit 0
    ;;
  '') ;;
  *)
    printf '%s\n' 'Usage: load.sh [--self-test]' >&2
    exit 2
    ;;
esac

printf '%s\n' \
  'tailscale-pf: checking /etc/pf.conf, then loading it.' \
  'Expect the -f warning twice (syntax check and load) and "No ALTQ support in kernel" once.'

/sbin/pfctl -E >/dev/null 2>&1 || true
/sbin/pfctl -nf /etc/pf.conf
/sbin/pfctl -f /etc/pf.conf
summarize "$(/sbin/pfctl -a "$ANCHOR" -sr 2>/dev/null)"
