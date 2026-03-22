#!/usr/bin/env bash
# test-analytical-pipeline.sh — Verify Phase 14 Analytical Pipeline structural requirements
# Tests file existence, YAML structure, cross-reference consistency, and constitutional compliance.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLES_DIR="$MOIRA_HOME/core/rules/roles"
QUALITY_DIR="$MOIRA_HOME/core/rules/quality"
PIPELINES_DIR="$MOIRA_HOME/core/pipelines"

echo "=== Analytical Pipeline Structural Tests ==="

# ── Pipeline YAML exists and has required sections ────────────────────
assert_file_exists "$PIPELINES_DIR/analytical.yaml" "analytical.yaml exists"

if [[ -f "$PIPELINES_DIR/analytical.yaml" ]]; then
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^_meta:" "analytical.yaml has _meta section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^steps:" "analytical.yaml has steps section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^agent_map:" "analytical.yaml has agent_map section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^organize_map:" "analytical.yaml has organize_map section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^gates:" "analytical.yaml has gates section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^error_handlers:" "analytical.yaml has error_handlers section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^post:" "analytical.yaml has post section"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "quality_gates:" "analytical.yaml has quality_gates field"

  # All 9 steps present
  for step_id in classification gather scope analysis depth_checkpoint organize synthesis review completion; do
    assert_file_contains "$PIPELINES_DIR/analytical.yaml" "id: ${step_id}" "analytical.yaml has step: ${step_id}"
  done

  # All 4 gates present
  for gate_id in classification_gate scope_gate depth_checkpoint_gate final_gate; do
    assert_file_contains "$PIPELINES_DIR/analytical.yaml" "id: ${gate_id}" "analytical.yaml has gate: ${gate_id}"
  done

  # Depth checkpoint gate has branching and all 5 options
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "branching: true" "analytical.yaml depth_checkpoint_gate has branching: true"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "repeating: true" "analytical.yaml depth_checkpoint_gate has repeating: true"
  for option in sufficient deepen redirect details abort; do
    assert_file_contains "$PIPELINES_DIR/analytical.yaml" "id: ${option}" "analytical.yaml has gate option: ${option}"
  done

  # Agent map covers all 6 subtypes
  for subtype in research design audit weakness decision documentation; do
    assert_file_contains "$PIPELINES_DIR/analytical.yaml" "^  ${subtype}:" "analytical.yaml agent_map has subtype: ${subtype}"
  done

  # Organize map has default + documentation
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "default: metis" "analytical.yaml organize_map has default: metis"
  assert_file_contains "$PIPELINES_DIR/analytical.yaml" "documentation: athena" "analytical.yaml organize_map has documentation: athena"
fi

# ── QA1-QA4 YAML files exist and have correct structure ──────────────
for qa in qa1-scope-completeness qa2-evidence-quality qa3-actionability qa4-analytical-rigor; do
  assert_file_exists "$QUALITY_DIR/${qa}.yaml" "quality gate ${qa}.yaml exists"
  if [[ -f "$QUALITY_DIR/${qa}.yaml" ]]; then
    assert_file_contains "$QUALITY_DIR/${qa}.yaml" "^_meta:" "${qa}: has _meta section"
    assert_file_contains "$QUALITY_DIR/${qa}.yaml" "^items:" "${qa}: has items section"
    assert_file_contains "$QUALITY_DIR/${qa}.yaml" "on_missing:" "${qa}: has on_missing"
    assert_file_contains "$QUALITY_DIR/${qa}.yaml" "agent: themis" "${qa}: assigned to themis"
    assert_file_contains "$QUALITY_DIR/${qa}.yaml" "pipeline_step: review" "${qa}: at review step"
  fi
done

# ── Calliope role definition ─────────────────────────────────────────
assert_file_exists "$ROLES_DIR/calliope.yaml" "calliope.yaml exists"

