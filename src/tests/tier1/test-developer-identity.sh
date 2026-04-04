#!/usr/bin/env bash
# test-developer-identity.sh — Tier 1 tests for developer identity in task state (D-225)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Developer Identity (D-225)"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

source "$SRC_DIR/global/lib/task-init.sh"
set +e

# ── Setup: git repo ──
PROJECT="$TEMP_DIR/project"
mkdir -p "$PROJECT/.moira/state/tasks"
cd "$PROJECT"
git init -q
git config user.name "Alice Wonderland"
git config user.email "alice@test.com"

# ── 1. Git name used ──
task_id=$(moira_task_init "test task" "" "$PROJECT/.moira/state" 2>/dev/null)
status_file="$PROJECT/.moira/state/tasks/${task_id}/status.yaml"
manifest_file="$PROJECT/.moira/state/tasks/${task_id}/manifest.yaml"

if grep -q 'developer: "Alice Wonderland"' "$status_file" 2>/dev/null; then
  pass "git name: developer field in status.yaml"
else
  fail "git name: expected 'Alice Wonderland' in status.yaml, got: $(grep developer "$status_file" 2>/dev/null)"
fi

if grep -q 'developer: "Alice Wonderland"' "$manifest_file" 2>/dev/null; then
  pass "git name: developer field in manifest.yaml"
else
  fail "git name: expected 'Alice Wonderland' in manifest.yaml"
fi

# ── 2. Empty git name → $USER fallback ──
git config user.name ""
# Clean up previous task state for fresh init
rm -f "$PROJECT/.moira/state/current.yaml"
task_id2=$(moira_task_init "test task 2" "" "$PROJECT/.moira/state" 2>/dev/null)
status_file2="$PROJECT/.moira/state/tasks/${task_id2}/status.yaml"
dev_name=$(grep '^developer:' "$status_file2" 2>/dev/null | sed 's/developer:[[:space:]]*//' | tr -d '"')
if [[ "$dev_name" == "$USER" ]]; then
  pass "empty git name: falls back to \$USER"
else
  fail "empty git name: expected '$USER', got '$dev_name'"
fi

# ── 3. No git repo but global gitconfig → uses global name or $USER ──
NOGIT="$TEMP_DIR/nogit"
mkdir -p "$NOGIT/.moira/state/tasks"
cd "$NOGIT"
# Not a git repo — git config user.name reads global config (if set)
task_id3=$(moira_task_init "test task 3" "" "$NOGIT/.moira/state" 2>/dev/null)
status_file3="$NOGIT/.moira/state/tasks/${task_id3}/status.yaml"
dev_name3=$(grep '^developer:' "$status_file3" 2>/dev/null | sed 's/developer:[[:space:]]*//' | tr -d '"')
if [[ -n "$dev_name3" && "$dev_name3" != "developer:" ]]; then
  pass "no git repo: developer field populated (from global config or \$USER)"
else
  fail "no git repo: developer should be non-empty, got '$dev_name3'"
fi

# ── 4. Developer in both status.yaml and manifest.yaml ──
assert_file_contains "$PROJECT/.moira/state/tasks/${task_id}/status.yaml" "developer:" "status.yaml has developer field"
assert_file_contains "$PROJECT/.moira/state/tasks/${task_id}/manifest.yaml" "developer:" "manifest.yaml has developer field"

# ── 5. Developer name with special chars ──
cd "$PROJECT"
git config user.name "O'Brien (Dev)"
rm -f "$PROJECT/.moira/state/current.yaml"
task_id5=$(moira_task_init "test task 5" "" "$PROJECT/.moira/state" 2>/dev/null)
status_file5="$PROJECT/.moira/state/tasks/${task_id5}/status.yaml"
if grep -q "O'Brien" "$status_file5" 2>/dev/null; then
  pass "special chars: developer name with apostrophe preserved"
else
  fail "special chars: apostrophe in name should be preserved"
fi

test_summary
