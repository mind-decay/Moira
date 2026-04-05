#!/usr/bin/env bash
# test-fn-budget.sh — Functional tests for budget.sh
# Tests token estimation, overflow detection, agent budget lookup, recording.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: budget.sh (functional)"

# Source the library under test
source "$SRC_LIB_DIR/budget.sh"
set +e

# ── _moira_budget_get_agent_budget: hardcoded defaults ───────────────

run_fn _moira_budget_get_agent_budget "classifier" ""
assert_output_equals "$FN_STDOUT" "20000" "get_agent_budget: classifier default 20000"

run_fn _moira_budget_get_agent_budget "explorer" ""
assert_output_equals "$FN_STDOUT" "140000" "get_agent_budget: explorer default 140000"

run_fn _moira_budget_get_agent_budget "implementer" ""
assert_output_equals "$FN_STDOUT" "120000" "get_agent_budget: implementer default 120000"

# ── _moira_budget_get_agent_budget: from budgets.yaml ────────────────

mkdir -p "$TEMP_DIR/budget-config"
cat > "$TEMP_DIR/budget-config/budgets.yaml" << 'EOF'
agent_budgets:
  classifier: 30000
  explorer: 200000
max_load_percent: 80
EOF

run_fn _moira_budget_get_agent_budget "classifier" "$TEMP_DIR/budget-config"
assert_output_equals "$FN_STDOUT" "30000" "get_agent_budget: reads from budgets.yaml"

run_fn _moira_budget_get_agent_budget "explorer" "$TEMP_DIR/budget-config"
assert_output_equals "$FN_STDOUT" "200000" "get_agent_budget: reads explorer from budgets.yaml"

# Unknown role falls back to hardcoded 0
run_fn _moira_budget_get_agent_budget "unknown_role" "$TEMP_DIR/budget-config"
assert_output_equals "$FN_STDOUT" "0" "get_agent_budget: unknown role → 0"

# ── _moira_budget_get_max_load: default ──────────────────────────────

run_fn _moira_budget_get_max_load ""
assert_output_equals "$FN_STDOUT" "70" "get_max_load: default 70"

# ── _moira_budget_get_max_load: from config ──────────────────────────

run_fn _moira_budget_get_max_load "$TEMP_DIR/budget-config"
assert_output_equals "$FN_STDOUT" "80" "get_max_load: reads from budgets.yaml"

# ── moira_budget_estimate_tokens: file size / 4 ─────────────────────

# Create a file of known size (400 bytes)
dd if=/dev/zero bs=1 count=400 of="$TEMP_DIR/testfile.txt" 2>/dev/null
run_fn moira_budget_estimate_tokens "$TEMP_DIR/testfile.txt"
assert_output_equals "$FN_STDOUT" "100" "estimate_tokens: 400 bytes → 100 tokens"

# Larger file
dd if=/dev/zero bs=1 count=4000 of="$TEMP_DIR/bigfile.txt" 2>/dev/null
run_fn moira_budget_estimate_tokens "$TEMP_DIR/bigfile.txt"
assert_output_equals "$FN_STDOUT" "1000" "estimate_tokens: 4000 bytes → 1000 tokens"

# ── moira_budget_estimate_tokens: missing file → 0 ──────────────────

run_fn moira_budget_estimate_tokens "$TEMP_DIR/nonexistent.txt"
assert_output_equals "$FN_STDOUT" "0" "estimate_tokens: missing file → 0"

# ── moira_budget_estimate_batch: multiple files ──────────────────────

dd if=/dev/zero bs=1 count=100 of="$TEMP_DIR/file1.txt" 2>/dev/null
dd if=/dev/zero bs=1 count=200 of="$TEMP_DIR/file2.txt" 2>/dev/null

file_list="$TEMP_DIR/file1.txt
$TEMP_DIR/file2.txt"

run_fn moira_budget_estimate_batch "$file_list"
assert_output_equals "$FN_STDOUT" "75" "estimate_batch: 100+200 bytes → 75 tokens"

# ── moira_budget_estimate_batch: empty list → 0 ─────────────────────

run_fn moira_budget_estimate_batch ""
assert_output_equals "$FN_STDOUT" "0" "estimate_batch: empty list → 0"