if [[ -f "$ROLES_DIR/calliope.yaml" ]]; then
  assert_file_contains "$ROLES_DIR/calliope.yaml" "role: scribe" "calliope: role is scribe"
  assert_file_contains "$ROLES_DIR/calliope.yaml" "budget: 80000" "calliope: budget is 80000"
  assert_file_contains "$ROLES_DIR/calliope.yaml" "^identity:" "calliope: has identity"
  assert_file_contains "$ROLES_DIR/calliope.yaml" "^capabilities:" "calliope: has capabilities"
  assert_file_contains "$ROLES_DIR/calliope.yaml" "^never:" "calliope: has never section"
  assert_file_contains "$ROLES_DIR/calliope.yaml" "^knowledge_access:" "calliope: has knowledge_access"
  assert_file_contains "$ROLES_DIR/calliope.yaml" "response_format:" "calliope: has response_format"

  # Count NEVER constraints (should be 7)
  never_count=$(grep -c '"Never ' "$ROLES_DIR/calliope.yaml" 2>/dev/null || echo "0")
  if [[ "$never_count" -ge 7 ]]; then
    pass "calliope: has >= 7 NEVER constraints ($never_count)"
  else
    fail "calliope: has $never_count NEVER constraints (expected >= 7)"
  fi
fi

# ── state.sh contains all 17 step IDs ────────────────────────────────
STATE_SH="$SRC_DIR/global/lib/state.sh"
if [[ -f "$STATE_SH" ]]; then
  for step in classification exploration analysis architecture plan implementation review testing reflection decomposition integration completion gather scope depth_checkpoint organize synthesis; do
    if grep -q "valid_steps=.*${step}" "$STATE_SH" 2>/dev/null; then
      pass "state.sh: valid_steps contains ${step}"
    else
      fail "state.sh: valid_steps missing ${step}"
    fi
  done
fi

# ── budget.sh contains scribe default ────────────────────────────────
BUDGET_SH="$SRC_DIR/global/lib/budget.sh"
if [[ -f "$BUDGET_SH" ]]; then
  assert_file_contains "$BUDGET_SH" "_MOIRA_BUDGET_DEFAULTS_scribe=80000" "budget.sh: has scribe default"
fi

# ── Apollo response format includes mode= field ─────────────────────
if [[ -f "$ROLES_DIR/apollo.yaml" ]]; then
  assert_file_contains "$ROLES_DIR/apollo.yaml" "mode=" "apollo.yaml: response format includes mode= field"
  assert_file_contains "$ROLES_DIR/apollo.yaml" "analytical_signals:" "apollo.yaml: has analytical_signals section"
fi

# ── Knowledge access matrix includes calliope ────────────────────────
MATRIX="$MOIRA_HOME/core/knowledge-access-matrix.yaml"
if [[ -f "$MATRIX" ]]; then
  assert_file_contains "$MATRIX" "calliope:" "knowledge-access-matrix: includes calliope"
fi

# ── Cross-reference manifest updated ─────────────────────────────────
XREF="$SRC_DIR/global/core/xref-manifest.yaml"
if [[ -f "$XREF" ]]; then
  assert_file_contains "$XREF" "scribe=80000" "xref-manifest: xref-001 includes scribe budget"
  assert_file_contains "$XREF" "gather" "xref-manifest: xref-002 includes gather step"
  assert_file_contains "$XREF" "calliope" "xref-manifest: xref-003 includes calliope"
  assert_file_contains "$XREF" "scope_gate" "xref-manifest: xref-006 includes scope_gate"
  assert_file_contains "$XREF" "depth_checkpoint_gate" "xref-manifest: xref-006 includes depth_checkpoint_gate"
fi

# ── Agent analytical_mode sections ───────────────────────────────────
for agent in athena metis argus themis; do
  if [[ -f "$ROLES_DIR/${agent}.yaml" ]]; then
    assert_file_contains "$ROLES_DIR/${agent}.yaml" "analytical_mode:" "${agent}.yaml: has analytical_mode section"
  fi
done

# ── Calliope should NOT have analytical_mode (its default IS analytical) ──
if [[ -f "$ROLES_DIR/calliope.yaml" ]]; then
  if grep -q "analytical_mode:" "$ROLES_DIR/calliope.yaml" 2>/dev/null; then
    fail "calliope.yaml: should NOT have analytical_mode section (default instructions ARE analytical)"
  else
    pass "calliope.yaml: correctly lacks analytical_mode section"
  fi
fi

# ── graph.sh contains analytical baseline function ───────────────────
GRAPH_SH="$SRC_DIR/global/lib/graph.sh"
if [[ -f "$GRAPH_SH" ]]; then
  assert_file_contains "$GRAPH_SH" "moira_graph_analytical_baseline" "graph.sh: has moira_graph_analytical_baseline function"
  # S-1: Verify graceful degradation when Ariadne binary not found (D-102)
  assert_file_contains "$GRAPH_SH" "command -v ariadne" "graph.sh: analytical baseline checks for ariadne binary (graceful degradation)"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASSES passed, $FAILURES failed ==="
if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
