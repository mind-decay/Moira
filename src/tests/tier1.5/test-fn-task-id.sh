#!/usr/bin/env bash
# test-fn-task-id.sh — Functional tests for task-id.sh
# Tests ID generation, counter increment, zero-padding, overflow.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: task-id.sh (functional)"

# Source the library under test
source "$SRC_LIB_DIR/task-id.sh"
set +e

TODAY=$(date +%Y-%m-%d)

# ── First task of the day: no tasks dir → 001 ───────────────────────

run_fn moira_task_id "$TEMP_DIR/empty-state"
assert_exit_zero "task_id: no tasks dir → exit 0"
assert_output_equals "$FN_STDOUT" "task-${TODAY}-001" "task_id: first task → 001"

# ── First task: tasks dir exists but empty ───────────────────────────

mkdir -p "$TEMP_DIR/empty-tasks/tasks"
run_fn moira_task_id "$TEMP_DIR/empty-tasks"
assert_output_equals "$FN_STDOUT" "task-${TODAY}-001" "task_id: empty tasks dir → 001"

# ── Increment: existing task 001 → 002 ──────────────────────────────

mkdir -p "$TEMP_DIR/one-task/tasks/task-${TODAY}-001"
run_fn moira_task_id "$TEMP_DIR/one-task"
assert_output_equals "$FN_STDOUT" "task-${TODAY}-002" "task_id: after 001 → 002"

# ── Increment: existing tasks 001-003 → 004 ─────────────────────────

mkdir -p "$TEMP_DIR/multi-task/tasks/task-${TODAY}-001"
mkdir -p "$TEMP_DIR/multi-task/tasks/task-${TODAY}-002"
mkdir -p "$TEMP_DIR/multi-task/tasks/task-${TODAY}-003"
run_fn moira_task_id "$TEMP_DIR/multi-task"
assert_output_equals "$FN_STDOUT" "task-${TODAY}-004" "task_id: after 003 → 004"

# ── Zero-padding preserved ───────────────────────────────────────────

# Verify format is NNN (3 digits)
run_fn moira_task_id "$TEMP_DIR/empty-state"
if [[ "$FN_STDOUT" =~ task-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$ ]]; then
  pass "task_id: format matches task-YYYY-MM-DD-NNN"
else
  fail "task_id: format mismatch: $FN_STDOUT"
fi

# ── Gap handling: non-consecutive → uses highest ─────────────────────

mkdir -p "$TEMP_DIR/gap-task/tasks/task-${TODAY}-001"
mkdir -p "$TEMP_DIR/gap-task/tasks/task-${TODAY}-005"
run_fn moira_task_id "$TEMP_DIR/gap-task"
assert_output_equals "$FN_STDOUT" "task-${TODAY}-006" "task_id: gap → uses highest + 1"

# ── Different date tasks ignored ─────────────────────────────────────

mkdir -p "$TEMP_DIR/other-date/tasks/task-2025-01-01-050"
mkdir -p "$TEMP_DIR/other-date/tasks/task-${TODAY}-003"
run_fn moira_task_id "$TEMP_DIR/other-date"
assert_output_equals "$FN_STDOUT" "task-${TODAY}-004" "task_id: ignores other dates"

# ── Overflow: 999 → error ────────────────────────────────────────────

mkdir -p "$TEMP_DIR/overflow/tasks/task-${TODAY}-999"
run_fn moira_task_id "$TEMP_DIR/overflow"
assert_exit_nonzero "task_id: 999 overflow → exit 1"
assert_output_contains "$FN_STDERR" "exceeded 999" "task_id: overflow error message"

test_summary
