#!/usr/bin/env bash
# test-fn-state.sh — Functional tests for state.sh
# Tests state transitions, gate recording, agent logging, retries, completion.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: state.sh (functional)"

# Source the library under test (pulls in yaml-utils.sh)
source "$SRC_LIB_DIR/state.sh"
set +e

# ── Helper: create minimal current.yaml ──────────────────────────────
setup_state() {
  local state_dir="$1"
  local task_id="${2:-test-2026-04-05-001}"
  local pipeline="${3:-standard}"
  local step="${4:-classification}"
  local step_status="${5:-in_progress}"

  mkdir -p "$state_dir"
  mkdir -p "$state_dir/tasks/$task_id"

  cat > "$state_dir/current.yaml" << YAML
task_id: $task_id
pipeline: $pipeline
step: $step
step_status: $step_status
gate_pending: null
context_budget:
  total_agent_tokens: 0
history: []
YAML

  cat > "$state_dir/tasks/$task_id/status.yaml" << YAML
status: in_progress
created_at: "2026-04-05T10:00:00Z"
gates: []
retries:
  total: 0
budget:
  estimated_tokens: 0
  actual_tokens: 0
  by_agent: []
warnings: []
completion:
  action: null
  tweak_count: 0
  redo_count: 0
  final_review_passed: false
YAML
}

# ── moira_state_current: no file → idle ──────────────────────────────

run_fn moira_state_current "$TEMP_DIR/empty-state"
assert_exit_zero "current: no file → exit 0"
assert_output_equals "$FN_STDOUT" "idle" "current: no file → idle"

# ── moira_state_current: null task_id → idle ─────────────────────────

mkdir -p "$TEMP_DIR/null-state"
cat > "$TEMP_DIR/null-state/current.yaml" << 'EOF'
task_id: null
pipeline: standard
step: classification
step_status: pending
EOF

run_fn moira_state_current "$TEMP_DIR/null-state"
assert_output_equals "$FN_STDOUT" "idle" "current: null task_id → idle"

# ── moira_state_current: valid state → structured output ─────────────

local_state="$TEMP_DIR/valid-state"
setup_state "$local_state"

run_fn moira_state_current "$local_state"
assert_exit_zero "current: valid state → exit 0"
assert_output_contains "$FN_STDOUT" "task_id: test-2026-04-05-001" "current: outputs task_id"
assert_output_contains "$FN_STDOUT" "pipeline: standard" "current: outputs pipeline"
assert_output_contains "$FN_STDOUT" "step: classification" "current: outputs step"
assert_output_contains "$FN_STDOUT" "step_status: in_progress" "current: outputs step_status"

# ── moira_state_transition: valid steps ──────────────────────────────

valid_steps="classification exploration analysis architecture plan implementation review testing reflection decomposition integration completion gather scope depth_checkpoint organize synthesis"

trans_state="$TEMP_DIR/trans-state"
for step in $valid_steps; do
  setup_state "$trans_state" "test-001" "standard" "classification" "pending"
  run_fn moira_state_transition "$step" "in_progress" "$trans_state"
  assert_exit_zero "transition: step '$step' accepted"
done

# ── moira_state_transition: invalid step ─────────────────────────────

setup_state "$trans_state" "test-001" "standard" "classification" "pending"
run_fn moira_state_transition "bogus_step" "in_progress" "$trans_state"
assert_exit_nonzero "transition: invalid step rejected"
assert_output_contains "$FN_STDERR" "unknown pipeline step" "transition: error message for invalid step"

# ── moira_state_transition: valid statuses ───────────────────────────

valid_statuses="pending in_progress awaiting_gate completed failed checkpointed"

for status in $valid_statuses; do
  setup_state "$trans_state" "test-001" "standard" "classification" "pending"
  run_fn moira_state_transition "classification" "$status" "$trans_state"
  assert_exit_zero "transition: status '$status' accepted"
done

# ── moira_state_transition: invalid status ───────────────────────────

setup_state "$trans_state" "test-001" "standard" "classification" "pending"
run_fn moira_state_transition "classification" "bogus_status" "$trans_state"
assert_exit_nonzero "transition: invalid status rejected"
assert_output_contains "$FN_STDERR" "unknown step status" "transition: error message for invalid status"

# ── moira_state_transition: writes values ────────────────────────────

