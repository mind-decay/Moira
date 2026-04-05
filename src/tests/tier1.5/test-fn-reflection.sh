#!/usr/bin/env bash
# test-fn-reflection.sh — Functional tests for reflection.sh
# Tests task history, observation counting, proposal management, deep counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: reflection.sh (functional)"

source "$SRC_LIB_DIR/reflection.sh"
set +e

# ── Helper: create completed tasks ───────────────────────────────────
setup_reflection_state() {
  local state_dir="$1"
  mkdir -p "$state_dir/tasks/task-2026-04-05-001"
  mkdir -p "$state_dir/tasks/task-2026-04-05-002"

  cat > "$state_dir/tasks/task-2026-04-05-001/status.yaml" << 'EOF'
status: completed
task_id: task-2026-04-05-001
pipeline: standard
completed_at: "2026-04-05T10:00:00Z"
retries:
  total: 0
completion:
  final_review_passed: true
EOF

  cat > "$state_dir/tasks/task-2026-04-05-001/telemetry.yaml" << 'EOF'
pipeline:
  classification_correct: true
EOF

  cat > "$state_dir/tasks/task-2026-04-05-002/status.yaml" << 'EOF'
status: completed
task_id: task-2026-04-05-002
pipeline: standard
completed_at: "2026-04-05T11:00:00Z"
retries:
  total: 2
completion:
  final_review_passed: false
EOF

  cat > "$state_dir/tasks/task-2026-04-05-002/telemetry.yaml" << 'EOF'
pipeline:
  classification_correct: true
EOF
}

# ── moira_reflection_task_history: returns history ───────────────────

refl_state="$TEMP_DIR/refl-state"
setup_reflection_state "$refl_state"

run_fn moira_reflection_task_history "$refl_state" "5"
assert_exit_zero "task_history: exit 0"
assert_output_contains "$FN_STDOUT" "task-2026-04-05" "task_history: includes task IDs"
assert_output_contains "$FN_STDOUT" "standard" "task_history: includes pipeline type"

# ── moira_reflection_task_history: no tasks → error ──────────────────

run_fn moira_reflection_task_history "$TEMP_DIR/no-tasks" "5"
assert_exit_nonzero "task_history: no tasks → exit 1"

# ── moira_reflection_deep_counter: read default ──────────────────────

counter_state="$TEMP_DIR/counter-state"
mkdir -p "$counter_state"
run_fn moira_reflection_deep_counter "$counter_state"
assert_exit_zero "deep_counter: read → exit 0"

# ── moira_reflection_deep_counter: increment ─────────────────────────

moira_reflection_deep_counter "$counter_state" "reset" > /dev/null 2>&1
run_fn moira_reflection_deep_counter "$counter_state" "increment"
assert_exit_zero "deep_counter: increment → exit 0"
val1="$FN_STDOUT"

run_fn moira_reflection_deep_counter "$counter_state" "increment"
val2="$FN_STDOUT"
if [[ -n "$val1" && -n "$val2" ]]; then
  pass "deep_counter: increments produce values"
else
  fail "deep_counter: increment should produce output"
fi

# ── moira_reflection_deep_counter: reset ─────────────────────────────

run_fn moira_reflection_deep_counter "$counter_state" "reset"
assert_exit_zero "deep_counter: reset → exit 0"

# ── moira_reflection_record_proposal: creates proposals file ─────────

proposal_state="$TEMP_DIR/proposal-state"
mkdir -p "$proposal_state"

proposal_yaml="id: prop-001
type: rule_change
description: Update naming convention
evidence: 3 tasks showed inconsistency"

moira_reflection_record_proposal "$proposal_state" "$proposal_yaml"

# File is created at {state_dir}/reflection/proposals.yaml
proposals_file="$proposal_state/reflection/proposals.yaml"
assert_file_exists "$proposals_file" "record_proposal: creates reflection/proposals.yaml"
assert_file_contains "$proposals_file" "prop-001" "record_proposal: records proposal id"
assert_file_contains "$proposals_file" "pending" "record_proposal: sets status pending"

# ── moira_reflection_pending_proposals: lists pending ────────────────

run_fn moira_reflection_pending_proposals "$proposal_state"
assert_exit_zero "pending_proposals: exit 0"
assert_output_contains "$FN_STDOUT" "prop-001" "pending_proposals: lists proposal"

# ── moira_reflection_resolve_proposal: approve ───────────────────────

run_fn moira_reflection_resolve_proposal "$proposal_state" "prop-001" "approved"
assert_exit_zero "resolve_proposal: approved → exit 0"
assert_file_contains "$proposals_file" "approved" "resolve_proposal: status updated to approved"

# ── moira_reflection_resolve_proposal: nonexistent ID → silent no-op ─
# awk rewrites file without finding the ID — no error, no change

run_fn moira_reflection_resolve_proposal "$proposal_state" "nonexistent" "rejected"
assert_exit_zero "resolve_proposal: nonexistent ID → exit 0 (silent no-op)"

test_summary
