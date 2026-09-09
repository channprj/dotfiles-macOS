#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipefail

typeset -a calls=()

tccutil() {
  calls+=("$*")
}

source "${0:A:h:h}/sh/.zshfunc"

if (( ! $+functions[reset-iterm2-permissions] )); then
  print -u2 "reset-iterm2-permissions is not defined"
  exit 1
fi
if (( ! $+functions[synthetic_apply_claude] )); then
  print -u2 "synthetic_apply_claude is not defined"
  exit 1
fi

reset-iterm2-permissions

typeset -a expected=(
  "reset SystemPolicyRemovableVolumes com.googlecode.iterm2"
  "reset SystemPolicyAllFiles com.googlecode.iterm2"
)

if [[ "${(j:\n:)calls}" != "${(j:\n:)expected}" ]]; then
  print -u2 "unexpected tccutil calls"
  print -u2 "expected: ${(j: | :)expected}"
  print -u2 "actual:   ${(j: | :)calls}"
  exit 1
fi

test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zshfunc-test.XXXXXX")"
trap '/bin/rm -rf -- "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/empty"

cat >"$test_tmp/bin/claude" <<'EOF'
#!/bin/zsh

{
  print -r -- "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
  print -r -- "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN"
  print -r -- "ANTHROPIC_DEFAULT_OPUS_MODEL=$ANTHROPIC_DEFAULT_OPUS_MODEL"
  print -r -- "ANTHROPIC_DEFAULT_SONNET_MODEL=$ANTHROPIC_DEFAULT_SONNET_MODEL"
  print -r -- "ANTHROPIC_DEFAULT_HAIKU_MODEL=$ANTHROPIC_DEFAULT_HAIKU_MODEL"
  print -r -- "CLAUDE_CODE_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL"
  print -r -- "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
  print -r -- "CLAUDE_CODE_ATTRIBUTION_HEADER=$CLAUDE_CODE_ATTRIBUTION_HEADER"
  for argument in "$@"; do
    print -r -- "ARG=$argument"
  done
} >"$SYNTHETIC_CLAUDE_CAPTURE"
EOF
chmod +x "$test_tmp/bin/claude"

cat >"$test_tmp/bin/security" <<'EOF'
#!/bin/zsh

print -rl -- "$@" >"$SYNTHETIC_KEYCHAIN_CAPTURE"
if [[ "${1:-}" == "add-generic-password" ]]; then
  exit "${SYNTHETIC_KEYCHAIN_SAVE_STATUS:-0}"
fi
expected="find-generic-password -a $SYNTHETIC_KEYCHAIN_ACCOUNT -s synthetic.new.api-key -w"
[[ "$*" == "$expected" ]] || exit 64
[[ "${SYNTHETIC_KEYCHAIN_RESULT:-missing}" == "present" ]] || exit 44
print -r -- "$SYNTHETIC_KEYCHAIN_API_KEY"
EOF
chmod +x "$test_tmp/bin/security"

export PATH="$test_tmp/bin:$PATH"
export SYNTHETIC_CLAUDE_CAPTURE="$test_tmp/claude-capture"
export SYNTHETIC_KEYCHAIN_CAPTURE="$test_tmp/keychain-capture"
export SYNTHETIC_KEYCHAIN_ACCOUNT="$USER"
export SYNTHETIC_KEYCHAIN_API_KEY="keychain-test-key"
export SYNTHETIC_KEYCHAIN_RESULT="present"
export SYNTHETIC_API_KEY="synthetic-test-key"
export ANTHROPIC_BASE_URL="parent-base"
export ANTHROPIC_AUTH_TOKEN="parent-token"
export ANTHROPIC_DEFAULT_OPUS_MODEL="parent-opus"
export ANTHROPIC_DEFAULT_SONNET_MODEL="parent-sonnet"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="parent-haiku"
export CLAUDE_CODE_SUBAGENT_MODEL="parent-subagent"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="parent-traffic"
export CLAUDE_CODE_ATTRIBUTION_HEADER="parent-attribution"

synthetic_apply_claude --model "argument with spaces"

typeset -a expected_capture=(
  "ANTHROPIC_BASE_URL=https://api.synthetic.new/anthropic"
  "ANTHROPIC_AUTH_TOKEN=synthetic-test-key"
  "ANTHROPIC_DEFAULT_OPUS_MODEL=syn:large:vision"
  "ANTHROPIC_DEFAULT_SONNET_MODEL=syn:large:vision"
  "ANTHROPIC_DEFAULT_HAIKU_MODEL=syn:small:text"
  "CLAUDE_CODE_SUBAGENT_MODEL=syn:large:vision"
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
  "CLAUDE_CODE_ATTRIBUTION_HEADER=0"
  "ARG=--model"
  "ARG=argument with spaces"
)
actual_capture="$(<"$SYNTHETIC_CLAUDE_CAPTURE")"
expected_capture_text="${(F)expected_capture}"
if [[ "$actual_capture" != "$expected_capture_text" ]]; then
  print -u2 "unexpected Synthetic Claude environment or arguments"
  print -u2 "expected: ${(j: | :)expected_capture}"
  print -u2 "actual:   ${(j: | :)${(f)actual_capture}}"
  exit 1
fi