setup_state "$trans_state" "test-001" "standard" "classification" "pending"
moira_state_transition "exploration" "in_progress" "$trans_state"
assert_yaml_value "$trans_state/current.yaml" "step" "exploration" "transition: writes step"
assert_yaml_value "$trans_state/current.yaml" "step_status" "in_progress" "transition: writes step_status"

# Verify step_started_at was written
started=$(moira_yaml_get "$trans_state/current.yaml" "step_started_at" 2>/dev/null) || started=""
if [[ -n "$started" ]]; then
  pass "transition: writes step_started_at"
else
  fail "transition: step_started_at not written"
fi

# ── moira_state_transition: no file → error ──────────────────────────

run_fn moira_state_transition "classification" "pending" "$TEMP_DIR/no-state"
assert_exit_nonzero "transition: no current.yaml → error"

# ── moira_state_gate: valid decisions ────────────────────────────────

valid_decisions="proceed modify abort sufficient deepen redirect done"

for decision in $valid_decisions; do
  gate_state="$TEMP_DIR/gate-$decision"
  setup_state "$gate_state" "test-001"
  moira_yaml_set "$gate_state/current.yaml" "gate_pending" "classification"
  run_fn moira_state_gate "classification" "$decision" "" "$gate_state"
  assert_exit_zero "gate: decision '$decision' accepted"
done

# ── moira_state_gate: invalid decision ───────────────────────────────

gate_state="$TEMP_DIR/gate-invalid"
setup_state "$gate_state" "test-001"
run_fn moira_state_gate "classification" "invalid_decision" "" "$gate_state"
assert_exit_nonzero "gate: invalid decision rejected"

# ── moira_state_gate: clears gate_pending ────────────────────────────

gate_state="$TEMP_DIR/gate-clear"
setup_state "$gate_state" "test-001"
moira_yaml_set "$gate_state/current.yaml" "gate_pending" "classification"
moira_state_gate "classification" "proceed" "" "$gate_state"
assert_yaml_value "$gate_state/current.yaml" "gate_pending" "" "gate: clears gate_pending to null"

# ── moira_state_gate: writes to status.yaml ──────────────────────────

gate_state="$TEMP_DIR/gate-write"
setup_state "$gate_state" "test-001"
moira_state_gate "architecture" "modify" "needs rework" "$gate_state"
assert_file_contains "$gate_state/tasks/test-001/status.yaml" "architecture" "gate: writes gate name to status"
assert_file_contains "$gate_state/tasks/test-001/status.yaml" "modify" "gate: writes decision to status"
assert_file_contains "$gate_state/tasks/test-001/status.yaml" "needs rework" "gate: writes note to status"

# ── moira_state_gate: no active task → error ─────────────────────────

mkdir -p "$TEMP_DIR/gate-no-task"
cat > "$TEMP_DIR/gate-no-task/current.yaml" << 'EOF'
task_id: null
pipeline: standard
step: classification
step_status: pending
EOF

run_fn moira_state_gate "classification" "proceed" "" "$TEMP_DIR/gate-no-task"
assert_exit_nonzero "gate: no active task → error"

# ── moira_state_agent_done: appends history ──────────────────────────

agent_state="$TEMP_DIR/agent-state"
setup_state "$agent_state" "test-001"
moira_state_agent_done "exploration" "explorer" "success" "35" "50000" "found 20 files" "$agent_state"
assert_file_contains "$agent_state/current.yaml" "exploration" "agent_done: appends step to history"
assert_file_contains "$agent_state/current.yaml" "explorer" "agent_done: appends role to history"
assert_file_contains "$agent_state/current.yaml" "50000" "agent_done: appends tokens to history"

# ── moira_state_agent_done: updates total_agent_tokens ───────────────

assert_yaml_value "$agent_state/current.yaml" "context_budget.total_agent_tokens" "50000" "agent_done: updates total_agent_tokens"

# Second agent adds tokens cumulatively
moira_state_agent_done "analysis" "analyst" "success" "20" "30000" "analyzed patterns" "$agent_state"
assert_yaml_value "$agent_state/current.yaml" "context_budget.total_agent_tokens" "80000" "agent_done: cumulative token tracking"

# ── moira_state_agent_done: no file → error ──────────────────────────

run_fn moira_state_agent_done "exploration" "explorer" "success" "10" "5000" "test" "$TEMP_DIR/no-agent-state"
assert_exit_nonzero "agent_done: no current.yaml → error"

# ── moira_state_increment_retry: total ───────────────────────────────