# ── moira_budget_check_overflow: ok ──────────────────────────────────

# classifier budget = 20000, max_load = 70% → max_allowed = 14000, warn = 10000
run_fn moira_budget_check_overflow "classifier" "5000" ""
assert_exit_zero "check_overflow: 5000 < 10000 → ok"
assert_output_equals "$FN_STDOUT" "ok" "check_overflow: outputs ok"

# ── moira_budget_check_overflow: warning ─────────────────────────────

# 11000 > 50% of 20000 (10000) but < 70% (14000)
run_fn moira_budget_check_overflow "classifier" "11000" ""
assert_exit_zero "check_overflow: warning → exit 0"
assert_output_equals "$FN_STDOUT" "warning" "check_overflow: 11000 → warning"

# ── moira_budget_check_overflow: exceeded ────────────────────────────

# 15000 > 70% of 20000 (14000)
run_fn moira_budget_check_overflow "classifier" "15000" ""
assert_exit_nonzero "check_overflow: exceeded → exit 1"
assert_output_equals "$FN_STDOUT" "exceeded" "check_overflow: 15000 → exceeded"

# ── moira_budget_check_overflow: with custom max_load ────────────────

# budget-config has max_load=80, classifier=30000 → max_allowed=24000, warn=15000
run_fn moira_budget_check_overflow "classifier" "20000" "$TEMP_DIR/budget-config"
assert_output_equals "$FN_STDOUT" "warning" "check_overflow: custom config → warning"

run_fn moira_budget_check_overflow "classifier" "25000" "$TEMP_DIR/budget-config"
assert_output_equals "$FN_STDOUT" "exceeded" "check_overflow: custom config → exceeded"

# ── moira_budget_record_agent: writes to status.yaml ─────────────────

rec_dir="$TEMP_DIR/budget-rec"
mkdir -p "$rec_dir/state/tasks/test-001"

cat > "$rec_dir/state/tasks/test-001/status.yaml" << 'EOF'
status: in_progress
budget:
  estimated_tokens: 0
  actual_tokens: 0
  by_agent: []
EOF

moira_budget_record_agent "test-001" "explorer" "50000" "45000" "$rec_dir/state"
assert_file_contains "$rec_dir/state/tasks/test-001/status.yaml" "explorer" "record_agent: writes role"
assert_file_contains "$rec_dir/state/tasks/test-001/status.yaml" "45000" "record_agent: writes actual tokens"

# Check cumulative totals
assert_yaml_value "$rec_dir/state/tasks/test-001/status.yaml" "budget.actual_tokens" "45000" "record_agent: updates actual_tokens"
assert_yaml_value "$rec_dir/state/tasks/test-001/status.yaml" "budget.estimated_tokens" "50000" "record_agent: updates estimated_tokens"

# Second recording adds cumulatively
moira_budget_record_agent "test-001" "reviewer" "30000" "28000" "$rec_dir/state"
assert_yaml_value "$rec_dir/state/tasks/test-001/status.yaml" "budget.actual_tokens" "73000" "record_agent: cumulative actual"
assert_yaml_value "$rec_dir/state/tasks/test-001/status.yaml" "budget.estimated_tokens" "80000" "record_agent: cumulative estimated"

# ── moira_budget_record_agent: missing file → warning ────────────────

run_fn moira_budget_record_agent "nonexistent" "explorer" "1000" "900" "$TEMP_DIR/no-state"
assert_exit_zero "record_agent: missing file → exit 0 (warning)"

# ── moira_budget_estimate_agent: structured output ───────────────────

dd if=/dev/zero bs=1 count=2000 of="$TEMP_DIR/agent-file.txt" 2>/dev/null

run_fn moira_budget_estimate_agent "classifier" "$TEMP_DIR/agent-file.txt" "1000" "500" "200"
assert_output_contains "$FN_STDOUT" "working_data: 500" "estimate_agent: working_data calculated"
assert_output_contains "$FN_STDOUT" "knowledge: 1000" "estimate_agent: knowledge passed through"
assert_output_contains "$FN_STDOUT" "total: 2200" "estimate_agent: total = working + knowledge + instructions + mcp"
assert_output_contains "$FN_STDOUT" "status:" "estimate_agent: includes status"

test_summary
