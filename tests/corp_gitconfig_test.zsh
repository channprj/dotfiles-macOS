#!/bin/zsh

emulate -L zsh
setopt errexit nounset pipefail

repo_root="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-corp-git.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home/workspace/corp/project/nested" \
  "$test_root/home/workspace/corporate" "$test_root/home/personal"
ln -s "$test_root/home/workspace/corp/project" "$test_root/home/corp-link"
cat >"$test_root/home/.gitconfig" <<'EOF'
[user]
	email = personal@example.com
	name = Personal
EOF
cat >"$test_root/home/.gitconfig-corp" <<'EOF'
[user]
	email = corp@example.com
	name = Corp
[credential "https://github.com"]
	username = corp-user
[tag]
	forceSignAnnotated = false
EOF

run_git() {
  local directory="$1"
  shift
  env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 \
    HOME="$test_root/home" GIT_CONFIG_NOSYSTEM=1 \
    /bin/zsh -dfc '
      source "$1"
      cd -- "$2"
      shift 2
      git "$@"
    ' -- "$repo_root/sh/.zshenv" "$directory" "$@"
}

assert_eq() {
  [[ "$1" == "$2" ]] || {
    print -u2 -- "FAIL: $3 (expected '$1', got '$2')"
    exit 1
  }
}

for directory in personal workspace/corporate workspace/corp workspace/corp/project/nested corp-link; do
  case "$directory" in
    workspace/corp | workspace/corp/* | corp-link) expected_email=corp@example.com ;;
    *) expected_email=personal@example.com ;;
  esac
  assert_eq "$expected_email" \
    "$(run_git "$test_root/home/$directory" config --get user.email)" \
    "user.email in $directory"
done

assert_eq Corp \
  "$(run_git "$test_root/home/workspace/corp" config --get user.name)" \
  "corp name was not applied"
assert_eq corp-user \
  "$(run_git "$test_root/home/workspace/corp" config --get credential.https://github.com.username)" \
  "corp credential username was not applied"
assert_eq false \
  "$(run_git "$test_root/home/workspace/corp" config --get tag.forceSignAnnotated)" \
  "corp tag signing flag was not applied"
assert_eq personal@example.com \
  "$(run_git "$test_root/home/personal" config --get user.email)" \
  "personal directory used the corp email"
assert_eq personal@example.com \
  "$(run_git "$test_root/home/workspace/corp" -C "$test_root/home/personal" config --get user.email)" \
  "git -C out of the corporate workspace kept the corp email"
assert_eq corp@example.com \
  "$(run_git "$test_root/home/personal" -C "$test_root/home/workspace/corp" config --get user.email)" \
  "git -C into the corporate workspace missed the corp email"
assert_eq corp@example.com \
  "$(run_git "$test_root/home/personal" -C "$test_root/home/personal" -C "../workspace/corp" config --get user.email)" \
  "a later relative -C did not select the corporate workspace"

explicit="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.marker GIT_CONFIG_VALUE_0=kept \
  env HOME="$test_root/home" GIT_CONFIG_NOSYSTEM=1 \
  /bin/zsh -dfc '
    source "$1"
    cd -- "$2"
    git config --get user.marker
    git -c user.email=explicit@example.com config --get user.email
  ' -- "$repo_root/sh/.zshenv" "$test_root/home/workspace/corp")"
assert_eq $'kept\nexplicit@example.com' "$explicit" \
  "existing Git config environment or -c was replaced"

print "PASS: corporate workspace git commands use .gitconfig-corp"
