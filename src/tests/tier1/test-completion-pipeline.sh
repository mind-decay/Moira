#!/usr/bin/env bash
# test-completion-pipeline.sh — Functional tests for completion pipeline lifecycle
# Covers: telemetry creation, cleanup preserve-list, retention archival, end-to-end sequence
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Completion Pipeline (telemetry, cleanup, retention)"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source completion.sh (which sources dependencies; re-set +e after)
source "$SRC_DIR/global/lib/completion.sh"
set +e

# ── Helper: create a realistic task directory with all artifact types ──
create_full_task() {
  local state_dir="$1" task_id="$2" days_ago="${3:-0}"
  local task_dir="$state_dir/tasks/$task_id"
  mkdir -p "$task_dir/instructions" "$task_dir/findings" "$task_dir/phases/batch1"

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local completed_epoch
  completed_epoch=$(( $(date -u +%s) - days_ago * 86400 ))
  local completed_at
  completed_at=$(date -u -r "$completed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$completed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || completed_at="$ts"

  # status.yaml (must pre-exist for finalize to update)
  cat > "$task_dir/status.yaml" << EOF
task_id: "$task_id"
step_status: "gate_pending"
created_at: "$ts"
budget:
  actual_tokens: 15000
  estimated_tokens: 20000
completion:
  tweak_count: 1
  redo_count: 0
EOF

  # Intermediate artifacts (should be deleted by cleanup)
  echo "classification data" > "$task_dir/classification.md"
  echo "exploration data" > "$task_dir/exploration.md"
  echo "architecture data" > "$task_dir/architecture.md"
  echo "plan data" > "$task_dir/plan.md"
  echo "implementation data" > "$task_dir/implementation.md"
  echo "review data" > "$task_dir/review.md"
  echo "testing data" > "$task_dir/testing.md"
  echo "requirements data" > "$task_dir/requirements.md"
  echo "test results" > "$task_dir/test-results.md"
  echo "input data" > "$task_dir/input.md"
  echo "alternatives data" > "$task_dir/alternatives.md"
  echo "context data" > "$task_dir/context.md"
  echo "tweak xref" > "$task_dir/tweak-xref.md"

  # Glob-matched variants
  echo "review tweak" > "$task_dir/review-tweak-001.md"
  echo "tweak" > "$task_dir/tweak-001.md"
  echo "impl batch" > "$task_dir/implementation-batch1.md"
  echo "batch report" > "$task_dir/batch-1-report.md"

  # Manifest
  cat > "$task_dir/manifest.yaml" << EOF
task_id: "$task_id"
pipeline: standard
created_at: "$ts"
EOF

  # Subdirectory contents
  echo "instruction 1" > "$task_dir/instructions/step1.md"
  echo "finding 1" > "$task_dir/findings/finding1.md"
  echo "batch impl" > "$task_dir/phases/batch1/impl.md"
}

# ── Helper: create a minimal config for finalize ──
create_config() {
  local config_path="$1"
  cat > "$config_path" << EOF
version: "0.12.0"
project:
  name: "test-project"
  stack: "bash"
quality:
  mode: "conform"
EOF
}

# ── Setup ──
STATE_DIR="$TEMP_DIR/.moira/state"
CONFIG_PATH="$TEMP_DIR/.moira/config.yaml"
mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/archive" "$STATE_DIR/reflection"
mkdir -p "$TEMP_DIR/.moira"
create_config "$CONFIG_PATH"

# Create a global current.yaml (should be deleted by cleanup)
echo "pipeline: standard" > "$STATE_DIR/current.yaml"

# ══════════════════════════════════════════════════════════════════════
# 1. telemetry.yaml creation
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 1. Telemetry creation ──"

create_full_task "$STATE_DIR" "T-TEL-001"
# Create empty violations log (finalize reads it)
touch "$STATE_DIR/violations.log"

moira_completion_finalize "T-TEL-001" "standard" "done" "$STATE_DIR" "$CONFIG_PATH" > /dev/null 2>&1
exit_code=$?

assert_exit_code 0 "$exit_code" "finalize exits successfully"
assert_file_exists "$STATE_DIR/tasks/T-TEL-001/telemetry.yaml" "telemetry.yaml created by finalize"
assert_file_contains "$STATE_DIR/tasks/T-TEL-001/telemetry.yaml" "compliance" "telemetry has compliance data"
assert_file_contains "$STATE_DIR/tasks/T-TEL-001/telemetry.yaml" "structural" "telemetry has structural data"
assert_file_contains "$STATE_DIR/tasks/T-TEL-001/telemetry.yaml" "quality" "telemetry has quality data"

# ══════════════════════════════════════════════════════════════════════
# 2. status.yaml updates by finalize
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 2. Status updates ──"

assert_file_contains "$STATE_DIR/tasks/T-TEL-001/status.yaml" "status: completed" "status.yaml marked completed"
assert_file_contains "$STATE_DIR/tasks/T-TEL-001/status.yaml" "completed_at:" "status.yaml has completed_at"
assert_file_contains "$STATE_DIR/tasks/T-TEL-001/status.yaml" "completion_processor" "status.yaml has completion_processor"

# ══════════════════════════════════════════════════════════════════════
# 3. Cleanup preserves permanent records
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 3. Cleanup preserves permanent records ──"

# Write a reflection.md (simulating Phase 2 reflection output)
echo "reflection observations" > "$STATE_DIR/tasks/T-TEL-001/reflection.md"

moira_completion_cleanup "T-TEL-001" "$STATE_DIR" "standard"

assert_file_exists "$STATE_DIR/tasks/T-TEL-001/status.yaml" "cleanup preserves status.yaml"
assert_file_exists "$STATE_DIR/tasks/T-TEL-001/telemetry.yaml" "cleanup preserves telemetry.yaml"
assert_file_exists "$STATE_DIR/tasks/T-TEL-001/reflection.md" "cleanup preserves reflection.md"

# ══════════════════════════════════════════════════════════════════════
# 4. Cleanup deletes intermediate artifacts
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 4. Cleanup deletes intermediates ──"

assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/classification.md" "cleanup deletes classification.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/exploration.md" "cleanup deletes exploration.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/architecture.md" "cleanup deletes architecture.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/plan.md" "cleanup deletes plan.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/implementation.md" "cleanup deletes implementation.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/review.md" "cleanup deletes review.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/testing.md" "cleanup deletes testing.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/requirements.md" "cleanup deletes requirements.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/test-results.md" "cleanup deletes test-results.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/input.md" "cleanup deletes input.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/manifest.yaml" "cleanup deletes manifest.yaml"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/alternatives.md" "cleanup deletes alternatives.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/context.md" "cleanup deletes context.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/tweak-xref.md" "cleanup deletes tweak-xref.md"

# ══════════════════════════════════════════════════════════════════════
# 5. Cleanup deletes glob-matched files
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 5. Cleanup deletes glob-matched files ──"

assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/review-tweak-001.md" "cleanup deletes review-tweak-*.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/tweak-001.md" "cleanup deletes tweak-*.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/implementation-batch1.md" "cleanup deletes implementation-batch*.md"
assert_file_not_exists "$STATE_DIR/tasks/T-TEL-001/batch-1-report.md" "cleanup deletes batch-*-report.md"

# ══════════════════════════════════════════════════════════════════════
# 6. Cleanup deletes subdirectories
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 6. Cleanup deletes subdirectories ──"

assert_dir_not_exists "$STATE_DIR/tasks/T-TEL-001/instructions" "cleanup deletes instructions/"
assert_dir_not_exists "$STATE_DIR/tasks/T-TEL-001/findings" "cleanup deletes findings/"
assert_dir_not_exists "$STATE_DIR/tasks/T-TEL-001/phases" "cleanup deletes phases/"

# ══════════════════════════════════════════════════════════════════════
# 7. Cleanup removes global current.yaml
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 7. Global state cleanup ──"

assert_file_not_exists "$STATE_DIR/current.yaml" "cleanup removes global current.yaml"

# ══════════════════════════════════════════════════════════════════════
# 8. End-to-end: finalize → reflection → cleanup
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 8. End-to-end sequence ──"

create_full_task "$STATE_DIR" "T-E2E-001"
echo "pipeline: standard" > "$STATE_DIR/current.yaml"

# Phase 1: finalize
moira_completion_finalize "T-E2E-001" "standard" "done" "$STATE_DIR" "$CONFIG_PATH" > /dev/null 2>&1

# Phase 2: simulate reflection output
echo "deep reflection observations" > "$STATE_DIR/tasks/T-E2E-001/reflection.md"

# Phase 2b: cleanup
moira_completion_cleanup "T-E2E-001" "$STATE_DIR" "standard"

# Verify permanent records survived the full sequence
assert_file_exists "$STATE_DIR/tasks/T-E2E-001/status.yaml" "e2e: status.yaml survives"
assert_file_exists "$STATE_DIR/tasks/T-E2E-001/telemetry.yaml" "e2e: telemetry.yaml survives"
assert_file_exists "$STATE_DIR/tasks/T-E2E-001/reflection.md" "e2e: reflection.md survives"
assert_file_contains "$STATE_DIR/tasks/T-E2E-001/status.yaml" "status: completed" "e2e: status is completed"

# Verify intermediates are gone
assert_file_not_exists "$STATE_DIR/tasks/T-E2E-001/classification.md" "e2e: intermediates deleted"
assert_file_not_exists "$STATE_DIR/tasks/T-E2E-001/manifest.yaml" "e2e: manifest deleted"
assert_dir_not_exists "$STATE_DIR/tasks/T-E2E-001/instructions" "e2e: instruction dirs deleted"

# ══════════════════════════════════════════════════════════════════════
# 9. Retention cleanup archives permanent records
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 9. Retention archival ──"

create_full_task "$STATE_DIR" "T-RET-001" 45
# Mark as completed (retention only cleans completed tasks)
sed -i.bak 's/step_status: "gate_pending"/step_status: "completed"/' "$STATE_DIR/tasks/T-RET-001/status.yaml" 2>/dev/null || \
  sed -i '' 's/step_status: "gate_pending"/step_status: "completed"/' "$STATE_DIR/tasks/T-RET-001/status.yaml"
# Add completed_at for age check
completed_epoch=$(( $(date -u +%s) - 45 * 86400 ))
completed_at_val=$(date -u -r "$completed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$completed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
echo "completed_at: \"$completed_at_val\"" >> "$STATE_DIR/tasks/T-RET-001/status.yaml"

# Create telemetry (simulating a task that ran with the fix)
echo "compliance:" > "$STATE_DIR/tasks/T-RET-001/telemetry.yaml"
echo "  orchestrator_violation_count: 0" >> "$STATE_DIR/tasks/T-RET-001/telemetry.yaml"

moira_task_cleanup "$STATE_DIR" 30

# Task dir should be gone
if [[ ! -d "$STATE_DIR/tasks/T-RET-001" ]]; then
  pass "retention: task dir deleted"
else
  fail "retention: task dir should be deleted"
fi

# But permanent records should be archived
assert_file_exists "$STATE_DIR/archive/T-RET-001-manifest.yaml" "retention: manifest archived"
assert_file_exists "$STATE_DIR/archive/T-RET-001-status.yaml" "retention: status.yaml archived"
assert_file_exists "$STATE_DIR/archive/T-RET-001-telemetry.yaml" "retention: telemetry.yaml archived"

# ══════════════════════════════════════════════════════════════════════
# 10. Preserve-list robustness: unknown files get cleaned
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 10. Preserve-list robustness ──"

create_full_task "$STATE_DIR" "T-ROB-001"
# Add an unknown file (simulates future artifact type)
echo "some new artifact" > "$STATE_DIR/tasks/T-ROB-001/some-random-artifact.md"
echo "another future thing" > "$STATE_DIR/tasks/T-ROB-001/debug-trace.log"
# Add reflection (should be preserved)
echo "reflection" > "$STATE_DIR/tasks/T-ROB-001/reflection.md"

moira_completion_cleanup "T-ROB-001" "$STATE_DIR" "standard"

assert_file_exists "$STATE_DIR/tasks/T-ROB-001/status.yaml" "robustness: status.yaml preserved"
assert_file_exists "$STATE_DIR/tasks/T-ROB-001/reflection.md" "robustness: reflection.md preserved"
assert_file_not_exists "$STATE_DIR/tasks/T-ROB-001/some-random-artifact.md" "robustness: unknown file cleaned"
assert_file_not_exists "$STATE_DIR/tasks/T-ROB-001/debug-trace.log" "robustness: unknown log cleaned"

# ══════════════════════════════════════════════════════════════════════
# 11. Epic cleanup
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "── 11. Epic cleanup ──"

create_full_task "$STATE_DIR" "T-EPIC-001"
echo "reflection" > "$STATE_DIR/tasks/T-EPIC-001/reflection.md"
echo "queue data" > "$STATE_DIR/tasks/T-EPIC-001/queue.yaml"
mkdir -p "$STATE_DIR/tasks/T-EPIC-001/subtask-1" "$STATE_DIR/tasks/T-EPIC-001/subtask-2"
echo "subtask" > "$STATE_DIR/tasks/T-EPIC-001/subtask-1/impl.md"
echo "subtask" > "$STATE_DIR/tasks/T-EPIC-001/subtask-2/impl.md"
# Global queue pointing to this epic
cat > "$STATE_DIR/queue.yaml" << EOF
epic_id: T-EPIC-001
current_subtask: 2
EOF

moira_completion_cleanup "T-EPIC-001" "$STATE_DIR" "epic"

assert_file_exists "$STATE_DIR/tasks/T-EPIC-001/status.yaml" "epic: status.yaml preserved"
assert_file_exists "$STATE_DIR/tasks/T-EPIC-001/reflection.md" "epic: reflection.md preserved"
assert_dir_not_exists "$STATE_DIR/tasks/T-EPIC-001/subtask-1" "epic: subtask-1 deleted"
assert_dir_not_exists "$STATE_DIR/tasks/T-EPIC-001/subtask-2" "epic: subtask-2 deleted"
assert_file_not_exists "$STATE_DIR/tasks/T-EPIC-001/queue.yaml" "epic: queue.yaml deleted"
assert_file_not_exists "$STATE_DIR/queue.yaml" "epic: global queue deleted"

# ══════════════════════════════════════════════════════════════════════
echo ""
test_summary
