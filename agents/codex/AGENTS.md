## Herdr

Inside a Herdr pane (`HERDR_ENV=1`), start a helper with `~/dotfiles/herdr/plugins/agent-tree/spawn.sh <name> <kind> [--direction right|down] [-- args]`. Drive it with `herdr agent prompt <name>` and `herdr agent wait <name>`.

## Ponytail

Use the ponytail skill (full) for coding.

## GitHub CLI

Under `~/workspace/corp/`, run `gh auth switch --user chan-park_trueb` before the first `gh` call. Those paths use `~/.gitconfig-corp`. `channprj` lacks the `project` scope, so GitHub Projects calls fail on it. `gh auth switch` keeps that account for every later call in the session. Do not switch it back for a personal repository.

## Orchestration

Orchestrate by default. When work has two or more separable parts, plan it, split it, dispatch a team of children in parallel, merge their branches, and verify the result. Do a lookup, a one-file edit, or strictly sequential work yourself.

Only a top-level session on Fable, Opus, Astra, or Sol at `xhigh` effort or higher orchestrates. On another model, or at a known lower effort, say so in one line and work alone. A child never orchestrates.

Every child that edits files gets its own git worktree and branch. Use the host's worktree option when it has one (`isolation: "worktree"` in Claude Code and T3 Code). Otherwise run `git worktree add` and confine the child to that path. Read-only children share your checkout. Give each writer a disjoint set of files.

A child's worktree can start from the remote default branch instead of your `HEAD`. Commit what the child depends on and name that base commit in its brief.

A child's report is not evidence. Merge its branch into yours and run the project's checks on the merged tree. Then remove its worktree and branch under the cleanup rules below.

## Worktree and branch cleanup

When this session's worktree or task branch is finished, remove it in the same session and say so. Finished means every commit is on the remote default branch and later requirements, such as deploy, verification, or issue closure, are done. Require a clean `git status --short` (ignored files only) and `git rev-list --count origin/<default>..HEAD` of 0. Use `git worktree remove` without `--force` and `git branch -d`, never `-D`. If either refuses, leave it and report that. Touch only worktrees and branches this session created. Do not delete remote branches unless asked.

A child's worktree is finished once its commits are on the orchestrator's branch. For it, require `git rev-list --count <orchestrator-branch>..<child-branch>` of 0 instead of the remote check.

## Use ego-browser(ego-lite) as default agent browser

Use the `ego-browser` skill and Ego Lite for browsing, sign-in, forms, screenshots, extraction, and web UI review. Read `~/.agents/skills/ego-browser/SKILL.md` and run scripts with `ego-browser nodejs`. If the user or a higher-priority instruction names another browser, use that. If ego-browser fails, check the skill's `references/install.md`, report the cause, and name the unfinished work.

## Model selection

Give each child the cheapest model and effort that still meets the bar. Haiku/Luna `low` for mechanical work, Luna/Sonnet `medium` for scoped implementation, Sonnet `high` for demanding execution, and Opus/Astra `high` or `xhigh` for design, architecture, diagnosis, and security. Check the live catalog before dispatch, and set both on the dispatch call: an unset child can inherit the orchestrator's model and effort. Pass only the context the child needs. Keep an explicit user model choice.

## Session for Lightpanda

When Lightpanda must open a logged-in page, copy that origin's session from ego lite. Do not complete the site's login inside Lightpanda or ask for a pasted token.

Export that origin's cookies with CDP `Network.getCookies`, including HttpOnly cookies, and any localStorage token the app keeps. A cookie alone may not be enough. Pass the cookies to `lightpanda fetch --cookie` and set localStorage with `--inject-script-file` before page scripts run. Keep the files in `/tmp` at mode `0600`, delete them after, and never print them. Signed in means the final URL is the requested page. The first paint can still be a login shell. If ego lite has no session, give the user that site's login URL and read ego lite again after they sign in.
