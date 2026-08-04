#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MODE=${1:---all}

usage() {
  cat <<'EOF'
Usage: scripts/check-secrets.sh [--all|--current|--history]

Scans with fully redacted output. Install Gitleaks first:
  brew install gitleaks
EOF
}

if ! command -v gitleaks >/dev/null 2>&1; then
  printf '%s\n' 'error: gitleaks is required (brew install gitleaks)' >&2
  exit 127
fi

case "$MODE" in
  --all | --current | --history)
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

scan_current() {
  gitleaks dir \
    --no-banner \
    --no-color \
    --redact=100 \
    --config "$REPO_ROOT/.gitleaks.toml" \
    "$REPO_ROOT"
}

scan_history() {
  gitleaks git \
    --no-banner \
    --no-color \
    --redact=100 \
    --config "$REPO_ROOT/.gitleaks.toml" \
    --log-opts='--all --reflog' \
    "$REPO_ROOT"
}

if [[ "$MODE" == --all || "$MODE" == --current ]]; then
  scan_current
fi

if [[ "$MODE" == --all || "$MODE" == --history ]]; then
  scan_history
fi

printf '%s\n' 'Secret scan passed.'
