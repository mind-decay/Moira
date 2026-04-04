#!/usr/bin/env bash
# test-task-cleanup.sh — Tier 1 tests for task state cleanup (D-219)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Task State Cleanup (D-219)"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source completion.sh (which sources dependencies; re-set +e after)
source "$SRC_DIR/global/lib/completion.sh"
set +e

# ── Helper: create a task dir with given status and age ──
create_task() {
  local state_dir="$1" task_id="$2" status="$3" days_ago="${4:-0}"
  local task_dir="$state_dir/tasks/$task_id"
  mkdir -p "$task_dir"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Compute completed_at timestamp (days_ago * 86400 seconds before now)
  local completed_epoch
  completed_epoch=$(( $(date -u +%s) - days_ago * 86400 ))
  local completed_at
  completed_at=$(date -u -r "$completed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$completed_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || completed_at="$ts"

  cat > "$task_dir/status.yaml" << EOF
task_id: "$task_id"
step_status: "$status"
completed_at: "$completed_at"
created_at: "$ts"
EOF
  cat > "$task_dir/manifest.yaml" << EOF
task_id: "$task_id"
pipeline: standard
created_at: "$ts"
EOF
}

# ── Setup ──
STATE_DIR="$TEMP_DIR/.moira/state"
mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/archive"

# Create test tasks
create_task "$STATE_DIR" "T-001" "completed" 45   # old completed (should clean)
create_task "$STATE_DIR" "T-002" "completed" 10   # recent completed (keep)
create_task "$STATE_DIR" "T-003" "checkpointed" 45 # old checkpointed (never clean)
create_task "$STATE_DIR" "T-004" "in_progress" 45  # old in_progress (never clean)
create_task "$STATE_DIR" "T-005" "completed" 60    # old completed (should clean)

# ── 1. Status filtering: only completed ──
moira_task_cleanup "$STATE_DIR" 30

if [[ ! -d "$STATE_DIR/tasks/T-001" ]]; then
  pass "cleanup: completed task older than retention is deleted"
else
  fail "cleanup: T-001 (completed, 45d) should be deleted"
fi

if [[ -d "$STATE_DIR/tasks/T-002" ]]; then
  pass "cleanup: recent completed task preserved"
else
  fail "cleanup: T-002 (completed, 10d) should be preserved"
fi

if [[ -d "$STATE_DIR/tasks/T-003" ]]; then
  pass "cleanup: checkpointed task never cleaned"
else
  fail "cleanup: T-003 (checkpointed) must NEVER be cleaned"
fi

if [[ -d "$STATE_DIR/tasks/T-004" ]]; then
  pass "cleanup: in_progress task never cleaned"
else
  fail "cleanup: T-004 (in_progress) must NEVER be cleaned"
fi

if [[ ! -d "$STATE_DIR/tasks/T-005" ]]; then
  pass "cleanup: second old completed task also deleted"
else
  fail "cleanup: T-005 (completed, 60d) should be deleted"
fi

# ── 2. Archive-then-delete: manifest preserved ──
assert_file_exists "$STATE_DIR/archive/T-001-manifest.yaml" "archive: T-001 manifest archived"
assert_file_exists "$STATE_DIR/archive/T-005-manifest.yaml" "archive: T-005 manifest archived"

# ── 3. Idempotency: double-invoke no duplicate archives ──
# Run cleanup again — T-001 already cleaned, should not fail or duplicate
moira_task_cleanup "$STATE_DIR" 30
# Archive should still have exactly one copy per task
if [[ -f "$STATE_DIR/archive/T-001-manifest.yaml" ]]; then
  pass "idempotency: double cleanup no error"
else
  fail "idempotency: archive should still exist after second cleanup"
fi

# ── 4. Missing manifest: task dir deleted anyway ──
create_task "$STATE_DIR" "T-006" "completed" 45
rm -f "$STATE_DIR/tasks/T-006/manifest.yaml"
moira_task_cleanup "$STATE_DIR" 30
if [[ ! -d "$STATE_DIR/tasks/T-006" ]]; then
  pass "missing manifest: task dir still deleted"
else
  fail "missing manifest: T-006 should be deleted even without manifest"
fi

# ── 5. WAL recovery: intent marker without completed cleanup ──
create_task "$STATE_DIR" "T-007" "completed" 45
# Simulate crash: create intent marker, archive manifest, but don't delete dir
touch "$STATE_DIR/tasks/.cleanup-T-007"
cp "$STATE_DIR/tasks/T-007/manifest.yaml" "$STATE_DIR/archive/T-007-manifest.yaml" 2>/dev/null || true

moira_task_cleanup "$STATE_DIR" 30
if [[ ! -d "$STATE_DIR/tasks/T-007" ]]; then
  pass "WAL recovery: dir cleaned after crash recovery"
else
  fail "WAL recovery: T-007 should be cleaned via intent marker"
fi
if [[ ! -f "$STATE_DIR/tasks/.cleanup-T-007" ]]; then
  pass "WAL recovery: intent marker removed"
else
  fail "WAL recovery: .cleanup-T-007 marker should be removed"
fi

# ── 6. Cap at 10: create 15 eligible tasks ──
for i in $(seq 20 34); do
  create_task "$STATE_DIR" "T-0${i}" "completed" 45
done
moira_task_cleanup "$STATE_DIR" 30
# Count remaining task dirs (excluding T-002 recent + T-003 checkpoint + T-004 in_progress)
remaining=$(ls -d "$STATE_DIR/tasks"/T-0[23]?/ 2>/dev/null | wc -l | tr -d ' ')
# At least 5 should remain uncleaned (15 created, 10 max per invocation)
if [[ "$remaining" -ge 5 ]]; then
  pass "cap: at most 10 tasks cleaned per invocation"
else
  fail "cap: expected at least 5 remaining from 15, got $remaining"
fi

# ── 7. Retention 0 days: clean immediately ──
create_task "$STATE_DIR" "T-099" "completed" 0
# Wait 1 second so epoch comparison works
sleep 1
moira_task_cleanup "$STATE_DIR" 0
if [[ ! -d "$STATE_DIR/tasks/T-099" ]]; then
  pass "retention 0: task cleaned immediately"
else
  fail "retention 0: T-099 should be cleaned with retention=0"
fi

test_summary
