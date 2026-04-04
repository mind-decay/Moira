#!/usr/bin/env bash
# test-helpers.sh — Shared test utilities for Tier 1 structural verifier
# Sourced by test-*.sh files. Not executed directly.

PASSES=0
FAILURES=0
TEST_NAME=""

pass() {
  echo "  [PASS] $1"
  PASSES=$((PASSES + 1))
}

fail() {
  echo "  [FAIL] $1"
  FAILURES=$((FAILURES + 1))
}

assert_dir_exists() {
  if [[ -d "$1" ]]; then
    pass "$2"
  else
    fail "$2: directory not found: $1"
  fi
}

assert_file_exists() {
  if [[ -f "$1" ]]; then
    pass "$2"
  else
    fail "$2: file not found: $1"
  fi
}

assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    pass "$3"
  else
    fail "$3: '$2' not found in $1"
  fi
}

assert_equals() {
  if [[ "$1" == "$2" ]]; then
    pass "$3"
  else
    fail "$3: expected '$2', got '$1'"
  fi
}

assert_not_empty() {
  if [[ -n "$1" ]]; then
    pass "$2"
  else
    fail "$2: value is empty"
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg: expected exit code $expected, got $actual"
  fi
}

assert_file_not_exists() {
  if [[ ! -f "$1" ]]; then
    pass "$2"
  else
    fail "$2: file should not exist: $1"
  fi
}

assert_dir_not_exists() {
  if [[ ! -d "$1" ]]; then
    pass "$2"
  else
    fail "$2: directory should not exist: $1"
  fi
}

test_summary() {
  local total=$((PASSES + FAILURES))
  echo ""
  echo "  $PASSES/$total passed, $FAILURES failed"
  if [[ $FAILURES -gt 0 ]]; then
    return 1
  fi
  return 0
}
