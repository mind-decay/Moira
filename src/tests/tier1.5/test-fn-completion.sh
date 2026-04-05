#!/usr/bin/env bash
# test-fn-completion.sh — Functional tests for completion.sh
# Tests cleanup, log rotation, metrics retention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: completion.sh (functional)"

source "$SRC_LIB_DIR/completion.sh"
set +e

# ── _moira_completion_rotate_log: below threshold → no-op ────────────

mkdir -p "$TEMP_DIR/logs"
for i in $(seq 1 100); do echo "line $i" >> "$TEMP_DIR/logs/test.log"; done

_moira_completion_rotate_log "$TEMP_DIR/logs/test.log" 5000
if [[ ! -f "$TEMP_DIR/logs/test.log.1" ]]; then
  pass "rotate_log: below threshold → no archive"
else
  fail "rotate_log: should not archive when below threshold"
fi

# ── _moira_completion_rotate_log: above threshold → rotates ──────────

# Create large log (>2× threshold of 100 lines)
for i in $(seq 1 250); do echo "line $i" >> "$TEMP_DIR/logs/big.log"; done

_moira_completion_rotate_log "$TEMP_DIR/logs/big.log" 100
# Check if rotation happened (archive created or file truncated)
original_lines=$(wc -l < "$TEMP_DIR/logs/big.log" 2>/dev/null | tr -d ' ')
if [[ "$original_lines" -lt 250 ]] || ls "$TEMP_DIR/logs/big.log".* 2>/dev/null | grep -q .; then
  pass "rotate_log: above 2x threshold → rotated"
else
  fail "rotate_log: should rotate (lines=$original_lines, no archive found)"
fi

# ── moira_completion_cleanup: removes artifacts, preserves essentials ─

clean_state="$TEMP_DIR/clean-state"
mkdir -p "$clean_state/tasks/test-001"

# Create files that should be preserved
cat > "$clean_state/tasks/test-001/status.yaml" << 'EOF'
status: completed
EOF
cat > "$clean_state/tasks/test-001/telemetry.yaml" << 'EOF'
task_id: test-001
EOF
echo "# Reflection" > "$clean_state/tasks/test-001/reflection.md"

# Create files that should be cleaned
echo "input text" > "$clean_state/tasks/test-001/input.md"
mkdir -p "$clean_state/tasks/test-001/instructions"
echo "agent instructions" > "$clean_state/tasks/test-001/instructions/hermes.md"

run_fn moira_completion_cleanup "test-001" "$clean_state"
assert_exit_zero "completion_cleanup: exit 0"
assert_file_exists "$clean_state/tasks/test-001/status.yaml" "cleanup: preserves status.yaml"
assert_file_exists "$clean_state/tasks/test-001/telemetry.yaml" "cleanup: preserves telemetry.yaml"
assert_file_exists "$clean_state/tasks/test-001/reflection.md" "cleanup: preserves reflection.md"

# ── moira_completion_cleanup: path traversal → error ─────────────────

run_fn moira_completion_cleanup "../../../etc" "$clean_state"
assert_exit_nonzero "completion_cleanup: path traversal → exit 1"

# ── moira_completion_cleanup: missing task → exit 0 ──────────────────

run_fn moira_completion_cleanup "nonexistent" "$clean_state"
# Should not fail, just nothing to clean
assert_exit_zero "completion_cleanup: missing task → exit 0"

test_summary
