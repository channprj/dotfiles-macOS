#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

for command_name in bash zsh jq expect; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'FAIL: required test command is missing: %s\n' "$command_name" >&2
    exit 127
  fi
done

bash_files=(
  install.sh
  uninstall.sh
  lib/links.sh
  lib/transaction.sh
  scripts/check-secrets.sh
  tests/install_test.bash
  tests/lazyvim_test.sh
  tests/run.sh
)

/bin/bash -n "${bash_files[@]}"
for zsh_file in sh/.zshenv sh/.zshrc sh/.zshalias sh/.zshexec sh/.zshfunc tests/hsa_test.zsh tests/shell_startup_test.zsh tests/zshfunc_test.zsh; do
  /bin/zsh -n "$zsh_file"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S warning "${bash_files[@]}"
elif [[ "${DOTFILES_REQUIRE_SHELLCHECK:-0}" == 1 ]]; then
  printf '%s\n' 'FAIL: ShellCheck is required (brew install shellcheck)' >&2
  exit 127
else
  printf '%s\n' 'SKIP: ShellCheck is not installed (brew install shellcheck)' >&2
fi

/bin/zsh tests/shell_startup_test.zsh
/bin/zsh tests/hsa_test.zsh
/usr/bin/expect tests/hsa_prompt_test.exp
/bin/zsh tests/zshfunc_test.zsh
/bin/bash tests/install_test.bash
/bin/bash tests/lazyvim_test.sh

printf '%s\n' 'PASS: all deterministic dotfiles tests passed'
