## Herdr

Inside a Herdr pane (`HERDR_ENV=1`), start a helper with `~/dotfiles/herdr/plugins/agent-tree/spawn.sh <name> <kind> [--direction right|down] [-- args]`. Drive it with `herdr agent prompt <name>` and `herdr agent wait <name>`.

## Ponytail

Use the ponytail skill (full) for coding.

## GitHub CLI

Under `~/workspace/corp/`, run `gh auth switch --user chan-park_trueb` before the first `gh` call. Those paths use `~/.gitconfig-corp`. `channprj` lacks the `project` scope, so GitHub Projects calls fail on it. `gh auth switch` keeps that account for every later call in the session. Do not switch it back for a personal repository.

## Worktree and branch cleanup

When this session's worktree or task branch is finished, remove it in the same session and say so. Finished means every commit is on the remote default branch and later requirements, such as deploy, verification, or issue closure, are done. Require a clean `git status --short` (ignored files only) and `git rev-list --count origin/<default>..HEAD` of 0. Use `git worktree remove` without `--force` and `git branch -d`, never `-D`. If either refuses, leave it and report that. Touch only worktrees and branches this session created. Do not delete remote branches unless asked.

## Human decisions and push notifications

Before a plain-text question or blocking decision with no question tool, run this and then ask. Structured questions and permission prompts already notify.

```sh
node ~/.local/share/agent-input-notify/notify.mjs --message 'A brief summary of the decision needed'
```

The summary is Korean and names the decision. No secrets, credentials, raw commands, or file dumps. Skip routine progress and normal completion. A failed alert still allows the question. A push is not permission to proceed.

## Use ego-browser(ego-lite) as default agent browser

Use the `ego-browser` skill and Ego Lite for browsing, sign-in, forms, screenshots, extraction, and web UI review. Read `~/.agents/skills/ego-browser/SKILL.md` and run scripts with `ego-browser nodejs`. If the user or a higher-priority instruction names another browser, use that. If ego-browser fails, check the skill's `references/install.md`, report the cause, and name the unfinished work.

## Model selection

Use the cheapest model and effort that still meets the bar. Haiku/Luna `low` for mechanical work, Luna/Sonnet `medium` for scoped implementation, Sonnet `high` for demanding execution, and Opus/Astra `high` or `xhigh` for design, architecture, diagnosis, and security. Check the live catalog before dispatch. Pass only the context the child needs. Keep an explicit user model choice.

## Session for Lightpanda

When Lightpanda must open a logged-in page, copy that origin's session from ego lite. Do not complete the site's login inside Lightpanda or ask for a pasted token.

Export that origin's cookies with CDP `Network.getCookies`, including HttpOnly cookies, and any localStorage token the app keeps. A cookie alone may not be enough. Pass the cookies to `lightpanda fetch --cookie` and set localStorage with `--inject-script-file` before page scripts run. Keep the files in `/tmp` at mode `0600`, delete them after, and never print them. Signed in means the final URL is the requested page. The first paint can still be a login shell. If ego lite has no session, give the user that site's login URL and read ego lite again after they sign in.
