#!/usr/bin/env bash
# test-install.sh — Verify install.sh works correctly
# Uses temp HOME to avoid polluting real home directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create temp directory for test HOME
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Override HOME and MOIRA_HOME for testing
export HOME="$TEST_HOME"
export MOIRA_HOME="$TEST_HOME/.claude/moira"

# ── Test: clean install ───────────────────────────────────────────────
output=$(bash "$SRC_DIR/install.sh" 2>&1) || true

assert_file_exists "$MOIRA_HOME/.version" "clean install: .version exists"
assert_dir_exists "$MOIRA_HOME/lib" "clean install: lib/ exists"
assert_file_exists "$MOIRA_HOME/lib/yaml-utils.sh" "clean install: yaml-utils.sh exists"
assert_file_exists "$MOIRA_HOME/lib/state.sh" "clean install: state.sh exists"
assert_file_exists "$MOIRA_HOME/lib/scaffold.sh" "clean install: scaffold.sh exists"
assert_file_exists "$MOIRA_HOME/lib/task-id.sh" "clean install: task-id.sh exists"
assert_dir_exists "$TEST_HOME/.claude/commands/moira" "clean install: commands dir exists"
assert_file_exists "$TEST_HOME/.claude/commands/moira/help.md" "clean install: help.md exists"
assert_dir_exists "$MOIRA_HOME/schemas" "clean install: schemas dir exists"

# Phase 4: knowledge.sh and rules.sh
assert_file_exists "$MOIRA_HOME/lib/knowledge.sh" "clean install: knowledge.sh exists"
assert_file_exists "$MOIRA_HOME/lib/rules.sh" "clean install: rules.sh exists"

# Phase 4: knowledge.sh and rules.sh syntax valid
for lib in knowledge.sh rules.sh; do
  if bash -n "$MOIRA_HOME/lib/$lib" 2>/dev/null; then
    pass "clean install: $lib syntax valid"
  else
    fail "clean install: $lib has syntax errors"
  fi
done

# Phase 4: knowledge templates
assert_dir_exists "$MOIRA_HOME/templates/knowledge" "clean install: knowledge templates dir exists"
template_count=$(find "$MOIRA_HOME/templates/knowledge" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$template_count" -ge 17 ]]; then
  pass "clean install: $template_count knowledge templates (>=17)"
else
  fail "clean install: expected >=17 knowledge templates, found $template_count"
fi

# Pipeline definitions
assert_dir_exists "$MOIRA_HOME/core/pipelines" "clean install: pipelines dir exists"
for pipeline in quick standard full decomposition; do
  assert_file_exists "$MOIRA_HOME/core/pipelines/${pipeline}.yaml" "clean install: ${pipeline}.yaml exists"
done

# Pipeline definitions contain gates section
for pipeline in quick standard full decomposition; do
  assert_file_contains "$MOIRA_HOME/core/pipelines/${pipeline}.yaml" "gates:" "clean install: ${pipeline}.yaml has gates section"
done

# Skill files
for skill in orchestrator gates dispatch errors; do
  assert_file_exists "$MOIRA_HOME/skills/${skill}.md" "clean install: skill ${skill}.md exists"
done

# Orchestrator skill is non-empty
if [[ -s "$MOIRA_HOME/skills/orchestrator.md" ]]; then
  pass "clean install: orchestrator.md is non-empty"
else
  fail "clean install: orchestrator.md is empty"
fi

# Telemetry schema
assert_file_exists "$MOIRA_HOME/schemas/telemetry.schema.yaml" "clean install: telemetry schema exists"

# Count command stubs
cmd_count=$(ls "$TEST_HOME/.claude/commands/moira/"*.md 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$cmd_count" "10" "clean install: 10 command stubs installed"

# ── Test: idempotency (re-run) ────────────────────────────────────────
output2=$(bash "$SRC_DIR/install.sh" 2>&1) || true
assert_file_exists "$MOIRA_HOME/.version" "re-install: .version still exists"
assert_file_exists "$MOIRA_HOME/lib/yaml-utils.sh" "re-install: yaml-utils.sh still exists"

if echo "$output2" | grep -q "Verification passed"; then
  pass "re-install: verification passes"
else
  fail "re-install: verification failed"
fi

# ── Test: overwrite/update ────────────────────────────────────────────
echo "# modified" >> "$MOIRA_HOME/lib/yaml-utils.sh"
bash "$SRC_DIR/install.sh" 2>&1 > /dev/null || true
if grep -q "# modified" "$MOIRA_HOME/lib/yaml-utils.sh"; then
  fail "overwrite: modified file was NOT overwritten"
else
  pass "overwrite: modified file was overwritten (update works)"
fi

# ── Test: scaffold_project ────────────────────────────────────────────
source "$MOIRA_HOME/lib/scaffold.sh"
test_project="$TEST_HOME/test-project"
mkdir -p "$test_project"
moira_scaffold_project "$test_project"

assert_dir_exists "$test_project/.claude/moira/core/rules/roles" "scaffold: core/rules/roles"
assert_dir_exists "$test_project/.claude/moira/project/rules" "scaffold: project/rules"
assert_dir_exists "$test_project/.claude/moira/config" "scaffold: config"
assert_dir_exists "$test_project/.claude/moira/knowledge/project-model" "scaffold: knowledge/project-model"
assert_dir_exists "$test_project/.claude/moira/knowledge/conventions" "scaffold: knowledge/conventions"
assert_dir_exists "$test_project/.claude/moira/knowledge/decisions/archive" "scaffold: knowledge/decisions/archive"
assert_dir_exists "$test_project/.claude/moira/knowledge/patterns" "scaffold: knowledge/patterns"
assert_dir_exists "$test_project/.claude/moira/knowledge/patterns/archive" "scaffold: knowledge/patterns/archive"
assert_dir_exists "$test_project/.claude/moira/knowledge/failures" "scaffold: knowledge/failures"
assert_dir_exists "$test_project/.claude/moira/knowledge/quality-map" "scaffold: knowledge/quality-map"
assert_dir_exists "$test_project/.claude/moira/state/tasks" "scaffold: state/tasks"
assert_dir_exists "$test_project/.claude/moira/state/metrics" "scaffold: state/metrics"
assert_dir_exists "$test_project/.claude/moira/state/audits" "scaffold: state/audits"
assert_dir_exists "$test_project/.claude/moira/hooks" "scaffold: hooks"

# Idempotency: run scaffold again
moira_scaffold_project "$test_project"
assert_dir_exists "$test_project/.claude/moira/state/tasks" "scaffold idempotent: state/tasks still exists"

# ── Test: task-id generation ──────────────────────────────────────────
source "$MOIRA_HOME/lib/task-id.sh"
state_dir="$test_project/.claude/moira/state"

# First ID of the day
id1=$(moira_task_id "$state_dir")
today=$(date +%Y-%m-%d)
assert_equals "$id1" "task-${today}-001" "task-id: first ID is 001"

# Create directory for first task, generate second
mkdir -p "$state_dir/tasks/$id1"
id2=$(moira_task_id "$state_dir")
assert_equals "$id2" "task-${today}-002" "task-id: second ID is 002"

# Create second, generate third
mkdir -p "$state_dir/tasks/$id2"
id3=$(moira_task_id "$state_dir")
assert_equals "$id3" "task-${today}-003" "task-id: third ID is 003"

test_summary
