#!/bin/bash

set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Keep the agent socket below the Unix-domain socket path limit.
test_root=$(mktemp -d /tmp/dotfiles-sign.XXXXXX)
unset SSH_AGENT_PID SSH_AUTH_SOCK GIT_CONFIG_COUNT
trap 'if [[ -n "${SSH_AGENT_PID:-}" ]]; then ssh-agent -k >/dev/null; fi; rm -rf -- "$test_root"' EXIT

export HOME="$test_root"
export GIT_CONFIG_GLOBAL="$repo_root/git/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export SSH_ASKPASS="$test_root/askpass"
export SSH_ASKPASS_REQUIRE=force
export DISPLAY=:99

mkdir -p "$HOME/.ssh" "$HOME/.config/git"
ln -s "$repo_root/git/ssh-signing" "$HOME/.config/git/ssh-signing"
cat >"$SSH_ASKPASS" <<'EOF'
#!/bin/sh
echo "agent asked for confirmation" >>"$HOME/agent-requests"
exit 1
EOF
chmod +x "$SSH_ASKPASS"

key="$HOME/.ssh/id_ed25519-github"
ssh-keygen -q -t ed25519 -N '' -f "$key"
eval "$(ssh-agent -a "$test_root/agent.sock" -s)" >/dev/null
ssh-add -c "$key" >/dev/null 2>&1

git init -q "$test_root/repo"
cd "$test_root/repo"
git config user.email signing-test@example.com
printf 'signing-test@example.com %s\n' "$(<"$key.pub")" >"$HOME/.ssh/allowed_signers"

if ! git commit --allow-empty -m 'Signed with local key'; then
  if [[ -f "$HOME/agent-requests" ]]; then cat "$HOME/agent-requests" >&2; fi
  exit 1
fi
if [[ -e "$HOME/agent-requests" ]]; then
  cat "$HOME/agent-requests" >&2
  exit 1
fi
git verify-commit HEAD

ssh-add -d "$key.pub" >/dev/null 2>&1
ssh-add "$key" >/dev/null 2>&1
mv -- "$key" "$test_root/offline-key"
git commit --allow-empty -m 'Signed with agent key'
git verify-commit HEAD

printf '%s\n' 'PASS: Git signs with the local key and uses the agent when the local key is absent'
