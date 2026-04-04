#!/usr/bin/env bash
# Test suite for mock-sbx CLI emulator
# Usage: bash tools/mock-sbx-tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

PASS=0 FAIL=0 TOTAL=0
FAILURES=()

# --- Test Framework ---

reset_state() {
  export SBX_MOCK_STATE_DIR="$(mktemp -d)"
}

cleanup_state() {
  rm -rf "$SBX_MOCK_STATE_DIR"
}

run_test() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  reset_state
  if "$@" 2>/dev/null; then
    PASS=$((PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$name")
    printf '  \033[31m✗\033[0m %s\n' "$name"
  fi
  cleanup_state
}

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-}"
  if [[ "$actual" != "$expected" ]]; then
    echo "  ASSERT_EQ FAILED${msg:+: $msg}" >&2
    echo "    expected: $expected" >&2
    echo "    actual:   $actual" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT_CONTAINS FAILED${msg:+: $msg}" >&2
    echo "    needle:   $needle" >&2
    echo "    haystack: $haystack" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ASSERT_NOT_CONTAINS FAILED${msg:+: $msg}" >&2
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  local actual
  set +e
  "$@" >/dev/null 2>/dev/null
  actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    echo "  ASSERT_EXIT_CODE FAILED: expected $expected, got $actual" >&2
    return 1
  fi
}

# --- Lifecycle Tests ---

test_version() {
  local out
  out="$(sbx version)"
  assert_contains "$out" "mock-sbx"
}

test_help() {
  local out
  out="$(sbx help)"
  assert_contains "$out" "Available Commands"
}

test_ls_empty() {
  local out
  out="$(sbx ls --json)"
  assert_eq "$out" '{"sandboxes":[]}'
}

test_run_creates_sandbox() {
  sbx run claude /tmp/test-proj --name test-create < /dev/null
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"name":"test-create"'
  assert_contains "$out" '"status":"running"'
  assert_contains "$out" '"agent":"claude"'
}

test_run_default_name() {
  sbx run claude /tmp/my-project < /dev/null
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"name":"claude-my-project"'
}

test_run_custom_name() {
  sbx run claude /tmp/proj --name custom-name < /dev/null
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"name":"custom-name"'
}

test_run_workspace_in_json() {
  sbx run claude /tmp/my-workspace --name ws-test < /dev/null
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"/tmp/my-workspace"'
}

test_stop_updates_status() {
  sbx run claude /tmp/proj --name stop-test < /dev/null
  sbx stop stop-test
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"status":"stopped"'
}

test_stop_clears_ports() {
  sbx run claude /tmp/proj --name port-stop < /dev/null
  sbx ports port-stop --publish 8080:3000
  sbx stop port-stop
  local out
  out="$(sbx ports port-stop --json)"
  assert_eq "$out" "[]"
}

test_stop_not_found() {
  local stderr
  set +e
  stderr="$(sbx stop nonexistent 2>&1 1>/dev/null)"
  local exit_code=$?
  set -e
  assert_eq "$exit_code" "1"
  assert_contains "$stderr" "not found"
}

test_rm_removes_sandbox() {
  sbx run claude /tmp/proj --name rm-test < /dev/null
  sbx rm -f rm-test
  local out
  out="$(sbx ls --json)"
  assert_eq "$out" '{"sandboxes":[]}'
}

test_rm_not_found() {
  local stderr
  set +e
  stderr="$(sbx rm -f ghost 2>&1 1>/dev/null)"
  local exit_code=$?
  set -e
  assert_eq "$exit_code" "1"
  assert_contains "$stderr" "not found"
}

test_rm_output_message() {
  sbx run claude /tmp/proj --name msg-test < /dev/null
  local out
  out="$(sbx rm -f msg-test)"
  assert_contains "$out" "removed"
}

test_resume_stopped() {
  sbx run claude /tmp/proj --name resume-test < /dev/null
  sbx stop resume-test
  sbx run resume-test < /dev/null
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"status":"running"'
}

