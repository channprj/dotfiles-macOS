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

assert_call_sequence() {
  local calls_file="$1"
  local expected="$2"
  local actual="$(<"$calls_file")"

  if [[ "$actual" != "$expected" ]]; then
    print -u2 "unexpected Herdr call sequence"
    print -u2 "expected:"
    print -r -- "$expected" | sed 's/^/  /' >&2
    print -u2 "actual:"
    print -r -- "$actual" | sed 's/^/  /' >&2
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

test_delete_stops_running_session_before_deleting() (
  local project_dir="$test_root/delete-running"
  local calls_file="$test_root/delete-running.calls"
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "session list --json")
        print '{"sessions":[{"name":"delete-running","running":true}]}'
        ;;
      "session stop delete-running" | "session delete delete-running")
        ;;
      *)
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  hsa delete --force >/dev/null

  assert_call_sequence "$calls_file" $'session list --json\nsession stop delete-running\nsession delete delete-running'
)

test_delete_skips_stop_for_stopped_session() (
  local project_dir="$test_root/delete-stopped"
  local calls_file="$test_root/delete-stopped.calls"
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "session list --json")
        print '{"sessions":[{"name":"delete-stopped","running":false}]}'
        ;;
      "session delete delete-stopped")
        ;;
      *)
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  hsa delete -f >/dev/null

  assert_call_sequence "$calls_file" $'session list --json\nsession delete delete-stopped'
)

test_delete_is_idempotent_for_missing_session() (
  local project_dir="$test_root/delete-missing"
  local calls_file="$test_root/delete-missing.calls"
  local output=""
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    [[ "$*" == "session list --json" ]] || return 1
    print '{"sessions":[]}'
  }

  cd "$project_dir"
  output="$(hsa delete --force)"

  [[ "$output" == *"does not exist"* ]] || {
    print -u2 "missing sessions should be reported as an idempotent success"
    exit 1
  }
  assert_call_sequence "$calls_file" 'session list --json'
)

test_delete_never_runs_after_stop_failure() (
  local project_dir="$test_root/delete-stop-failure"
  local calls_file="$test_root/delete-stop-failure.calls"
  local result=0
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "session list --json")
        print '{"sessions":[{"name":"delete-stop-failure","running":true}]}'
        ;;
      "session stop delete-stop-failure")
        return 9
        ;;
      *)
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  if hsa delete --force >/dev/null 2>&1; then
    print -u2 "stop failure should make hsa delete fail"
    exit 1
  else
    result=$?
  fi

  (( result != 0 )) || exit 1
  assert_called "$calls_file" "session stop delete-stop-failure"
  assert_not_called "$calls_file" "session delete delete-stop-failure"
)

test_delete_reports_delete_failure() (
  local project_dir="$test_root/delete-failure"
  local calls_file="$test_root/delete-failure.calls"
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    case "$*" in
      "session list --json")
        print '{"sessions":[{"name":"delete-failure","running":false}]}'
        ;;
      "session delete delete-failure")
        return 8
        ;;
      *)
        return 1
        ;;
    esac
  }

  cd "$project_dir"
  if hsa delete --force >/dev/null 2>&1; then
    print -u2 "delete failure should make hsa delete fail"
    exit 1
  fi

  assert_called "$calls_file" "session delete delete-failure"
)

test_delete_rejects_unknown_options_before_listing() (
  local project_dir="$test_root/delete-options"
  local calls_file="$test_root/delete-options.calls"
  local result=0
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    return 1
  }

  cd "$project_dir"
  if hsa delete --unsafe >/dev/null 2>&1; then
    print -u2 "unknown delete options should fail"
    exit 1
  else
    result=$?
  fi

  (( result == 2 )) || {
    print -u2 "unknown delete options should return 2, got $result"
    exit 1
  }
  [[ ! -s "$calls_file" ]] || {
    print -u2 "unknown options should not call Herdr"
    exit 1
  }
)

test_delete_requires_force_without_a_terminal() (
  local project_dir="$test_root/delete-noninteractive"
  local calls_file="$test_root/delete-noninteractive.calls"
  local error_file="$test_root/delete-noninteractive.err"
  local result=0
  mkdir -p "$project_dir"
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    [[ "$*" == "session list --json" ]] || return 1
    print '{"sessions":[{"name":"delete-noninteractive","running":false}]}'
  }

  cd "$project_dir"
  if hsa delete </dev/null >/dev/null 2>"$error_file"; then
    print -u2 "non-interactive deletion should require --force"
    exit 1
  else
    result=$?
  fi

  (( result == 1 )) || exit 1
  grep -Fq -- "use --force" "$error_file" || {
    print -u2 "non-interactive error should explain --force"
    exit 1
  }
  assert_not_called "$calls_file" "session delete delete-noninteractive"
)

test_delete_uses_root_session_name_at_filesystem_root() (
  local calls_file="$test_root/delete-root.calls"
  local output=""
  : >"$calls_file"

  herdr() {
    print -r -- "$*" >>"$calls_file"
    [[ "$*" == "session list --json" ]] || return 1
    print '{"sessions":[]}'
  }

  cd /
  output="$(hsa delete --force)"

  [[ "$output" == *"session 'root'"* ]] || {
    print -u2 "filesystem root should map to the root session"
    exit 1
  }
)

test_reconciles_stale_session_to_invoking_directory
test_reuses_matching_workspace_without_duplication
test_bootstraps_stopped_session_before_reconciling
test_delete_stops_running_session_before_deleting
test_delete_skips_stop_for_stopped_session
test_delete_is_idempotent_for_missing_session
test_delete_never_runs_after_stop_failure
test_delete_reports_delete_failure
test_delete_rejects_unknown_options_before_listing
test_delete_requires_force_without_a_terminal
test_delete_uses_root_session_name_at_filesystem_root

print "PASS: hsa attaches safely and deletes sessions with guarded state transitions"
