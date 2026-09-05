# Synthetic Apply Claude wrapper design

## Goal

Add a Zsh helper named `synthetic_apply_claude` that launches Claude Code
through the Synthetic Anthropic-compatible endpoint without changing the
caller's shell environment. After the command exits, a normal `claude`
invocation must retain its existing provider configuration.

## Interface

```sh
synthetic_apply_claude [claude arguments...]
```

The helper reads `SYNTHETIC_API_KEY` from the current environment, falling back
to the `synthetic.new.api-key` item in the user's macOS Keychain. It forwards
all arguments to `claude` unchanged and fails with a clear diagnostic when both
key sources are empty or Claude Code is unavailable.

## Environment contract

Only the child `claude` process receives these overrides:

- `ANTHROPIC_BASE_URL=https://api.synthetic.new/anthropic`
- `ANTHROPIC_AUTH_TOKEN` set to the environment or Keychain API key
- `ANTHROPIC_DEFAULT_OPUS_MODEL=syn:large:vision`
- `ANTHROPIC_DEFAULT_SONNET_MODEL=syn:large:vision`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL=syn:small:text`
- `CLAUDE_CODE_SUBAGENT_MODEL=syn:large:vision`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
- `CLAUDE_CODE_ATTRIBUTION_HEADER=0`

The helper will use command-scoped environment injection. It will not export,
unset, or otherwise mutate provider variables in the parent shell. Therefore
there is no separate reset command: exiting `synthetic_apply_claude` is the
rollback, and `claude` continues to use the caller's original environment.

## Repository integration

The function belongs in `sh/.zshfunc`, which the managed `sh/.zshrc` already
sources through `~/.zshfunc`. The existing dotfiles installer links that file,
and the transactional uninstaller remains the installation-level recovery path.

The README will document Keychain setup, the optional environment override,
invocation, automatic environment rollback, and the fact that API keys must
not be committed to the repository.

## Verification

The Zsh function test will use a local Claude stub and a dummy key to prove:

1. the function is defined;
2. every required environment override reaches the child process;
3. arguments, including values containing spaces, are forwarded unchanged;
4. pre-existing parent-shell provider variables remain unchanged afterward;
5. the environment variable takes precedence over Keychain;
6. the Keychain fallback does not export the key to the parent environment;
7. missing keys in both sources fail before Claude is invoked; and
8. the full deterministic dotfiles test suite remains green.

No live Synthetic request is part of deterministic verification because it
would require an external credential and service availability.