# --- Policy Tests ---

test_policy_defaults_seeded() {
  local out
  out="$(sbx policy ls)"
  assert_contains "$out" "api.anthropic.com"
  assert_contains "$out" "github.com"
  assert_contains "$out" "*.npmjs.org"
}

test_policy_ls_format() {
  local out
  out="$(sbx policy ls)"
  assert_contains "$out" "NAME"
  assert_contains "$out" "TYPE"
  assert_contains "$out" "DECISION"
  assert_contains "$out" "RESOURCES"
}

test_policy_allow() {
  sbx policy allow network "test.example.com"
  local out
  out="$(sbx policy ls)"
  assert_contains "$out" "test.example.com"
  assert_contains "$out" "allow"
}

test_policy_deny() {
  sbx policy deny network "evil.test.com"
  local out
  out="$(sbx policy ls)"
  assert_contains "$out" "evil.test.com"
  assert_contains "$out" "deny"
}

test_policy_rm() {
  sbx policy allow network "remove-me.com"
  sbx policy rm network --resource "remove-me.com"
  local out
  out="$(sbx policy ls)"
  assert_not_contains "$out" "remove-me.com"
}

test_policy_log_json() {
  local out
  out="$(sbx policy log --json)"
  assert_contains "$out" '"blocked_hosts"'
  assert_contains "$out" '"allowed_hosts"'
  assert_contains "$out" '"vm_name"'
}

test_policy_log_no_entries() {
  # Trigger initialization first, then overwrite log with empty entries
  sbx version > /dev/null
  echo '{"blocked_hosts":[],"allowed_hosts":[]}' > "$SBX_MOCK_STATE_DIR/policy-log/entries.json"
  local out
  out="$(sbx policy log --json)"
  assert_contains "$out" '"blocked_hosts":[]'
  assert_contains "$out" '"allowed_hosts":[]'
}

# --- Port Tests ---

test_ports_empty() {
  sbx run claude /tmp/proj --name port-empty < /dev/null
  local out
  out="$(sbx ports port-empty --json)"
  assert_eq "$out" "[]"
}

test_ports_publish() {
  sbx run claude /tmp/proj --name port-pub < /dev/null
  local msg
  msg="$(sbx ports port-pub --publish 8080:3000)"
  assert_contains "$msg" "Published"
  local out
  out="$(sbx ports port-pub --json)"
  assert_contains "$out" '"host_port":8080'
  assert_contains "$out" '"sandbox_port":3000'
}

test_ports_unpublish() {
  sbx run claude /tmp/proj --name port-unpub < /dev/null
  sbx ports port-unpub --publish 8080:3000
  sbx ports port-unpub --unpublish 8080:3000
  local out
  out="$(sbx ports port-unpub --json)"
  assert_eq "$out" "[]"
}

test_ports_duplicate_error() {
  sbx run claude /tmp/proj --name port-dup < /dev/null
  sbx ports port-dup --publish 8080:3000
  local stderr
  set +e
  stderr="$(sbx ports port-dup --publish 8080:4000 2>&1 1>/dev/null)"
  local exit_code=$?
  set -e
  assert_eq "$exit_code" "1"
  assert_contains "$stderr" "already published"
  assert_contains "$stderr" "8080"
}

test_ports_multiple() {
  sbx run claude /tmp/proj --name port-multi < /dev/null
  sbx ports port-multi --publish 8080:3000
  sbx ports port-multi --publish 9090:4000
  local out
  out="$(sbx ports port-multi --json)"
  assert_contains "$out" '"host_port":8080'
  assert_contains "$out" '"host_port":9090'
}

# --- Error Format Tests ---

test_error_not_found_format() {
  local stderr
  set +e
  stderr="$(sbx stop my-sandbox 2>&1 1>/dev/null)"
  set -e
  # Must match: Error: sandbox 'my-sandbox' not found
  assert_contains "$stderr" "Error: sandbox 'my-sandbox' not found"
}

