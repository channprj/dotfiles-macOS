#!/bin/zsh

emulate -L zsh
setopt errexit nounset pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-shell.XXXXXX")"
TEST_HOME="$TEST_ROOT/home"

cleanup() {
  command rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"
}

for config in .zshenv .zshrc .zshalias .zshexec .zshfunc; do
  /bin/zsh -n "$REPO_ROOT/sh/$config"
done

mkdir -p "$TEST_HOME"
ln -s "$REPO_ROOT/sh/.zshenv" "$TEST_HOME/.zshenv"

noninteractive="$({
  env -i \
    HOME="$TEST_HOME" \
    ZDOTDIR="$TEST_HOME" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/bin" \
    /bin/zsh -c '
      source "$ZDOTDIR/.zshenv"
      unique_path=("${(u)path[@]}")
      integer path_index=1 pyenv_bin_index=0 pyenv_shims_index=0 homebrew_index=0
      typeset path_entry
      for path_entry in "${path[@]}"; do
        [[ "$path_entry" == "$HOME/.pyenv/bin" ]] && pyenv_bin_index=$path_index
        [[ "$path_entry" == "$HOME/.pyenv/shims" ]] && pyenv_shims_index=$path_index
        [[ "$path_entry" == "/opt/homebrew/bin" ]] && homebrew_index=$path_index
        (( path_index++ ))
      done
      print -r -- __DOTFILES_MARKER__
      print -r -- "$ANDROID_HOME"
      print -r -- "${PYENV_ROOT-__UNSET__}"
      print -r -- "${#path}:${#unique_path}"
      print -r -- "$pyenv_bin_index:$pyenv_shims_index:$homebrew_index"
    '
} 2>&1)"
noninteractive_lines=("${(@f)noninteractive}")

assert_eq 5 "${#noninteractive_lines}" ".zshenv emitted unexpected output"
assert_eq __DOTFILES_MARKER__ "$noninteractive_lines[1]" ".zshenv changed command output"
assert_eq "$TEST_HOME/Library/Android/sdk" "$noninteractive_lines[2]" "Android path is not HOME-relative"
path_counts=("${(@s/:/)noninteractive_lines[4]}")
assert_eq "$path_counts[1]" "$path_counts[2]" "PATH contains duplicate entries"
path_order=("${(@s/:/)noninteractive_lines[5]}")
(( path_order[1] > 0 )) || fail "pyenv bin is missing from PATH"
(( path_order[2] > 0 )) || fail "pyenv shims are missing from PATH"
(( path_order[3] > 0 )) || fail "Homebrew bin is missing from PATH"
(( path_order[1] < path_order[2] )) || fail "pyenv bin does not precede pyenv shims"
(( path_order[2] < path_order[3] )) || fail "pyenv shims do not precede Homebrew bin"
assert_eq "$TEST_HOME/.pyenv" "$noninteractive_lines[3]" "PYENV_ROOT is not HOME-relative"

# Reset PATH after .zshenv so optional tools are absent while .zshrc loads.
rm "$TEST_HOME/.zshenv"
printf 'source %q\npath=(/usr/bin /bin /usr/sbin /sbin)\nexport PATH\n' \
  "$REPO_ROOT/sh/.zshenv" >"$TEST_HOME/.zshenv"
for config in .zshrc .zshalias .zshfunc .zshexec; do
  ln -s "$REPO_ROOT/sh/$config" "$TEST_HOME/$config"
done

interactive="$({
  env -i \
    HOME="$TEST_HOME" \
    ZDOTDIR="$TEST_HOME" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=dumb \
    /bin/zsh -i -c 'print -r -- "$EDITOR|$VISUAL|$ZSH_THEME"'
} 2>&1)"
assert_eq 'mdner --wait|mdner --wait|dpoggi' "$interactive" "minimal interactive shell did not load cleanly"

mkdir -p "$TEST_HOME/.oh-my-zsh/custom/themes"
printf '# installed by the terminal module\n' >"$TEST_HOME/.oh-my-zsh/custom/themes/dpoggi-timestamp.zsh-theme"
theme="$({
  env -i \
    HOME="$TEST_HOME" \
    ZDOTDIR="$TEST_HOME" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=dumb \
    /bin/zsh -i -c 'print -r -- "$ZSH_THEME"'
} 2>&1)"
assert_eq dpoggi-timestamp "$theme" "installed terminal theme was not selected"

plugin_prefix="$TEST_ROOT/homebrew"
plugin_bin="$TEST_ROOT/bin"
mkdir -p \
  "$plugin_bin" \
  "$plugin_prefix/share/zsh-completions" \
  "$plugin_prefix/share/zsh-autosuggestions" \
  "$plugin_prefix/share/zsh-syntax-highlighting"
cat >"$plugin_bin/brew" <<EOF
#!/bin/sh
case "\$1" in
  shellenv) printf '%s\n' 'export HOMEBREW_PREFIX=$plugin_prefix' ;;
  --prefix) printf '%s\n' '$plugin_prefix' ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$plugin_bin/brew"
cat >"$plugin_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" <<'EOF'
typeset -g DOTFILES_TEST_ZSH_PLUGIN_ORDER=autosuggestions
EOF
cat >"$plugin_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" <<'EOF'
DOTFILES_TEST_ZSH_PLUGIN_ORDER="${DOTFILES_TEST_ZSH_PLUGIN_ORDER},syntax-highlighting"
EOF
printf 'source %q\npath=(%q /usr/bin /bin /usr/sbin /sbin)\nexport PATH\n' \
  "$REPO_ROOT/sh/.zshenv" "$plugin_bin" >"$TEST_HOME/.zshenv"

plugin_output="$({
  env -i \
    HOME="$TEST_HOME" \
    ZDOTDIR="$TEST_HOME" \
    PATH="$plugin_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=dumb \
    /usr/bin/script -q /dev/null /bin/zsh -i -c \
      'print -r -- "__ZSH_PLUGINS__|$fpath[1]|${DOTFILES_TEST_ZSH_PLUGIN_ORDER-}"'
} 2>&1)"
[[ "$plugin_output" == *"__ZSH_PLUGINS__|$plugin_prefix/share/zsh-completions|autosuggestions,syntax-highlighting"* ]] ||
  fail "Homebrew Zsh plugins did not load in completion/autosuggestion/highlighting order: $plugin_output"

excludes_file="$(HOME="$TEST_HOME" git config --file "$REPO_ROOT/git/.gitconfig" --path --get core.excludesfile)"
assert_eq "$TEST_HOME/.gitignore_global" "$excludes_file" "global Git excludes path is not portable"

if grep -R -n -E 'GREP_OPTIONS|/Users/' "$REPO_ROOT/sh" "$REPO_ROOT/git/.gitconfig" >/dev/null; then
  fail "active shell or Git configuration contains a retired machine-specific setting"
fi

print "PASS: shell startup is quiet, portable, guarded, and PATH-idempotent"
