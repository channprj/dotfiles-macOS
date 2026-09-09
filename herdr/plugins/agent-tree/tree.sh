#!/usr/bin/env bash
# Live tree renderer. Runs inside a Herdr plugin pane; q quits.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
command -v jq >/dev/null 2>&1 || { echo "tree.sh: jq is required"; exit 127; }

interval=${AGENT_TREE_INTERVAL:-1}
bold=$(tput bold 2>/dev/null || true) dim=$(tput dim 2>/dev/null || true) reset=$(tput sgr0 2>/dev/null || true)
red=$(tput setaf 1 2>/dev/null || true) green=$(tput setaf 2 2>/dev/null || true)
yellow=$(tput setaf 3 2>/dev/null || true) blue=$(tput setaf 4 2>/dev/null || true)

icon() {
  case $1 in
    working) printf '%s●%s' "$green" "$reset" ;;
    blocked) printf '%s◉%s' "$red" "$reset" ;;
    done)    printf '%s✔%s' "$blue" "$reset" ;;
    idle)    printf '%s○%s' "$dim" "$reset" ;;
    *)       printf '%s?%s' "$yellow" "$reset" ;;
  esac
}

# Print one node and its registered children. $1 pane id, $2 indent.
draw() {
  local pane="$1" indent="$2" agent status label
  agent=$(jq -r --arg p "$pane" '.[] | select(.pane_id==$p) | .agent // empty' <<<"$PANES")
  status=$(jq -r --arg p "$pane" '.[] | select(.pane_id==$p) | .agent_status // "none"' <<<"$PANES")
  label=$(awk -F'\t' -v c="$pane" '$3==c { print $4; exit }' <<<"$ROWS")
  if [ -n "$agent" ]; then
    printf '%s%s %s%s%s %s(%s · %s)%s\n' "$indent" "$(icon "$status")" "$bold" "${label:-$agent}" "$reset" "$dim" "$agent" "$pane" "$reset"
  else
    printf '%s%s$%s %s%s(%s)%s\n' "$indent" "$dim" "$reset" "${label:-shell}" "$dim" "$pane" "$reset"
  fi
  while IFS=$'\t' read -r _ _ child clabel kind; do
    [ -n "$child" ] || continue
    if [ "$kind" = sub ]; then
      printf '%s  %s└ ⋯ %s%s\n' "$indent" "$dim" "$clabel" "$reset"
    elif grep -qxF "$child" <<<"$LIVE"; then
      draw "$child" "$indent  "
    fi
  done < <(awk -F'\t' -v p="$pane" '$2==p' <<<"$ROWS")
}

render() {
  PANES=$("$HERDR_BIN" pane list 2>/dev/null | jq -c '.result.panes // []')
  WORKSPACES=$("$HERDR_BIN" workspace list 2>/dev/null | jq -r '.result.workspaces[] | "\(.workspace_id)\t\(.label)"')
  ROWS=$(tree_rows)
  LIVE=$(jq -r '.[].pane_id' <<<"$PANES")

  # Roots: live panes that are agents or have children, and are not a live child.
  local children roots
  children=$(awk -F'\t' '$5=="pane" { print $3 }' <<<"$ROWS")
  roots=$(jq -r '.[] | select(.agent != null) | .pane_id' <<<"$PANES"
          awk -F'\t' '$5=="pane" || $5=="sub" { print $2 }' <<<"$ROWS")
  roots=$(printf '%s\n' "$roots" | grep -xF -f <(printf '%s\n' "$LIVE") | grep -vxF -f <(printf '%s\n' "$children"; echo __none__) | sort -u)

  {
    printf '%sagent tree%s  %s%s%s\n\n' "$bold" "$reset" "$dim" "$(date +%H:%M:%S) · q to quit" "$reset"
    while IFS=$'\t' read -r wid wlabel; do
      [ -n "$wid" ] || continue
      printf '%s▸ %s%s\n' "$bold" "$wlabel" "$reset"
      local found=0 r
      for r in $roots; do
        case $r in "$wid:"*) draw "$r" "  "; found=1 ;; esac
      done
      [ $found = 1 ] || printf '  %s(no agents)%s\n' "$dim" "$reset"
    done <<<"$WORKSPACES"
  } >"$FRAME"
  tput cup 0 0 2>/dev/null || printf '\033[H'
  cat "$FRAME"
  tput ed 2>/dev/null || printf '\033[J'
}

FRAME=$(mktemp "${TMPDIR:-/tmp}/agent-tree.XXXXXX")
trap 'rm -f "$FRAME"; tput cnorm 2>/dev/null; exit 0' EXIT INT TERM
tput civis 2>/dev/null; clear
while :; do
  render
  if read -r -t "$interval" -n 1 key 2>/dev/null; then
    [ "$key" = q ] && exit 0
  fi
done
