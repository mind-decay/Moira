#!/usr/bin/env bash
# test-reflection-system.sh — Tier 1 structural verification for Phase 10 reflection engine
# Tests: reflection library, judge library, templates, skills, knowledge integration, telemetry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Reflection library ──────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/reflection.sh" "lib/reflection.sh exists"
if [[ -f "$MOIRA_HOME/lib/reflection.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/reflection.sh" 2>/dev/null; then
    pass "lib/reflection.sh syntax valid"
  else
    fail "lib/reflection.sh has syntax errors"
  fi
fi

# Check all 9 functions exist
if [[ -f "$MOIRA_HOME/lib/reflection.sh" ]]; then
  reflection_funcs=(
    moira_reflection_task_history
    moira_reflection_observation_count
    moira_reflection_get_observations
    moira_reflection_mcp_call_frequency
    moira_reflection_pending_proposals
    moira_reflection_record_proposal
    moira_reflection_resolve_proposal
    moira_reflection_deep_counter
    moira_reflection_auto_defer_stale
  )
  for func in "${reflection_funcs[@]}"; do
    if grep -q "^${func}()" "$MOIRA_HOME/lib/reflection.sh" 2>/dev/null || grep -q "^${func} ()" "$MOIRA_HOME/lib/reflection.sh" 2>/dev/null; then
      pass "function $func exists in reflection.sh"
    else
      fail "function $func not found in reflection.sh"
    fi
  done
fi

# ── Judge library ───────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/judge.sh" "lib/judge.sh exists"
if [[ -f "$MOIRA_HOME/lib/judge.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/judge.sh" 2>/dev/null; then
    pass "lib/judge.sh syntax valid"
  else
    fail "lib/judge.sh has syntax errors"
  fi
fi

if [[ -f "$MOIRA_HOME/lib/judge.sh" ]]; then
  judge_funcs=(
    moira_judge_invoke
    moira_judge_composite_score
    moira_judge_normalize_score
    moira_judge_calibrate
  )
  for func in "${judge_funcs[@]}"; do
    if grep -q "^${func}()" "$MOIRA_HOME/lib/judge.sh" 2>/dev/null || grep -q "^${func} ()" "$MOIRA_HOME/lib/judge.sh" 2>/dev/null; then
      pass "function $func exists in judge.sh"
    else
      fail "function $func not found in judge.sh"
    fi
  done
fi

# ── Reflection templates ────────────────────────────────────────────
for tmpl in lightweight standard deep epic; do
  assert_file_exists "$MOIRA_HOME/templates/reflection/${tmpl}.md" "reflection template ${tmpl}.md exists"
done

# ── Judge template ──────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/templates/judge/judge-prompt.md" "judge prompt template exists"

# ── Rubric files ────────────────────────────────────────────────────
for rubric in feature-implementation bugfix refactor; do
  assert_file_exists "$MOIRA_HOME/tests/bench/rubrics/${rubric}.yaml" "rubric ${rubric}.yaml exists"
done

# ── Calibration examples ────────────────────────────────────────────
for cal in good-implementation mediocre-implementation poor-implementation; do
  assert_dir_exists "$MOIRA_HOME/tests/bench/calibration/${cal}" "calibration ${cal}/ exists"
  assert_file_exists "$MOIRA_HOME/tests/bench/calibration/${cal}/expected.yaml" "calibration ${cal}/expected.yaml exists"
done

# ── Reflection skill ────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/skills/reflection.md" "reflection skill exists"

# ── Knowledge integration ───────────────────────────────────────────
if [[ -f "$MOIRA_HOME/core/knowledge-access-matrix.yaml" ]]; then
  for agent in mnemosyne hephaestus daedalus; do
    if grep -q "libraries:" "$MOIRA_HOME/core/knowledge-access-matrix.yaml" 2>/dev/null; then
      pass "knowledge-access-matrix.yaml has libraries dimension"
    else
      fail "knowledge-access-matrix.yaml missing libraries dimension"
    fi
  done
fi

if [[ -f "$MOIRA_HOME/lib/knowledge.sh" ]]; then
  if grep -q 'libraries' "$MOIRA_HOME/lib/knowledge.sh" 2>/dev/null; then
    pass "knowledge.sh includes libraries type"
  else
    fail "knowledge.sh missing libraries type"
  fi
fi

# ── Telemetry ───────────────────────────────────────────────────────
if [[ -f "$MOIRA_HOME/schemas/telemetry.schema.yaml" ]]; then
  if grep -q "mcp_calls:" "$MOIRA_HOME/schemas/telemetry.schema.yaml" 2>/dev/null; then
    pass "telemetry schema has mcp_calls section"
  else
    fail "telemetry schema missing mcp_calls section"
  fi
fi

# ── Integration ─────────────────────────────────────────────────────
# Mnemosyne role still has NEVER constraints
if [[ -f "$MOIRA_HOME/core/rules/roles/mnemosyne.yaml" ]]; then
  assert_file_contains "$MOIRA_HOME/core/rules/roles/mnemosyne.yaml" "NEVER" "mnemosyne.yaml has NEVER constraints"
fi

# Pipeline definitions have reflection field
for pipeline in quick standard full decomposition; do
  if [[ -f "$MOIRA_HOME/core/pipelines/${pipeline}.yaml" ]]; then
    if grep -q "reflection:" "$MOIRA_HOME/core/pipelines/${pipeline}.yaml" 2>/dev/null; then
      pass "${pipeline}.yaml has reflection field"
    else
      fail "${pipeline}.yaml missing reflection field"
    fi
  fi
done

# bench.sh sources judge.sh
if [[ -f "$MOIRA_HOME/lib/bench.sh" ]]; then
  assert_file_contains "$MOIRA_HOME/lib/bench.sh" "judge.sh" "bench.sh sources judge.sh"
fi

# health.md exists
assert_file_exists "$HOME/.claude/commands/moira/health.md" "health.md command exists"

# scaffold.sh creates state/reflection
if [[ -f "$MOIRA_HOME/lib/scaffold.sh" ]]; then
  assert_file_contains "$MOIRA_HOME/lib/scaffold.sh" "state/reflection" "scaffold.sh creates state/reflection"
fi

# orchestrator.md references reflection.md
if [[ -f "$MOIRA_HOME/skills/orchestrator.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "reflection.md" "orchestrator.md references reflection.md skill"
fi

# dispatch.md has Mnemosyne alternative path note
if [[ -f "$MOIRA_HOME/skills/dispatch.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "bypasses" "dispatch.md has Mnemosyne alternative path note"
fi

test_summary
