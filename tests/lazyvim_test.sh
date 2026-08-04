#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
NVIM_DIR="$REPO_ROOT/editor/nvim"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

required_files=(
  init.lua
  lazy-lock.json
  lazyvim.json
  lua/config/lazy.lua
  lua/config/options.lua
  lua/plugins/example.lua
  UPSTREAM.md
)

for required_file in "${required_files[@]}"; do
  [[ -f "$NVIM_DIR/$required_file" ]] || fail "missing $required_file"
done

if find "$NVIM_DIR" -type d -name .git -print -quit | grep -q .; then
  fail "nested .git directory is not allowed"
fi

for runtime_dir in .cache cache data state share; do
  [[ ! -e "$NVIM_DIR/$runtime_dir" ]] || fail "runtime directory is tracked: $runtime_dir"
done

jq -e '.LazyVim.commit and .["lazy.nvim"].commit' "$NVIM_DIR/lazy-lock.json" >/dev/null ||
  fail "lazy-lock.json does not pin LazyVim and lazy.nvim"
jq empty "$NVIM_DIR/.neoconf.json" "$NVIM_DIR/lazy-lock.json" "$NVIM_DIR/lazyvim.json"

grep -Fq 'vim.opt.ambiwidth = "single"' "$NVIM_DIR/lua/config/options.lua" ||
  fail "local ambiwidth option is missing"
grep -Eq '`[0-9a-f]{40}`' "$NVIM_DIR/UPSTREAM.md" ||
  fail "Starter revision is not documented"

if command -v nvim >/dev/null 2>&1; then
  while IFS= read -r lua_file; do
    nvim --headless -u NONE "+lua assert(loadfile([[$lua_file]]))" +qa >/dev/null 2>&1 ||
      fail "invalid Lua: ${lua_file#$NVIM_DIR/}"
  done < <(find "$NVIM_DIR" -type f -name '*.lua' | LC_ALL=C sort)
fi

printf '%s\n' 'PASS: LazyVim snapshot is pinned, clean, and preserves local options'
