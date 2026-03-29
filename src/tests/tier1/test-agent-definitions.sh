#!/usr/bin/env bash
# test-agent-definitions.sh — Verify Phase 2 agent definitions
# Tests structural requirements, constitutional compliance, knowledge matrix consistency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLES_DIR="$MOIRA_HOME/core/rules/roles"
QUALITY_DIR="$MOIRA_HOME/core/rules/quality"
AGENTS=(apollo hermes athena metis daedalus hephaestus themis aletheia mnemosyne argus calliope)

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

# ── Specific constitutional checks (search only never: section) ─────
# Helper: extract never: section from role file (macOS compatible)
extract_never_section() {
  sed -n '/^never:/,/^[^ ]/p' "$1" | sed '$d'
}

# Explorer (hermes): never propose/solution/recommend
if extract_never_section "$ROLES_DIR/hermes.yaml" | grep -q "propose\|solution\|recommend"; then
  pass "hermes: never section contains propose/solution/recommend"
else
  fail "hermes: never section missing propose/solution/recommend"
fi

# Implementer (hephaestus): never decision/feature
if extract_never_section "$ROLES_DIR/hephaestus.yaml" | grep -q "decision\|feature"; then
  pass "hephaestus: never section contains decision/feature"
else
  fail "hephaestus: never section missing decision/feature"
fi

# Reviewer (themis): never fix/modify
if extract_never_section "$ROLES_DIR/themis.yaml" | grep -q "fix\|modify"; then
  pass "themis: never section contains fix/modify"
else
  fail "themis: never section missing fix/modify"
fi

# Reflector (mnemosyne): never change rules directly
if extract_never_section "$ROLES_DIR/mnemosyne.yaml" | grep -q "change rules directly"; then
  pass "mnemosyne: never section contains 'change rules directly'"
else
  fail "mnemosyne: never section missing 'change rules directly'"
fi

# ── Phase 4/5 tool guidance in agent roles ───────────────────────────
# Use source roles dir for Phase 4/5 checks (edits go to src/, not installed copy)
SRC_ROLES="$SRC_DIR/global/core/rules/roles"
if [[ ! -d "$SRC_ROLES" ]]; then
  SRC_ROLES="$ROLES_DIR"
fi

P45_TOOL_PAIRS="hermes:ariadne_symbol_search athena:ariadne_plan_impact daedalus:ariadne_context hephaestus:ariadne_symbols themis:ariadne_callers aletheia:ariadne_tests_for"

# Phase 8: expanded Ariadne integration — additional tool references per agent
P8_TOOL_PAIRS="hermes:ariadne_dependencies hermes:ariadne_cluster athena:ariadne_coupling themis:ariadne_diff themis:ariadne_cycles themis:ariadne_smells hephaestus:ariadne_callers hephaestus:ariadne_dependencies aletheia:ariadne_blast_radius aletheia:ariadne_callers"

for pair in $P45_TOOL_PAIRS; do
  agent="${pair%%:*}"
  expected_ref="${pair#*:}"
  role_file="$SRC_ROLES/${agent}.yaml"
  if [[ ! -f "$role_file" ]]; then
    role_file="$ROLES_DIR/${agent}.yaml"
  fi
  if grep -q "$expected_ref" "$role_file" 2>/dev/null; then
    pass "phase4/5: ${agent} references $expected_ref"
  else
    fail "phase4/5: ${agent} missing $expected_ref"
  fi
done

for pair in $P8_TOOL_PAIRS; do
  agent="${pair%%:*}"
  expected_ref="${pair#*:}"
  role_file="$SRC_ROLES/${agent}.yaml"
  if [[ ! -f "$role_file" ]]; then
    role_file="$ROLES_DIR/${agent}.yaml"
  fi
  if grep -q "$expected_ref" "$role_file" 2>/dev/null; then
    pass "phase8: ${agent} references $expected_ref"
  else
    fail "phase8: ${agent} missing $expected_ref"
  fi
done

# ── Regression: all agent YAMLs still have never: block ──────────────
for agent in "${AGENTS[@]}"; do
  role_file="$ROLES_DIR/${agent}.yaml"
  [[ -f "$role_file" ]] || continue
  if grep -q "^never:" "$role_file" 2>/dev/null; then
    never_count=$(grep -c '"Never ' "$role_file" 2>/dev/null || echo "0")
    if [[ "$never_count" -ge 3 ]]; then
      pass "regression: ${agent} never: block intact ($never_count constraints)"
    else
      fail "regression: ${agent} never: block degraded ($never_count constraints, need >= 3)"
    fi
  else
    fail "regression: ${agent} missing never: block entirely"
  fi
done

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
# Check each role file's knowledge_access matches the matrix row (all 4 dimensions)
KNOWLEDGE_DIMS=(project_model conventions decisions patterns graph)

for agent in "${AGENTS[@]}"; do
  role_file="$ROLES_DIR/${agent}.yaml"
  [[ -f "$role_file" && -f "$matrix_file" ]] || continue

  for dim in "${KNOWLEDGE_DIMS[@]}"; do
    # Extract value from role file (under knowledge_access: block), strip YAML comments
    role_val=$(sed -n '/^knowledge_access:/,/^[^ ]/{ /'"$dim"':/p; }' "$role_file" | sed 's/#.*//' | sed 's/.*'"$dim"': *//' | tr -d ' ')
    # Extract value from matrix (inline YAML format) — only from read_access section
    matrix_val=$(sed -n '/^read_access:/,/^[a-z]/{ /^  '"${agent}"':/p; }' "$matrix_file" | grep -o "${dim}: *[A-Za-z0-9]*" | sed 's/.*: *//' | tr -d ' ')

    if [[ "$role_val" == "$matrix_val" ]]; then
      pass "${agent}: knowledge_access.${dim} matches matrix ($role_val)"
    else
      fail "${agent}: knowledge_access.${dim} mismatch: role=$role_val, matrix=$matrix_val"
    fi
  done
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
  # Q4 uses sections: with nested items:, others use top-level items:
  if [[ "$qfile" == "q4-correctness" ]]; then
    assert_file_contains "$qpath" "^sections:" "${qfile}: has sections structure"
  else
    assert_file_contains "$qpath" "^items:" "${qfile}: has items section"
  fi
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
