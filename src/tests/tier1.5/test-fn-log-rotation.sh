#!/usr/bin/env bash
# test-fn-log-rotation.sh — Functional tests for log-rotation.sh
# Tests rotation thresholds and archive behavior.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: log-rotation.sh (functional)"

source "$SRC_LIB_DIR/log-rotation.sh"
set +e

# ── moira_rotate_logs: no logs → no-op ──────────────────────────────

empty_state="$TEMP_DIR/empty-logs"
mkdir -p "$empty_state"
run_fn moira_rotate_logs "$empty_state"
assert_exit_zero "rotate_logs: no logs → exit 0"

# ── moira_rotate_logs: small logs → no rotation ─────────────────────

small_state="$TEMP_DIR/small-logs"
mkdir -p "$small_state"
for i in $(seq 1 100); do echo "line $i" >> "$small_state/violations.log"; done

moira_rotate_logs "$small_state"
if [[ ! -f "$small_state/violations.log.1" ]]; then
  pass "rotate_logs: small log → no archive"
else
  fail "rotate_logs: should not archive small log"
fi

# ── moira_rotate_logs: large log → rotated ───────────────────────────

large_state="$TEMP_DIR/large-logs"
mkdir -p "$large_state"
# Default threshold is 5000; rotation moves file to archive/
for i in $(seq 1 6000); do echo "violation line $i" >> "$large_state/violations.log"; done

moira_rotate_logs "$large_state"
# The file gets moved to archive/ with timestamp, then a new empty file is created
if [[ -d "$large_state/archive" ]] || [[ ! -s "$large_state/violations.log" ]] || \
   ls "$large_state"/violations.log.* 2>/dev/null | head -1 | grep -q .; then
  pass "rotate_logs: large log → rotated"
else
  # Check if file was simply truncated in place
  lines=$(wc -l < "$large_state/violations.log" 2>/dev/null | tr -d ' ')
  if [[ "$lines" -lt 6000 ]]; then
    pass "rotate_logs: large log → truncated"
  else
    fail "rotate_logs: log should be rotated or truncated"
  fi
fi

test_summary
