#!/usr/bin/env bash
# test-fn-checkpoint.sh — Functional tests for checkpoint.sh
# Tests checkpoint create, validate, resume context, cleanup.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: checkpoint.sh (functional)"

source "$SRC_LIB_DIR/checkpoint.sh"
set +e

# ── Helper: setup task state for checkpoint tests ────────────────────
setup_checkpoint_state() {
  local state_dir="$1"
  local task_id="$2"
  local task_dir="$state_dir/tasks/$task_id"

  mkdir -p "$task_dir"

  cat > "$state_dir/current.yaml" << YAML
task_id: $task_id
pipeline: standard
step: implementation
step_status: in_progress
YAML

  cat > "$task_dir/status.yaml" << YAML
status: in_progress
created_at: "2026-04-05T10:00:00Z"
gates:
  - gate: classification
    decision: proceed
  - gate: architecture
    decision: proceed
YAML

  cat > "$task_dir/input.md" << 'YAML'
Add pagination to API endpoint
YAML
}

# ── moira_checkpoint_create: valid reasons ───────────────────────────

valid_reasons="context_limit user_pause error session_end"

for reason in $valid_reasons; do
  cp_state="$TEMP_DIR/cp-$reason"
  setup_checkpoint_state "$cp_state" "test-001"
  run_fn moira_checkpoint_create "test-001" "implementation" "$reason" "$cp_state"
  assert_exit_zero "checkpoint_create: reason '$reason' accepted"
done

# ── moira_checkpoint_create: writes manifest ─────────────────────────

cp_state="$TEMP_DIR/cp-manifest"
setup_checkpoint_state "$cp_state" "test-001"
moira_checkpoint_create "test-001" "implementation" "user_pause" "$cp_state"
assert_file_exists "$cp_state/tasks/test-001/manifest.yaml" "checkpoint_create: creates manifest"
assert_file_contains "$cp_state/tasks/test-001/manifest.yaml" "implementation" "checkpoint_create: records step"
assert_file_contains "$cp_state/tasks/test-001/manifest.yaml" "user_pause" "checkpoint_create: records reason"

# ── moira_checkpoint_create: updates status to checkpointed ──────────

# checkpoint_create does NOT call moira_state_set_status — that's the orchestrator's job
status_val=$(moira_yaml_get "$cp_state/tasks/test-001/status.yaml" "status" 2>/dev/null) || status_val=""
assert_equals "$status_val" "in_progress" "checkpoint_create: does NOT change status (orchestrator responsibility)"

# ── moira_checkpoint_cleanup: removes manifest ───────────────────────

cp_clean="$TEMP_DIR/cp-clean"
setup_checkpoint_state "$cp_clean" "test-001"
moira_checkpoint_create "test-001" "implementation" "user_pause" "$cp_clean"
assert_file_exists "$cp_clean/tasks/test-001/manifest.yaml" "cleanup: manifest exists before"
moira_checkpoint_cleanup "test-001" "$cp_clean"
assert_file_not_exists "$cp_clean/tasks/test-001/manifest.yaml" "cleanup: manifest removed"

# ── moira_checkpoint_cleanup: no manifest → no error ─────────────────

run_fn moira_checkpoint_cleanup "test-001" "$TEMP_DIR/no-manifest"
assert_exit_zero "cleanup: no manifest → exit 0"

# ── moira_checkpoint_build_resume_context: produces summary ──────────

cp_resume="$TEMP_DIR/cp-resume"
setup_checkpoint_state "$cp_resume" "test-001"
moira_checkpoint_create "test-001" "implementation" "context_limit" "$cp_resume"
run_fn moira_checkpoint_build_resume_context "test-001" "$cp_resume"
assert_exit_zero "resume_context: exit 0"
# resume_context always returns a summary sentence, even with "(none)" placeholders
if [[ -n "$FN_STDOUT" ]]; then
  pass "resume_context: returns non-empty summary"
else
  fail "resume_context: should always return a summary sentence"
fi

# ── moira_checkpoint_validate: missing manifest → inconsistent ───────

run_fn moira_checkpoint_validate "nonexistent" "$TEMP_DIR/no-task"
assert_exit_zero "validate: returns exit 0 with diagnostic string"
assert_output_contains "$FN_STDOUT" "inconsistent" "validate: missing manifest → inconsistent diagnosis"

test_summary
