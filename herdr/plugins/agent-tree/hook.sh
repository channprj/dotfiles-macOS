#!/usr/bin/env bash
# Claude Code SubagentStart / SubagentStop hook.
# Registers in-process subagents as leaf nodes under the pane Claude runs in.
# No-op outside Herdr.
set -u
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

input=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$input")
agent_id=$(jq -r '.agent_id // empty' <<<"$input")
agent_type=$(jq -r '.agent_type // "subagent"' <<<"$input")
[ -n "$agent_id" ] || exit 0

case $event in
  SubagentStart) tree_add "$HERDR_PANE_ID" "$agent_id" "$agent_type" sub ;;
  SubagentStop) tree_remove_child "$agent_id" ;;
esac
exit 0
