#!/usr/bin/env bash
# test-fn-retry.sh — Functional tests for retry.sh
# Tests retry decisions, cost estimation, outcome recording, lookup table.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: retry.sh (functional)"

source "$SRC_LIB_DIR/retry.sh"
set +e

# ── Default lookup table ─────────────────────────────────────────────

run_fn moira_retry_lookup_table "$TEMP_DIR/no-state"
assert_exit_zero "lookup_table: no state → exit 0"
# Error types use E5_QUALITY, E6_AGENT format
if [[ -n "$FN_STDOUT" ]]; then
  pass "lookup_table: returns non-empty table"
else
  fail "lookup_table: expected non-empty output"
fi

# ── moira_retry_should_retry: standard case ──────────────────────────

run_fn moira_retry_should_retry "E5_QUALITY" "reviewer" "$TEMP_DIR/no-state"
assert_exit_zero "should_retry: E5_QUALITY → exit 0"
assert_output_contains "$FN_STDOUT" "decision:" "should_retry: includes decision"

# ── moira_retry_should_retry: budget_exceeded → escalate ─────────────

# E4_BUDGET has hard_limit=1 (wildcard default), but low default probability
run_fn moira_retry_should_retry "E4_BUDGET" "explorer" "$TEMP_DIR/no-state"
assert_output_contains "$FN_STDOUT" "decision:" "should_retry: E4_BUDGET → has decision"

# ── moira_retry_expected_cost: produces cost comparison ──────────────

run_fn moira_retry_expected_cost "E5_QUALITY" "reviewer" "1" "$TEMP_DIR/no-state"
assert_exit_zero "expected_cost: exit 0"
assert_output_contains "$FN_STDOUT" "recommendation:" "expected_cost: includes recommendation"

# ── moira_retry_record_outcome: creates stats file ───────────────────

rec_state="$TEMP_DIR/retry-rec"
mkdir -p "$rec_state"
moira_retry_record_outcome "E5_QUALITY" "reviewer" "1" "success" "$rec_state"
assert_file_exists "$rec_state/retry-stats.yaml" "record_outcome: creates retry-stats.yaml"

# ── moira_retry_record_outcome: updates on second call ───────────────

moira_retry_record_outcome "E5_QUALITY" "reviewer" "2" "failure" "$rec_state"
assert_file_contains "$rec_state/retry-stats.yaml" "E5_QUALITY" "record_outcome: records error type"
assert_file_contains "$rec_state/retry-stats.yaml" "reviewer" "record_outcome: records agent type"

# ── Hard limits respected ────────────────────────────────────────────

run_fn moira_retry_expected_cost "E5_QUALITY" "reviewer" "5" "$TEMP_DIR/no-state"
assert_output_contains "$FN_STDOUT" "recommendation:" "expected_cost: high attempt → has recommendation"

test_summary