test_error_port_conflict_format() {
  sbx run claude /tmp/proj --name conflict-test < /dev/null
  sbx ports conflict-test --publish 8080:3000
  local stderr
  set +e
  stderr="$(sbx ports conflict-test --publish 8080:5000 2>&1 1>/dev/null)"
  set -e
  # Must match: ERROR: publish port: port 127.0.0.1:8080/tcp is already published
  assert_contains "$stderr" "ERROR: publish port: port 127.0.0.1:8080/tcp is already published"
}

test_unknown_command() {
  assert_exit_code 1 sbx foobar
}

# --- Interactive Mode Tests ---

test_interactive_attach_no_crash() {
  # Verify attach path works without crash (interactive banner only shows with TTY)
  sbx run claude /tmp/proj --name attach-test < /dev/null
  sbx run attach-test < /dev/null  # attach with no TTY should exit cleanly
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"name":"attach-test"'
  assert_contains "$out" '"status":"running"'
}

# --- State Tests ---

test_state_persistence() {
  sbx run claude /tmp/proj --name persist-test < /dev/null
  # Second invocation finds the sandbox
  local out
  out="$(sbx ls --json)"
  assert_contains "$out" '"name":"persist-test"'
}

test_state_isolation() {
  sbx run claude /tmp/proj --name iso-test < /dev/null
  local dir1="$SBX_MOCK_STATE_DIR"
  export SBX_MOCK_STATE_DIR="$(mktemp -d)"
  local out
  out="$(sbx ls --json)"
  assert_eq "$out" '{"sandboxes":[]}'
  rm -rf "$SBX_MOCK_STATE_DIR"
  export SBX_MOCK_STATE_DIR="$dir1"
}

# --- Run All Tests ---

echo ""
echo "mock-sbx test suite"
echo "==================="
echo ""

echo "Lifecycle:"
run_test "version"                    test_version
run_test "help"                       test_help
run_test "ls empty"                   test_ls_empty
run_test "run creates sandbox"        test_run_creates_sandbox
run_test "run default name"           test_run_default_name
run_test "run custom name"            test_run_custom_name
run_test "run workspace in json"      test_run_workspace_in_json
run_test "stop updates status"        test_stop_updates_status
run_test "stop clears ports"          test_stop_clears_ports
run_test "stop not found"             test_stop_not_found
run_test "rm removes sandbox"         test_rm_removes_sandbox
run_test "rm not found"               test_rm_not_found
run_test "rm output message"          test_rm_output_message
run_test "resume stopped"             test_resume_stopped

echo ""
echo "Policies:"
run_test "defaults seeded"            test_policy_defaults_seeded
run_test "ls format"                  test_policy_ls_format
run_test "allow"                      test_policy_allow
run_test "deny"                       test_policy_deny
run_test "rm"                         test_policy_rm
run_test "log json"                   test_policy_log_json
run_test "log no entries"             test_policy_log_no_entries

echo ""
echo "Ports:"
run_test "empty"                      test_ports_empty
run_test "publish"                    test_ports_publish
run_test "unpublish"                  test_ports_unpublish
run_test "duplicate error"            test_ports_duplicate_error
run_test "multiple"                   test_ports_multiple

echo ""
echo "Error Formats:"
run_test "not found format"           test_error_not_found_format
run_test "port conflict format"       test_error_port_conflict_format
run_test "unknown command"            test_unknown_command

echo ""
echo "Interactive:"
run_test "attach no crash"            test_interactive_attach_no_crash

echo ""
echo "State:"
run_test "persistence"                test_state_persistence
run_test "isolation"                  test_state_isolation

echo ""
echo "==================="
printf '%d tests: \033[32m%d passed\033[0m' "$TOTAL" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf ', \033[31m%d failed\033[0m' "$FAIL"
  echo ""
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
else
  echo ""
fi
echo ""