typeset -a expected_parent_environment=(
  "parent-base"
  "parent-token"
  "parent-opus"
  "parent-sonnet"
  "parent-haiku"
  "parent-subagent"
  "parent-traffic"
  "parent-attribution"
)
typeset -a actual_parent_environment=(
  "$ANTHROPIC_BASE_URL"
  "$ANTHROPIC_AUTH_TOKEN"
  "$ANTHROPIC_DEFAULT_OPUS_MODEL"
  "$ANTHROPIC_DEFAULT_SONNET_MODEL"
  "$ANTHROPIC_DEFAULT_HAIKU_MODEL"
  "$CLAUDE_CODE_SUBAGENT_MODEL"
  "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
  "$CLAUDE_CODE_ATTRIBUTION_HEADER"
)
if [[ "${(j:\n:)actual_parent_environment}" != "${(j:\n:)expected_parent_environment}" ]]; then
  print -u2 "synthetic_apply_claude changed the parent environment"
  exit 1
fi

rm -f -- "$SYNTHETIC_CLAUDE_CAPTURE"
unset SYNTHETIC_API_KEY
synthetic_apply_claude --version
keychain_capture="$(<"$SYNTHETIC_CLAUDE_CAPTURE")"
if [[ "$keychain_capture" != *"ANTHROPIC_AUTH_TOKEN=keychain-test-key"* ]]; then
  print -u2 "synthetic_apply_claude did not use the Keychain API key"
  exit 1
fi
if [[ "$keychain_capture" != *"ARG=--version"* ]]; then
  print -u2 "synthetic_apply_claude did not forward arguments with the Keychain API key"
  exit 1
fi
if (( ${+SYNTHETIC_API_KEY} )); then
  print -u2 "synthetic_apply_claude exported the Keychain API key to the parent environment"
  exit 1
fi

rm -f -- "$SYNTHETIC_CLAUDE_CAPTURE"
export SYNTHETIC_KEYCHAIN_RESULT="missing"
missing_key_error="$test_tmp/missing-key-error"
if synthetic_apply_claude --version >/dev/null 2>"$missing_key_error"; then
  print -u2 "synthetic_apply_claude accepted missing environment and Keychain API keys"
  exit 1
fi
if [[ -e "$SYNTHETIC_CLAUDE_CAPTURE" ]]; then
  print -u2 "synthetic_apply_claude invoked Claude without an API key"
  exit 1
fi
if [[ "$(<"$missing_key_error")" != "synthetic_apply_claude: API key was not found in SYNTHETIC_API_KEY or Keychain" ]]; then
  print -u2 "synthetic_apply_claude returned an unexpected missing-key error"
  exit 1
fi

# Configuration must work before either an API key or Claude is installed.
mv "$test_tmp/bin/claude" "$test_tmp/claude"
original_path="$PATH"
PATH="$test_tmp/bin"
rehash
config_output="$test_tmp/config-output"
if ! synthetic_apply_claude config >"$config_output" 2>&1; then
  print -u2 "synthetic_apply_claude config required an existing API key or Claude executable"
  exit 1
fi
typeset -a expected_config_args=(
  add-generic-password
  -a "$USER"
  -s synthetic.new.api-key
  -l "Synthetic API Key"
  -U
  -w
)
if [[ "$(<"$SYNTHETIC_KEYCHAIN_CAPTURE")" != "${(F)expected_config_args}" ]]; then
  print -u2 "config did not request an interactive Keychain password update"
  exit 1
fi
if [[ -e "$SYNTHETIC_CLAUDE_CAPTURE" ]] || (( ${+SYNTHETIC_API_KEY} )); then
  print -u2 "config launched Claude or exported an API key"
  exit 1
fi

# An environment override must not bypass configuration or hide save failures.
export SYNTHETIC_API_KEY="synthetic-test-key"
export SYNTHETIC_KEYCHAIN_SAVE_STATUS=37
config_status=0
synthetic_apply_claude config >"$config_output" 2>&1 || config_status=$?
if (( config_status != 37 )) || [[ "$(<"$config_output")" == *"saved"* ]]; then
  print -u2 "config did not propagate the Keychain save failure"
  exit 1
fi
unset SYNTHETIC_KEYCHAIN_SAVE_STATUS
PATH="$original_path"
rehash
mv "$test_tmp/claude" "$test_tmp/bin/claude"

rm -f -- "$SYNTHETIC_KEYCHAIN_CAPTURE"
config_status=0
synthetic_apply_claude config unexpected-argument >"$config_output" 2>&1 || config_status=$?
if (( config_status != 2 )) || [[ -e "$SYNTHETIC_KEYCHAIN_CAPTURE" || -e "$SYNTHETIC_CLAUDE_CAPTURE" ]]; then
  print -u2 "config accepted extra arguments or ran a command before rejecting them"
  exit 1
fi

export SYNTHETIC_API_KEY="synthetic-test-key"
export SYNTHETIC_KEYCHAIN_RESULT="present"
original_path="$PATH"
PATH="$test_tmp/empty"
rehash
config_status=0
synthetic_apply_claude config >"$config_output" 2>&1 || config_status=$?
if (( config_status != 127 )) || [[ "$(<"$config_output")" != *"security"* ]]; then
  print -u2 "config did not report the missing Keychain command"
  exit 1
fi
missing_claude_error="$test_tmp/missing-claude-error"
if synthetic_apply_claude --version >/dev/null 2>"$missing_claude_error"; then
  print -u2 "synthetic_apply_claude accepted a missing Claude executable"
  exit 1
fi
PATH="$original_path"
rehash
if [[ "$(<"$missing_claude_error")" != "synthetic_apply_claude: claude is not installed or not in PATH" ]]; then
  print -u2 "synthetic_apply_claude returned an unexpected missing-Claude error"
  exit 1
fi

print "PASS: Zsh functions reset iTerm2 permissions and isolate Synthetic Claude"
