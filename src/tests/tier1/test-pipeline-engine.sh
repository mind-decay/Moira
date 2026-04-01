#!/usr/bin/env bash
# test-pipeline-engine.sh — Structural verification for Phase 3 Pipeline Engine
# Tests pipeline definitions, gate integrity, orchestrator purity, and state tracking.
# Source: design/specs/2026-03-11-phase3-pipeline-engine.md → D9

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPELINES_DIR="$SRC_DIR/global/core/pipelines"
SKILLS_DIR="$SRC_DIR/global/skills"

# ── Test: Pipeline files exist ──────────────────────────────────────
for pipeline in quick standard full decomposition; do
  assert_file_exists "$PIPELINES_DIR/${pipeline}.yaml" "pipeline ${pipeline}.yaml exists"
done

# ── Test: Pipeline selection is pure function (Art 2.1) ─────────────
# quick.yaml: trigger must be small + high
assert_file_contains "$PIPELINES_DIR/quick.yaml" "size: small" "quick: trigger size=small"
assert_file_contains "$PIPELINES_DIR/quick.yaml" "confidence: high" "quick: trigger confidence=high"

# standard.yaml: trigger must be medium
assert_file_contains "$PIPELINES_DIR/standard.yaml" "size: medium" "standard: trigger size=medium"

# standard.yaml: alternate trigger for small+low
assert_file_contains "$PIPELINES_DIR/standard.yaml" "confidence: low" "standard: alternate trigger confidence=low"

# full.yaml: trigger must be large
assert_file_contains "$PIPELINES_DIR/full.yaml" "size: large" "full: trigger size=large"

# decomposition.yaml: trigger must be epic
assert_file_contains "$PIPELINES_DIR/decomposition.yaml" "size: epic" "decomposition: trigger size=epic"

# ── Test: Gate completeness per pipeline (Art 2.2) ──────────────────
# Count gates in each pipeline
quick_gates=$(grep -c "^  - id:" "$PIPELINES_DIR/quick.yaml" 2>/dev/null || echo 0)
# Quick gates section only — count lines matching gate id under gates:
quick_gate_count=$(awk '/^gates:/{found=1} found && /^  - id:/{count++} /^[a-z]/ && !/^gates:/ && found{exit} END{print count+0}' "$PIPELINES_DIR/quick.yaml")
if [[ "$quick_gate_count" -ge 2 ]]; then
  pass "quick pipeline has >= 2 gates ($quick_gate_count)"
else
  fail "quick pipeline has < 2 gates ($quick_gate_count)"
fi

standard_gate_count=$(awk '/^gates:/{found=1} found && /^  - id:/{count++} /^[a-z]/ && !/^gates:/ && found{exit} END{print count+0}' "$PIPELINES_DIR/standard.yaml")
if [[ "$standard_gate_count" -ge 4 ]]; then
  pass "standard pipeline has >= 4 gates ($standard_gate_count)"
else
  fail "standard pipeline has < 4 gates ($standard_gate_count)"
fi

full_gate_count=$(awk '/^gates:/{found=1} found && /^  - id:/{count++} /^[a-z]/ && !/^gates:/ && found{exit} END{print count+0}' "$PIPELINES_DIR/full.yaml")
if [[ "$full_gate_count" -ge 5 ]]; then
  pass "full pipeline has >= 5 gates ($full_gate_count)"
else
  fail "full pipeline has < 5 gates ($full_gate_count)"
fi

decomp_gate_count=$(awk '/^gates:/{found=1} found && /^  - id:/{count++} /^[a-z]/ && !/^gates:/ && found{exit} END{print count+0}' "$PIPELINES_DIR/decomposition.yaml")
if [[ "$decomp_gate_count" -ge 4 ]]; then
  pass "decomposition pipeline has >= 4 gates ($decomp_gate_count)"
else
  fail "decomposition pipeline has < 4 gates ($decomp_gate_count)"
fi