retry_state="$TEMP_DIR/retry-state"
setup_state "$retry_state" "test-001"
moira_state_increment_retry "test-001" "total" "$retry_state"
assert_yaml_value "$retry_state/tasks/test-001/status.yaml" "retries.total" "1" "retry: increments total"

moira_state_increment_retry "test-001" "total" "$retry_state"
assert_yaml_value "$retry_state/tasks/test-001/status.yaml" "retries.total" "2" "retry: increments total again"

# ── moira_state_increment_retry: type-specific ───────────────────────

retry_state2="$TEMP_DIR/retry-state2"
setup_state "$retry_state2" "test-001"
moira_state_increment_retry "test-001" "quality" "$retry_state2"
assert_yaml_value "$retry_state2/tasks/test-001/status.yaml" "retries.total" "1" "retry: quality also increments total"
assert_yaml_value "$retry_state2/tasks/test-001/status.yaml" "retries.quality" "1" "retry: quality counter incremented"

# ── moira_state_increment_retry: missing file → warning ──────────────

run_fn moira_state_increment_retry "nonexistent-task" "total" "$TEMP_DIR/retry-missing"
assert_exit_zero "retry: missing file → exit 0 (warning only)"
assert_output_contains "$FN_STDERR" "Warning" "retry: missing file → warning message"

# ── moira_state_set_status: valid statuses ───────────────────────────

valid_task_statuses="pending in_progress completed failed aborted"

for status in $valid_task_statuses; do
  status_state="$TEMP_DIR/status-$status"
  setup_state "$status_state" "test-001"
  run_fn moira_state_set_status "test-001" "$status" "$status_state"
  assert_exit_zero "set_status: '$status' accepted"
done

# ── moira_state_set_status: invalid ──────────────────────────────────

set_state="$TEMP_DIR/status-invalid"
setup_state "$set_state" "test-001"
run_fn moira_state_set_status "test-001" "invalid_status" "$set_state"
assert_exit_nonzero "set_status: invalid status rejected"

# ── moira_state_set_status: writes value ─────────────────────────────

set_state2="$TEMP_DIR/status-write"
setup_state "$set_state2" "test-001"
moira_state_set_status "test-001" "completed" "$set_state2"
assert_yaml_value "$set_state2/tasks/test-001/status.yaml" "status" "completed" "set_status: writes value"

# ── moira_state_set_status: missing file → warning ───────────────────

run_fn moira_state_set_status "nonexistent" "completed" "$TEMP_DIR/no-status"
assert_exit_zero "set_status: missing file → exit 0 (warning)"

# ── moira_state_record_completion: valid actions ─────────────────────

valid_actions="done tweak redo diff test abort"

for action in $valid_actions; do
  comp_state="$TEMP_DIR/comp-$action"
  setup_state "$comp_state" "test-001"
  run_fn moira_state_record_completion "test-001" "$action" "2" "1" "true" "$comp_state"
  assert_exit_zero "record_completion: action '$action' accepted"
done

# ── moira_state_record_completion: invalid action ────────────────────

comp_invalid="$TEMP_DIR/comp-invalid"
setup_state "$comp_invalid" "test-001"
run_fn moira_state_record_completion "test-001" "invalid_action" "0" "0" "false" "$comp_invalid"
assert_exit_nonzero "record_completion: invalid action rejected"

# ── moira_state_record_completion: writes all fields ─────────────────

comp_write="$TEMP_DIR/comp-write"
setup_state "$comp_write" "test-001"
moira_state_record_completion "test-001" "done" "3" "1" "true" "$comp_write"
assert_yaml_value "$comp_write/tasks/test-001/status.yaml" "completion.action" "done" "record_completion: writes action"
assert_yaml_value "$comp_write/tasks/test-001/status.yaml" "completion.tweak_count" "3" "record_completion: writes tweak_count"
assert_yaml_value "$comp_write/tasks/test-001/status.yaml" "completion.redo_count" "1" "record_completion: writes redo_count"
assert_yaml_value "$comp_write/tasks/test-001/status.yaml" "completion.final_review_passed" "true" "record_completion: writes final_review_passed"

# Verify completed_at was written
completed_at=$(moira_yaml_get "$comp_write/tasks/test-001/status.yaml" "completed_at" 2>/dev/null) || completed_at=""
if [[ -n "$completed_at" ]]; then
  pass "record_completion: writes completed_at"
else
  fail "record_completion: completed_at not written"
fi

test_summary
