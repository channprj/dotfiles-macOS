# Agent Tree (Herdr plugin)

Live parent → child tree of coding agents in a Herdr pane.

Herdr itself only knows workspace → tab → pane. This plugin adds an explicit
edge registry so a lead agent, the helpers it spawns in side panes, and the
in-process subagents Claude Code runs inside a pane all show up as one tree.

```
▸ userscripts
  ● lead (claude · w1:p1)
    ◉ review (codex · w1:p2)
    ● test (claude · w1:p3)
      └ ⋯ Explore
▸ dotfiles
  ○ claude (claude · w2:p1)
```

## Files

| File | Role |
| --- | --- |
| `spawn.sh <name> <kind> [--direction right\|down] [-- args]` | Split beside the current pane, start an agent there, register the edge. Prints the child pane id. |
| `hook.sh` | Claude Code `SubagentStart` / `SubagentStop` hook. Registers in-process subagents as leaf nodes. No-op outside Herdr. |
| `tree.sh` | Renderer for the `tree` plugin pane. Polls every second; `q` quits. |
| `prune.sh` | `pane.closed` event hook. Drops the closed pane and everything under it. |
| `lib.sh` | State file helpers. |

State lives in `~/.local/state/herdr-agent-tree/tree.tsv`
(`socket, parent_pane, child, label, kind`). Rows are keyed by Herdr socket so
several named sessions can share the file.

## Setup

```sh
herdr plugin link ~/dotfiles/herdr/plugins/agent-tree
```

Claude Code hooks (`~/.claude/settings.json`):

```json
"SubagentStart": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash /Users/chan.park/dotfiles/herdr/plugins/agent-tree/hook.sh", "timeout": 5 }] }],
"SubagentStop":  [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash /Users/chan.park/dotfiles/herdr/plugins/agent-tree/hook.sh", "timeout": 5 }] }]
```

## Use

Open the tree:

```sh
herdr plugin pane open --plugin chann.agent-tree --entrypoint tree --placement split --direction right --no-focus
```

Spawn a child from inside any pane (a lead agent does the same):

```sh
~/dotfiles/herdr/plugins/agent-tree/spawn.sh review codex
~/dotfiles/herdr/plugins/agent-tree/spawn.sh test claude --direction down
```

Children started with plain `herdr agent start` are not linked to a parent and
appear as roots. Tell your agents to use `spawn.sh` instead.

Optional keybinding (`config.toml`):

```toml
[[keys.command]]
key = "prefix+t"
type = "pane"
command = "bash ~/dotfiles/herdr/plugins/agent-tree/tree.sh"
description = "agent tree"
```