# ── Test: No auto-proceed logic (Art 4.2) ───────────────────────────
auto_proceed_count=0
for f in "$PIPELINES_DIR"/*.yaml "$SKILLS_DIR"/*.md; do
  if [[ -f "$f" ]]; then
    count=$(grep -ci "auto_proceed\|auto_approve\|skip_gate\|auto_skip" "$f" 2>/dev/null || true)
    count=${count:-0}
    auto_proceed_count=$((auto_proceed_count + count))
  fi
done
if [[ "$auto_proceed_count" -eq 0 ]]; then
  pass "no auto-proceed/skip-gate patterns found"
else
  fail "found $auto_proceed_count auto-proceed/skip-gate patterns"
fi

# ── Test: No unauthorized conditional gate skip ─────────────────────
# D-193: conditional mid-point gates are allowed (required: false + condition:)
# What's NOT allowed: skip_if, when:, if_condition patterns that bypass required gates
conditional_skip=0
for f in "$PIPELINES_DIR"/*.yaml; do
  if [[ -f "$f" ]]; then
    count=$(grep -ci "skip_if\|when:\|if_condition" "$f" 2>/dev/null || true)
    count=${count:-0}
    conditional_skip=$((conditional_skip + count))
  fi
done
if [[ "$conditional_skip" -eq 0 ]]; then
  pass "no unauthorized conditional gate skip patterns in pipeline definitions"
else
  fail "found $conditional_skip unauthorized conditional gate skip patterns"
fi

# ── Test: Orchestrator purity (Art 1.1) ─────────────────────────────
# Orchestrator skill must NOT contain project file operations
if [[ -f "$SKILLS_DIR/orchestrator.md" ]]; then
  purity_violations=0
  for pattern in 'Read.*src/' 'Write.*src/' 'Edit.*src/' 'Grep.*src/' 'Glob.*src/'; do
    count=$(grep -c "$pattern" "$SKILLS_DIR/orchestrator.md" 2>/dev/null || true)
    count=${count:-0}
    purity_violations=$((purity_violations + count))
  done
  if [[ "$purity_violations" -eq 0 ]]; then
    pass "orchestrator skill has no project file operations"
  else
    fail "orchestrator skill has $purity_violations project file operation patterns"
  fi
else
  fail "orchestrator.md not found"
fi

# ── Test: State write per step ──────────────────────────────────────
# Every step in pipeline definitions must have a writes_to field
for pipeline in quick standard full decomposition; do
  f="$PIPELINES_DIR/${pipeline}.yaml"
  # Count step entries (lines with "- id:" under steps section)
  step_count=$(awk '/^steps:/{found=1} found && /^  - id:/{count++} /^[a-z]/ && !/^steps:/ && found{exit} END{print count+0}' "$f")
  # Count writes_to entries in steps section (before gates:)
  writes_count=$(awk '/^steps:/{found=1} found && /writes_to:/{count++} /^gates:/{exit} END{print count+0}' "$f")
  if [[ "$writes_count" -ge "$step_count" && "$step_count" -gt 0 ]]; then
    pass "${pipeline}: all ${step_count} steps have writes_to fields"
  else
    fail "${pipeline}: writes_to count ($writes_count) < step count ($step_count)"
  fi
done

# ── Test: Error recovery has display ────────────────────────────────
# Each required error type (E1-E6) must have its own Display section
if [[ -f "$SKILLS_DIR/errors.md" ]]; then
  for error_type in E1-INPUT E2-SCOPE E3-CONFLICT E5-QUALITY E6-AGENT; do
    # Check that the error type section exists AND has a Display subsection
    if awk "/^## ${error_type}/{found=1} found && /### Display/{ok=1; exit} /^## E[0-9]/ && found && !/^## ${error_type}/{exit} END{exit !ok}" "$SKILLS_DIR/errors.md"; then
      pass "errors.md: ${error_type} has Display section"
    else
      fail "errors.md: ${error_type} missing Display section"
    fi
  done
else
  fail "errors.md not found"
fi

# ── Test: Budget report at completion ───────────────────────────────
if [[ -f "$SKILLS_DIR/orchestrator.md" ]]; then
  if grep -qi "budget report" "$SKILLS_DIR/orchestrator.md" 2>/dev/null; then
    pass "orchestrator mentions budget report in completion flow"
  else
    fail "orchestrator does not mention budget report"
  fi
else
  fail "orchestrator.md not found"
fi

# ── Test: All gates have required: true (conditional gates allowed, D-193) ──
for pipeline in quick standard full decomposition; do
  required_count=$(grep -c "required: true" "$PIPELINES_DIR/${pipeline}.yaml" 2>/dev/null || echo 0)
  conditional_count=$(grep -c "required: false" "$PIPELINES_DIR/${pipeline}.yaml" 2>/dev/null || echo 0)
  gate_count=$(awk '/^gates:/{found=1} found && /^  - id:/{count++} /^[a-z]/ && !/^gates:/ && found{exit} END{print count+0}' "$PIPELINES_DIR/${pipeline}.yaml")
  total_accounted=$((required_count + conditional_count))
  if [[ "$total_accounted" -ge "$gate_count" ]]; then
    pass "${pipeline}: all gates have required field ($required_count required, $conditional_count conditional)"
  else
    fail "${pipeline}: not all gates have required field ($total_accounted/$gate_count)"
  fi
done

# ── Test: Skill files exist ─────────────────────────────────────────
for skill in orchestrator gates dispatch errors; do
  assert_file_exists "$SKILLS_DIR/${skill}.md" "skill ${skill}.md exists"
done

# ── Test: Telemetry schema exists ───────────────────────────────────
assert_file_exists "$SRC_DIR/schemas/telemetry.schema.yaml" "telemetry schema exists"
assert_file_contains "$SRC_DIR/schemas/telemetry.schema.yaml" "_meta:" "telemetry schema has _meta"
assert_file_contains "$SRC_DIR/schemas/telemetry.schema.yaml" "fields:" "telemetry schema has fields"

test_summary
