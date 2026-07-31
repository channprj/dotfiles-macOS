#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipefail

readonly repo_root="${0:A:h:h}"
typeset test_root
test_root="$(mktemp -d /tmp/hsa-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

source "$repo_root/sh/.zshfunc"

if (( ! $+functions[hsa] )); then
  print -u2 "hsa is not defined as a function"
  exit 1
fi

assert_called() {
  local calls_file="$1"
  local expected="$2"

  if ! grep -Fqx -- "$expected" "$calls_file"; then
    print -u2 "missing Herdr call: $expected"
    print -u2 "actual calls:"
    sed 's/^/  /' "$calls_file" >&2
    exit 1
  fi
}

assert_not_called() {
  local calls_file="$1"
  local unexpected="$2"

  if grep -Fqx -- "$unexpected" "$calls_file"; then
    print -u2 "unexpected Herdr call: $unexpected"
    print -u2 "actual calls:"
    sed 's/^/  /' "$calls_file" >&2
    exit 1
  fi
}

test_reconciles_stale_session_to_invoking_directory() (
  local project_dir="$test_root/project"
  local calls_file="$test_root/stale.calls"
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "--session project status server")
        print "status: running"
        ;;
      "--session project api snapshot")
        print '{"result":{"snapshot":{"panes":[{"cwd":"/Users/example","workspace_id":"w1"}]}}}'
        ;;
      "--session project workspace create --cwd $project_dir --focus")
        print '{"result":{"type":"workspace_created","workspace":{"workspace_id":"w2"}}}'
        ;;
      "session attach project")
        ;;
      *)
        print -u2 "unexpected Herdr invocation: $*"
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  hsa

  assert_called "$calls_file" "--session project workspace create --cwd $project_dir --focus"
  assert_called "$calls_file" "session attach project"
)

test_reuses_matching_workspace_without_duplication() (
  local project_dir="$test_root/reuse"
  local calls_file="$test_root/reuse.calls"
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "--session reuse status server")
        print "status: running"
        ;;
      "--session reuse api snapshot")
        print -r -- \
          "{\"result\":{\"snapshot\":{\"panes\":[{\"cwd\":\"${project_dir:A}\",\"workspace_id\":\"w7\"}]}}}"
        ;;
      "--session reuse workspace focus w7")
        print '{"result":{"type":"workspace_focused"}}'
        ;;
      "session attach reuse")
        ;;
      *)
        print -u2 "unexpected Herdr invocation: $*"
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  hsa

  assert_called "$calls_file" "--session reuse workspace focus w7"
  assert_not_called "$calls_file" "--session reuse workspace create --cwd $project_dir --focus"
  assert_called "$calls_file" "session attach reuse"
)

test_bootstraps_stopped_session_before_reconciling() (
  local project_dir="$test_root/cold"
  local calls_file="$test_root/cold.calls"
  local running_marker="$test_root/cold.running"
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "--session cold status server")
        if [[ -e "$running_marker" ]]; then
          print "status: running"
        else
          print "status: not running"
        fi
        ;;
      "session attach cold")
        : >"$running_marker"
        ;;
      "--session cold api snapshot")
        print '{"result":{"snapshot":{"panes":[{"cwd":"/Users/example","workspace_id":"w1"}]}}}'
        ;;
      "--session cold workspace create --cwd $project_dir --focus")
        print '{"result":{"type":"workspace_created","workspace":{"workspace_id":"w2"}}}'
        ;;
      *)
        print -u2 "unexpected Herdr invocation: $*"
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  hsa

  assert_called "$calls_file" "--session cold workspace create --cwd $project_dir --focus"
  if (( $(grep -Fxc -- "session attach cold" "$calls_file") != 2 )); then
    print -u2 "stopped session should be bootstrapped once and attached once"
    sed 's/^/  /' "$calls_file" >&2
    exit 1
  fi
)

test_reconciles_stale_session_to_invoking_directory
test_reuses_matching_workspace_without_duplication
test_bootstraps_stopped_session_before_reconciling

print "PASS: hsa always focuses a workspace rooted at the invoking directory"
