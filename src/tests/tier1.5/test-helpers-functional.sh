#!/usr/bin/env bash
# test-helpers-functional.sh — Extended test utilities for Tier 1.5 functional tests
# Sources tier1/test-helpers.sh and adds functional-specific assertions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tier1/test-helpers.sh"

# ── Source path resolution ───────────────────────────────────────────
# Functional tests ALWAYS source from src/global/lib (source tree),
# never from $MOIRA_HOME/lib (installed copy).
SRC_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SRC_LIB_DIR="$SRC_DIR/src/global/lib"
export MOIRA_SCHEMA_DIR="$SRC_DIR/src/schemas"

# ── Temp directory setup ─────────────────────────────────────────────
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Fake MOIRA_HOME pointing to temp — isolates tests from installed copy
export MOIRA_HOME="$TEMP_DIR/moira-home"
mkdir -p "$MOIRA_HOME"

# ── run_fn <function_name> [args...] ─────────────────────────────────
# Captures stdout → $FN_STDOUT, stderr → $FN_STDERR, exit code → $FN_EXIT
# Eliminates repetitive set +e / output=$() / code=$? / set -e boilerplate.
FN_STDOUT=""
FN_STDERR=""
FN_EXIT=0
run_fn() {
  local fn_name="$1"
  shift
  local _stdout_file _stderr_file
  _stdout_file=$(mktemp)
  _stderr_file=$(mktemp)
  set +e
  "$fn_name" "$@" >"$_stdout_file" 2>"$_stderr_file"
  FN_EXIT=$?
  set -e
  FN_STDOUT=$(cat "$_stdout_file")
  FN_STDERR=$(cat "$_stderr_file")
  rm -f "$_stdout_file" "$_stderr_file"
}

# ── Additional assertions ────────────────────────────────────────────

assert_exit_nonzero() {
  local msg="$1"
  if [[ $FN_EXIT -ne 0 ]]; then
    pass "$msg"
  else
    fail "$msg: expected non-zero exit, got 0"
  fi
}

assert_exit_zero() {
  local msg="$1"
  if [[ $FN_EXIT -eq 0 ]]; then
    pass "$msg"
  else
    fail "$msg: expected exit 0, got $FN_EXIT"
  fi
}

assert_output_contains() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    pass "$msg"
  else
    fail "$msg: '$expected' not found in output"
  fi
}

assert_output_not_contains() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" != *"$expected"* ]]; then
    pass "$msg"
  else
    fail "$msg: '$expected' should not be in output"
  fi
}

assert_output_equals() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg: expected '$expected', got '$actual'"
  fi
}

assert_output_empty() {
  local actual="$1"
  local msg="$2"
  if [[ -z "$actual" ]]; then
    pass "$msg"
  else
    fail "$msg: expected empty output, got '$actual'"
  fi
}

assert_yaml_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local msg="$4"
  local actual
  actual=$(moira_yaml_get "$file" "$key" 2>/dev/null) || actual=""
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg: yaml[$key] expected '$expected', got '$actual'"
  fi
}

assert_numeric_range() {
  local value="$1"
  local min="$2"
  local max="$3"
  local msg="$4"
  if [[ "$value" -ge "$min" && "$value" -le "$max" ]]; then
    pass "$msg"
  else
    fail "$msg: $value not in range [$min, $max]"
  fi
}

assert_file_line_count() {
  local file="$1"
  local expected="$2"
  local msg="$3"
  local actual
  actual=$(wc -l < "$file" | tr -d ' ')
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg: expected $expected lines, got $actual"
  fi
}
