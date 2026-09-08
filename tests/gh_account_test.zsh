#!/bin/zsh

emulate -L zsh
setopt errexit nounset pipefail

repo_root="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-gh-account.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/home/workspace/corp/project/nested" \
  "$test_root/home/workspace/corporate" "$test_root/home/personal" "$test_root/empty"
ln -s "$test_root/home/workspace/corp/project" "$test_root/home/corp-link"

cat >"$test_root/bin/gh" <<'EOF'
#!/bin/zsh -df
setopt nounset
case "$1 $2" in
  'config get')
    print -r -- "$(<"$GH_TEST_ACTIVE")"
    ;;
  'auth switch')
    [[ "${GH_TEST_SWITCH_FAIL:-0}" == 0 ]] || exit 4
    print -r -- "$6" >"$GH_TEST_ACTIVE"
    print -r -- "$6" >>"$GH_TEST_SWITCHES"
    ;;
  'auth token')
    [[ "${GH_TEST_TOKEN_FAIL:-0}" == 0 ]] || exit 5
    [[ "${GH_TEST_EMPTY_TOKEN:-0}" == 0 ]] || exit 0
    [[ -z "${GH_TEST_RACE:-}" ]] || print -r -- "$GH_TEST_RACE" >"$GH_TEST_ACTIVE"
    print -r -- "test-token-for-$6"
    ;;
  *)
    print -r -- "${GH_TOKEN:-${GITHUB_TOKEN:-unset}}" >"$GH_TEST_CAPTURE"
    printf '%s\n' "$@" >>"$GH_TEST_CAPTURE"
    print -r -- "command-output"
    exit "${GH_TEST_EXIT:-0}"
    ;;
esac
EOF
chmod +x "$test_root/bin/gh"

run_gh() {
  local directory="$1"
  shift
  env HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" \
    GH_TEST_ACTIVE="$test_root/active" GH_TEST_SWITCHES="$test_root/switches" \
    GH_TEST_CAPTURE="$test_root/capture" \
    /bin/zsh -dfc '
      source "$1"
      path=("$2" /usr/bin /bin)
      cd -- "$3"
      shift 3
      gh "$@"
    ' -- "$repo_root/sh/.zshenv" "$test_root/bin" "$directory" "$@"
}

assert_eq() {
  [[ "$1" == "$2" ]] || {
    print -u2 -- "FAIL: $3 (expected '$1', got '$2')"
    exit 1
  }
}

unset GH_TOKEN GITHUB_TOKEN GH_HOST
print -r -- chan-park_trueb >"$test_root/active"
: >"$test_root/switches"

for directory in personal workspace/corp workspace/corp/project/nested workspace/corporate corp-link personal; do
  case "$directory" in
    workspace/corp | workspace/corp/* | corp-link) expected_user=chan-park_trueb ;;
    *) expected_user=channprj ;;
  esac
  output="$(run_gh "$test_root/home/$directory" api user --jq '.login')"
  assert_eq command-output "$output" "wrapper polluted stdout"
  assert_eq "$expected_user" "$(cat -- "$test_root/active")" "wrong account in $directory"
  assert_eq "test-token-for-$expected_user" "$(head -1 "$test_root/capture")" "wrong token in $directory"
done
assert_eq 5 "$(wc -l <"$test_root/switches" | tr -d ' ')" "redundant or missing account switches"

run_gh "$test_root/home/personal" api user --jq 'argument with spaces' >/dev/null
assert_eq $'test-token-for-channprj\napi\nuser\n--jq\nargument with spaces' \
  "$(cat -- "$test_root/capture")" "arguments were changed"

GH_TEST_RACE=chan-park_trueb run_gh "$test_root/home/personal" api user >/dev/null
assert_eq test-token-for-channprj "$(head -1 "$test_root/capture")" "another terminal changed the command account"
assert_eq chan-park_trueb "$(cat -- "$test_root/active")" "race fixture did not switch the shared account"

run_gh "$test_root/home/personal" auth status >/dev/null
assert_eq channprj "$(cat -- "$test_root/active")" "auth status did not select the directory account"
assert_eq unset "$(head -1 "$test_root/capture")" "auth status hid the stored authentication source"

for token_name in GH_TOKEN GITHUB_TOKEN; do
  print -r -- chan-park_trueb >"$test_root/active"
  export "$token_name=explicit-test-token"
  run_gh "$test_root/home/personal" api user >/dev/null
  assert_eq explicit-test-token "$(head -1 "$test_root/capture")" "explicit token was replaced"
  assert_eq chan-park_trueb "$(cat -- "$test_root/active")" "explicit token switched the account"
  unset "$token_name"
done

for auth_command in login logout refresh setup-git; do
  run_gh "$test_root/home/personal" auth "$auth_command" >/dev/null
  assert_eq chan-park_trueb "$(cat -- "$test_root/active")" "authentication management switched the account"
done
run_gh "$test_root/home/personal" auth switch --hostname github.com --user channprj
assert_eq channprj "$(cat -- "$test_root/active")" "manual account switch was blocked"

print -r -- chan-park_trueb >"$test_root/active"
GH_HOST=github.example.com run_gh "$test_root/home/personal" api user >/dev/null
run_gh "$test_root/home/personal" api user --hostname github.example.com >/dev/null
run_gh "$test_root/home/personal" api user --hostname=github.example.com >/dev/null
run_gh "$test_root/home/personal" auth status -h github.example.com >/dev/null
run_gh "$test_root/home/personal" help api >/dev/null
assert_eq chan-park_trueb "$(cat -- "$test_root/active")" "another host or help switched the account"
assert_eq unset "$(head -1 "$test_root/capture")" "another host or help received a GitHub token"

for failure in GH_TEST_SWITCH_FAIL GH_TEST_TOKEN_FAIL GH_TEST_EMPTY_TOKEN; do
  print -r -- chan-park_trueb >"$test_root/active"
  rm -f "$test_root/capture"
  export "$failure=1"
  if run_gh "$test_root/home/personal" api user >/dev/null 2>&1; then
    print -u2 -- "FAIL: $failure was ignored"
    exit 1
  fi
  [[ ! -e "$test_root/capture" ]] || { print -u2 'FAIL: command ran after authentication failed'; exit 1; }
  unset "$failure"
done

exit_code=0
GH_TEST_EXIT=17 run_gh "$test_root/home/personal" api user >/dev/null || exit_code=$?
assert_eq 17 "$exit_code" "command exit code was changed"

exit_code=0
missing_error="$(
  env HOME="$test_root/home" /bin/zsh -dfc '
    source "$1"
    path=("$2")
    gh api user
  ' -- "$repo_root/sh/.zshenv" "$test_root/empty" 2>&1
)" || exit_code=$?
assert_eq 127 "$exit_code" "missing GitHub CLI did not return command-not-found"
assert_eq 'gh: GitHub CLI is not installed or not in PATH' "$missing_error" "missing CLI error was unclear"

print 'PASS: gh selects accounts by directory, switches only when needed, and preserves command authentication'
