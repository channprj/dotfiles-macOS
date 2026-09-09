#!/usr/bin/env bash
# Spawn a child agent in a split beside the current pane and register the edge.
#
# Usage (from inside a Herdr pane):
#   spawn.sh <name> <kind> [--direction right|down] [-- <agent args...>]
# Prints the child pane id.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() {
  echo "usage: spawn.sh <name> <kind> [--direction right|down] [-- agent args...]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
name=$1 kind=$2
shift 2
direction=right
while [ $# -gt 0 ]; do
  case $1 in
    --direction) direction=$2; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done

parent=${HERDR_PANE_ID:?spawn.sh must run inside a Herdr pane}
command -v jq >/dev/null || { echo "spawn.sh: jq is required" >&2; exit 127; }

child=$("$HERDR_BIN" pane split "$parent" --direction "$direction" --no-focus | jq -r '.result.pane.pane_id')
[ -n "$child" ] && [ "$child" != null ] || { echo "spawn.sh: pane split failed" >&2; exit 1; }

# Register before starting so the node shows up while the agent boots.
tree_add "$parent" "$child" "$name" pane

if [ $# -gt 0 ]; then
  "$HERDR_BIN" agent start "$name" --kind "$kind" --pane "$child" -- "$@" >/dev/null
else
  "$HERDR_BIN" agent start "$name" --kind "$kind" --pane "$child" >/dev/null
fi
echo "$child"
