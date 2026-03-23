#!/usr/bin/env bash
# test-orchestrator-enforcement.sh — Verify orchestrator enforcement fixes (D-134 task-002)
# Tests classification validation, step enforcement, post-pipeline terminal state, and schema updates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLES_DIR="$SRC_DIR/global/core/rules/roles"
SKILLS_DIR="$SRC_DIR/global/skills"
SCHEMAS_DIR="$SRC_DIR/schemas"

echo "=== Orchestrator Enforcement Structural Tests ==="

# ── Test Group 1: Classification Validation (Issue B) ────────────────

echo ""
echo "--- Classification Validation ---"

assert_file_contains "$ROLES_DIR/apollo.yaml" "^valid_values:" \
  "apollo.yaml contains valid_values block"

assert_file_contains "$ROLES_DIR/apollo.yaml" "size: \[small, medium, large, epic\]" \
  "apollo.yaml valid_values has size enum"

assert_file_contains "$ROLES_DIR/apollo.yaml" "mode: \[implementation, analytical\]" \
  "apollo.yaml valid_values has mode enum"

assert_file_contains "$ROLES_DIR/apollo.yaml" "confidence: \[high, low\]" \
  "apollo.yaml valid_values has confidence enum"

assert_file_contains "$ROLES_DIR/apollo.yaml" "subtype: \[research, design, audit, weakness, decision, documentation\]" \
  "apollo.yaml valid_values has subtype enum with all 6 values"

assert_file_contains "$ROLES_DIR/apollo.yaml" "MUST use ONLY these values" \
  "apollo.yaml identity contains MUST use ONLY these values"

assert_file_contains "$ROLES_DIR/apollo.yaml" "size=<small|medium|large|epic>" \
  "apollo.yaml response_format contains size enum format"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Step 1b: Classification Validation" \
  "orchestrator.md contains Step 1b: Classification Validation"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Normalize all parsed values to lowercase" \
  "orchestrator.md contains normalize-to-lowercase instruction"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "NEVER silently map an unknown value to a default" \
  "orchestrator.md contains NEVER silently map instruction"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "E6-AGENT" \
  "orchestrator.md Step 1b references E6-AGENT for invalid values"

# ── Test Group 2: Step Enforcement (Issue C) ─────────────────────────

echo ""
echo "--- Step Enforcement ---"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Step Completion Tracking" \
  "orchestrator.md contains Step Completion Tracking subsection"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "analytical.completed_steps\[\]" \
  "orchestrator.md contains analytical.completed_steps[] reference"

# All 7 required analytical steps referenced
for step in gather scope analysis depth_checkpoint organize synthesis review; do
  assert_file_contains "$SKILLS_DIR/orchestrator.md" "$step" \
    "orchestrator.md references required step: $step"
done

assert_file_contains "$SKILLS_DIR/orchestrator.md" "STEP ENFORCEMENT" \
  "orchestrator.md contains pre-final-gate STEP ENFORCEMENT validation"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "EVERY STEP IS MANDATORY" \
  "orchestrator.md contains step-skipping anti-rationalization"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "THEMIS DECIDES QUALITY, NOT YOU" \
  "orchestrator.md contains THEMIS DECIDES QUALITY, NOT YOU"

# ── Test Group 3: Post-Pipeline Terminal State (Issue A) ─────────────

echo ""
echo "--- Post-Pipeline Terminal State ---"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Post-Pipeline State" \
  "orchestrator.md contains Post-Pipeline State subsection"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "TERMINAL state" \
  "orchestrator.md contains TERMINAL state"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Do NOT dispatch any agents" \
  "orchestrator.md contains Do NOT dispatch any agents"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Do NOT interpret user instructions as pipeline continuation" \
  "orchestrator.md contains Do NOT interpret as pipeline continuation"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "CREATE A NEW TASK" \
  "orchestrator.md contains phase-transition anti-rationalization"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "EVERY PHASE IS A SEPARATE PIPELINE" \
  "orchestrator.md contains EVERY PHASE IS A SEPARATE PIPELINE"

assert_file_contains "$SKILLS_DIR/completion.md" "Phase 3: Actionable Findings Recommendation" \
  "completion.md contains Phase 3: Actionable Findings Recommendation"

assert_file_contains "$SKILLS_DIR/completion.md" 'pipeline_type == "analytical"' \
  "completion.md contains pipeline_type == analytical check"

# ── Test Group 4: Schema Update ──────────────────────────────────────

echo ""
echo "--- Schema Update ---"

assert_file_contains "$SCHEMAS_DIR/current.schema.yaml" "analytical.completed_steps" \
  "current.schema.yaml contains analytical.completed_steps"

assert_file_contains "$SCHEMAS_DIR/current.schema.yaml" "type: array" \
  "current.schema.yaml completed_steps has type: array"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
test_summary
