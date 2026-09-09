#!/usr/bin/env bash
# pane.closed event hook: drop the closed pane and everything registered under it.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
command -v jq >/dev/null 2>&1 || exit 0

event_json=${HERDR_PLUGIN_EVENT_JSON:-}
[ -n "$event_json" ] || exit 0
printf '%s\n' "$event_json" >"$AGENT_TREE_DIR/last-event.json"   # debugging aid
pane_id=$(jq -r '.data.pane_id // .pane_id // empty' <<<"$event_json")
[ -n "$pane_id" ] || exit 0
tree_remove_subtree "$pane_id"
