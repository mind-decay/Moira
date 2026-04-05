#!/usr/bin/env bash
# test-fn-epic.sh — Functional tests for epic.sh
# Tests DAG validation, task scheduling, progress tracking.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: epic.sh (functional)"

source "$SRC_LIB_DIR/epic.sh"
set +e

# ── Helper: create epic queue ────────────────────────────────────────
setup_epic() {
  local state_dir="$1"
  local task_id="$2"
  local task_dir="$state_dir/tasks/$task_id"
  mkdir -p "$task_dir"

  cat > "$task_dir/queue.yaml" << YAML
epic_id: $task_id
tasks:
  - id: sub-001
    description: "Set up database schema"
    size: small
    status: completed
    depends_on: []
  - id: sub-002
    description: "Implement API endpoints"
    size: medium
    status: pending
    depends_on: [sub-001]
  - id: sub-003
    description: "Write tests"
    size: small
    status: pending
    depends_on: [sub-002]
  - id: sub-004
    description: "Add documentation"
    size: small
    status: pending
    depends_on: []
YAML
}

# ── moira_epic_parse_queue: reads tasks ──────────────────────────────

epic_state="$TEMP_DIR/epic-state"
setup_epic "$epic_state" "test-001"

run_fn moira_epic_parse_queue "test-001" "$epic_state"
assert_exit_zero "parse_queue: exit 0"
assert_output_contains "$FN_STDOUT" "sub-001" "parse_queue: includes first task"
assert_output_contains "$FN_STDOUT" "sub-004" "parse_queue: includes last task"

# ── moira_epic_validate_dag: valid DAG ───────────────────────────────

run_fn moira_epic_validate_dag "test-001" "$epic_state"
assert_exit_zero "validate_dag: valid → exit 0"
assert_output_contains "$FN_STDOUT" "valid" "validate_dag: outputs valid"

# ── moira_epic_validate_dag: cycle detection ─────────────────────────

cycle_state="$TEMP_DIR/epic-cycle"
mkdir -p "$cycle_state/tasks/test-002"
cat > "$cycle_state/tasks/test-002/queue.yaml" << 'EOF'
epic_id: test-002
tasks:
  - id: a
    description: "Task A"
    size: small
    status: pending
    depends_on: [b]
  - id: b
    description: "Task B"
    size: small
    status: pending
    depends_on: [a]
EOF

run_fn moira_epic_validate_dag "test-002" "$cycle_state"
assert_output_contains "$FN_STDOUT" "cycle" "validate_dag: detects cycle"

# ── moira_epic_next_tasks: scheduling ────────────────────────────────

run_fn moira_epic_next_tasks "test-001" "$epic_state"
assert_exit_zero "next_tasks: exit 0"
# sub-002 is pending with dep sub-001 (completed) → eligible
assert_output_contains "$FN_STDOUT" "sub-002" "next_tasks: sub-002 eligible (dep completed)"
# sub-004 is pending with no deps → eligible
assert_output_contains "$FN_STDOUT" "sub-004" "next_tasks: sub-004 eligible (no deps)"
# sub-003 depends on sub-002 (pending) → not eligible
assert_output_not_contains "$FN_STDOUT" "sub-003" "next_tasks: sub-003 not eligible (dep pending)"

# ── moira_epic_update_progress: updates status ───────────────────────

moira_epic_update_progress "test-001" "sub-002" "completed" "$epic_state"
# Verify sub-002 is now completed in queue
assert_file_contains "$epic_state/tasks/test-001/queue.yaml" "completed" "update_progress: writes status"

# ── moira_epic_check_dependencies: ready ─────────────────────────────

# After sub-002 completed, sub-003 should be ready
run_fn moira_epic_check_dependencies "test-001" "sub-003" "$epic_state"
assert_output_contains "$FN_STDOUT" "ready" "check_dependencies: sub-003 ready after sub-002 completed"

# ── moira_epic_check_dependencies: blocked ───────────────────────────

# Reset sub-002 to pending for this test
reset_state="$TEMP_DIR/epic-blocked"
setup_epic "$reset_state" "test-003"
run_fn moira_epic_check_dependencies "test-003" "sub-003" "$reset_state"
assert_output_contains "$FN_STDOUT" "blocked" "check_dependencies: sub-003 blocked (sub-002 pending)"

test_summary
