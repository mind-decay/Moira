#!/usr/bin/env bash
# test-agent-definitions.sh — Verify Phase 2 agent definitions
# Tests structural requirements, constitutional compliance, knowledge matrix consistency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
ROLES_DIR="$MOIRA_HOME/core/rules/roles"
QUALITY_DIR="$MOIRA_HOME/core/rules/quality"
AGENTS=(apollo hermes athena metis daedalus hephaestus themis aletheia mnemosyne argus)

# ── Base rules ───────────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/core/rules/base.yaml" "base.yaml exists"
assert_file_contains "$MOIRA_HOME/core/rules/base.yaml" "^inviolable:" "base.yaml has inviolable: section"

# Count inviolable rules (lines matching "- id: INV-")
if [[ -f "$MOIRA_HOME/core/rules/base.yaml" ]]; then
  inv_count=$(grep -c "id: INV-" "$MOIRA_HOME/core/rules/base.yaml" 2>/dev/null || echo "0")
  if [[ "$inv_count" -eq 7 ]]; then
    pass "base.yaml has all 7 inviolable rules"
  else
    fail "base.yaml has $inv_count inviolable rules (expected 7)"
  fi
fi

# ── All 10 role files exist ──────────────────────────────────────────
for agent in "${AGENTS[@]}"; do
  assert_file_exists "$ROLES_DIR/${agent}.yaml" "role ${agent}.yaml exists"
done

# ── Structural checks per role file ──────────────────────────────────
for agent in "${AGENTS[@]}"; do
  role_file="$ROLES_DIR/${agent}.yaml"
  [[ -f "$role_file" ]] || continue

  assert_file_contains "$role_file" "_meta:" "${agent}: has _meta section"
  assert_file_contains "$role_file" "role:" "${agent}: has _meta.role field"
  assert_file_contains "$role_file" "budget:" "${agent}: has _meta.budget field"
  assert_file_contains "$role_file" "^identity:" "${agent}: has identity field"
  assert_file_contains "$role_file" "^capabilities:" "${agent}: has capabilities section"
  assert_file_contains "$role_file" "^never:" "${agent}: has never section"
  assert_file_contains "$role_file" "^knowledge_access:" "${agent}: has knowledge_access section"
  assert_file_contains "$role_file" "response_format:" "${agent}: has response_format"
done

# ── Constitutional compliance (Art 1.2): ≥3 NEVER constraints ───────
for agent in "${AGENTS[@]}"; do
  role_file="$ROLES_DIR/${agent}.yaml"
  [[ -f "$role_file" ]] || continue

  # Count lines starting with "  - " inside never: section
  # Simple approach: count lines matching "Never" under never:
  never_count=$(grep -c '"Never ' "$role_file" 2>/dev/null || echo "0")
  if [[ "$never_count" -ge 3 ]]; then
    pass "${agent}: has ≥3 NEVER constraints ($never_count)"
  else
    fail "${agent}: has $never_count NEVER constraints (need ≥3)"
  fi
done

# ── Specific constitutional checks ──────────────────────────────────
# Explorer (hermes): never propose/solution/recommend
assert_file_contains "$ROLES_DIR/hermes.yaml" "propose\|solution\|recommend" "hermes: never contains propose/solution/recommend"

# Implementer (hephaestus): never decision/feature
assert_file_contains "$ROLES_DIR/hephaestus.yaml" "decision\|feature" "hephaestus: never contains decision/feature"

# Reviewer (themis): never fix/modify
assert_file_contains "$ROLES_DIR/themis.yaml" "fix\|modify" "themis: never contains fix/modify"

# Reflector (mnemosyne): never change rules directly
assert_file_contains "$ROLES_DIR/mnemosyne.yaml" "change rules directly" "mnemosyne: never contains 'change rules directly'"

# ── Knowledge access matrix ──────────────────────────────────────────
matrix_file="$MOIRA_HOME/core/knowledge-access-matrix.yaml"
assert_file_exists "$matrix_file" "knowledge-access-matrix.yaml exists"

if [[ -f "$matrix_file" ]]; then
  # Matrix has entries for all 10 agents
  for agent in "${AGENTS[@]}"; do
    assert_file_contains "$matrix_file" "^  ${agent}:" "matrix has entry for ${agent}"
  done
fi

# ── Knowledge access consistency: role files vs matrix ───────────────
# Check each role file's knowledge_access matches the matrix row
for agent in "${AGENTS[@]}"; do
  role_file="$ROLES_DIR/${agent}.yaml"
  [[ -f "$role_file" && -f "$matrix_file" ]] || continue

  # Extract project_model from role file
  role_pm=$(grep -A1 "^knowledge_access:" "$role_file" | grep "project_model:" | sed 's/.*: *//' | tr -d ' ')
  # Extract project_model from matrix
  matrix_pm=$(grep "^  ${agent}:" "$matrix_file" | sed 's/.*project_model: *//' | sed 's/,.*//' | tr -d ' ')

  if [[ "$role_pm" == "$matrix_pm" ]]; then
    pass "${agent}: knowledge_access.project_model matches matrix ($role_pm)"
  else
    fail "${agent}: knowledge_access.project_model mismatch: role=$role_pm, matrix=$matrix_pm"
  fi
done

# ── Quality checklists ──────────────────────────────────────────────
quality_files=(q1-completeness q2-soundness q3-feasibility q4-correctness q5-coverage)
for qfile in "${quality_files[@]}"; do
  assert_file_exists "$QUALITY_DIR/${qfile}.yaml" "quality ${qfile}.yaml exists"
done

for qfile in "${quality_files[@]}"; do
  qpath="$QUALITY_DIR/${qfile}.yaml"
  [[ -f "$qpath" ]] || continue

  assert_file_contains "$qpath" "agent:" "${qfile}: has _meta.agent field"
  assert_file_contains "$qpath" "items:" "${qfile}: has items section"
done

# ── Response contract ────────────────────────────────────────────────
contract_file="$MOIRA_HOME/core/response-contract.yaml"
assert_file_exists "$contract_file" "response-contract.yaml exists"

if [[ -f "$contract_file" ]]; then
  for status in success failure blocked budget_exceeded; do
    assert_file_contains "$contract_file" "$status:" "response-contract has status: $status"
  done
fi

test_summary
