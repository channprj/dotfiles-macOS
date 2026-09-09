# shellcheck shell=bash
# Shared state helpers for the agent-tree plugin.
#
# State file: one row per edge, tab-separated:
#   socket <TAB> parent_pane <TAB> child <TAB> label <TAB> kind
# kind is "pane" (child is a Herdr pane id) or "sub" (child is a Claude Code
# subagent id living inside the parent pane). Rows are keyed by the Herdr
# socket so several sessions can share the file without pane id collisions.
#
# The path is fixed on purpose: hook.sh runs under Claude Code, not Herdr, so
# it never receives HERDR_PLUGIN_STATE_DIR.

AGENT_TREE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-agent-tree"
AGENT_TREE_FILE="$AGENT_TREE_DIR/tree.tsv"
AGENT_TREE_LOCK="$AGENT_TREE_DIR/.lock"
HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
AGENT_TREE_SOCKET="${HERDR_SOCKET_PATH:-default}"

mkdir -p "$AGENT_TREE_DIR"
[ -f "$AGENT_TREE_FILE" ] || : >"$AGENT_TREE_FILE"

# mkdir-based lock: macOS ships no flock(1).
tree_lock() {
  local i
  for i in $(seq 1 100); do
    mkdir "$AGENT_TREE_LOCK" 2>/dev/null && return 0
    sleep 0.02
  done
  return 1
}
tree_unlock() { rmdir "$AGENT_TREE_LOCK" 2>/dev/null || true; }

tree_add() { # <parent_pane> <child> <label> <kind>
  tree_lock || return 1
  printf '%s\t%s\t%s\t%s\t%s\n' "$AGENT_TREE_SOCKET" "$1" "$2" "$3" "$4" >>"$AGENT_TREE_FILE"
  tree_unlock
}

# Rewrite the file keeping only rows for which the awk program prints.
tree_filter() { # <awk condition over $1..$5>
  local tmp
  tree_lock || return 1
  tmp=$(mktemp "$AGENT_TREE_DIR/tree.XXXXXX")
  awk -F'\t' -v sock="$AGENT_TREE_SOCKET" "!(\$1==sock && ($1))" "$AGENT_TREE_FILE" >"$tmp" && mv "$tmp" "$AGENT_TREE_FILE"
  tree_unlock
}

tree_remove_child() { tree_filter "\$3==\"$1\""; }

# Remove a pane and everything registered beneath it.
tree_remove_subtree() { # <pane_id>
  local ids="$1" next
  while :; do
    next=$(awk -F'\t' -v sock="$AGENT_TREE_SOCKET" -v ids="$ids" '
      BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) seen[a[i]] = 1 }
      $1 == sock && ($2 in seen) && !($3 in seen) { print $3 }' "$AGENT_TREE_FILE")
    [ -n "$next" ] || break
    ids="$ids $next"
  done
  tree_filter "$(printf '%s' "$ids" | awk '{ for (i = 1; i <= NF; i++) printf "%s$2==\"%s\" || $3==\"%s\"", (i > 1 ? " || " : ""), $i, $i }')"
}

# Rows for this socket only.
tree_rows() { awk -F'\t' -v sock="$AGENT_TREE_SOCKET" '$1==sock' "$AGENT_TREE_FILE"; }
