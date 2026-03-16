#!/usr/bin/env bash
# test-epic.sh — Verify epic/task queue system artifacts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"

# ── epic.sh existence ────────────────────────────────────────────────
assert_file_exists "$SRC_DIR/global/lib/epic.sh" "epic.sh exists in src"
assert_file_exists "$MOIRA_HOME/lib/epic.sh" "epic.sh exists in MOIRA_HOME"

# ── epic.sh functions ────────────────────────────────────────────────
for func in moira_epic_parse_queue moira_epic_validate_dag moira_epic_next_tasks moira_epic_update_progress moira_epic_check_dependencies; do
  if grep -q "$func" "$SRC_DIR/global/lib/epic.sh" 2>/dev/null; then
    pass "epic.sh defines $func"
  else
    fail "epic.sh missing function: $func"
  fi
done

# ── epic.sh syntax ──────────────────────────────────────────────────
if bash -n "$SRC_DIR/global/lib/epic.sh" 2>/dev/null; then
  pass "epic.sh has valid bash syntax"
else
  fail "epic.sh has syntax errors"
fi

# ── queue.schema.yaml ────────────────────────────────────────────────
queue_schema="$MOIRA_HOME/schemas/queue.schema.yaml"
if [[ ! -f "$queue_schema" ]]; then
  queue_schema="$SRC_DIR/global/schemas/queue.schema.yaml"
fi
assert_file_exists "$queue_schema" "queue.schema.yaml exists"
assert_file_contains "$queue_schema" "epic_id" "queue schema has epic_id field"
assert_file_contains "$queue_schema" "tasks" "queue schema has tasks field"
assert_file_contains "$queue_schema" "progress" "queue schema has progress field"

# ── decomposition.yaml references repeatable_group ───────────────────
decomp_yaml="$MOIRA_HOME/core/pipelines/decomposition.yaml"
if [[ ! -f "$decomp_yaml" ]]; then
  decomp_yaml="$SRC_DIR/global/core/pipelines/decomposition.yaml"
fi
assert_file_exists "$decomp_yaml" "decomposition.yaml exists"
assert_file_contains "$decomp_yaml" "repeatable_group" "decomposition.yaml references repeatable_group"

test_summary
