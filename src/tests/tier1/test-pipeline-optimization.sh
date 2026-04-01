#!/usr/bin/env bash
# test-pipeline-optimization.sh — Verify Phase 16 pipeline token optimization changes
# Tests D-189 through D-195: merged research, plan-check, embedded verify, paralysis guard, pipeline restructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLES_DIR="$MOIRA_HOME/core/rules/roles"
SRC_ROLES="$SRC_DIR/global/core/rules/roles"
QUALITY_DIR="$MOIRA_HOME/core/rules/quality"
SRC_QUALITY="$SRC_DIR/global/core/rules/quality"
PIPELINES_DIR="$MOIRA_HOME/core/pipelines"
SRC_PIPELINES="$SRC_DIR/global/core/pipelines"
SRC_SKILLS="$SRC_DIR/global/skills"

# Helper: prefer source dir, fallback to installed
role_file() { local f="$SRC_ROLES/$1.yaml"; [[ -f "$f" ]] && echo "$f" || echo "$ROLES_DIR/$1.yaml"; }
quality_file() { local f="$SRC_QUALITY/$1.yaml"; [[ -f "$f" ]] && echo "$f" || echo "$QUALITY_DIR/$1.yaml"; }
pipeline_file() { local f="$SRC_PIPELINES/$1.yaml"; [[ -f "$f" ]] && echo "$f" || echo "$PIPELINES_DIR/$1.yaml"; }

# ── D-189: Hermes gap analysis ───────────────────────────────────────
hermes="$(role_file hermes)"
assert_file_contains "$hermes" "gap_analysis:" "D-189: hermes has gap_analysis section"
assert_file_contains "$hermes" "Gap Analysis" "D-189: hermes gap_analysis mentions ## Gap Analysis"
assert_file_contains "$hermes" "[Ee]dge cases" "D-189: hermes gap_analysis covers edge cases"
assert_file_contains "$hermes" "[Ee]rror" "D-189: hermes gap_analysis covers error paths"
assert_file_contains "$hermes" "[Ss]ecurity" "D-189: hermes gap_analysis covers security"
assert_file_contains "$hermes" "[Bb]ackwards compatibility" "D-189: hermes gap_analysis covers backwards compat"
assert_file_contains "$hermes" "gap.*facts" "D-189: hermes never proposes solutions in gap analysis"

# D-189: Hermes knowledge access upgraded to L1 for project_model
assert_file_contains "$hermes" "project_model: L1" "D-189: hermes project_model is L1 (was L0)"

# D-189: Knowledge access matrix matches
matrix="$SRC_DIR/global/core/knowledge-access-matrix.yaml"
if [[ -f "$matrix" ]]; then
  if grep "hermes:" "$matrix" | grep -q "project_model: L1"; then
    pass "D-189: knowledge-access-matrix hermes project_model is L1"
  else
    fail "D-189: knowledge-access-matrix hermes project_model not L1"
  fi
fi

# D-189: Q1 quality criteria references hermes
q1="$(quality_file q1-completeness)"
assert_file_contains "$q1" "agent: hermes" "D-189: q1-completeness agent is hermes (was athena)"

# ── D-190: Themis plan-check mode ────────────────────────────────────
themis="$(role_file themis)"
assert_file_contains "$themis" "plan_check_mode:" "D-190: themis has plan_check_mode section"
assert_file_contains "$themis" "Scope alignment" "D-190: themis plan-check validates scope"
assert_file_contains "$themis" "File existence" "D-190: themis plan-check validates files"
assert_file_contains "$themis" "Dependency ordering" "D-190: themis plan-check validates deps"
assert_file_contains "$themis" "Verification coverage" "D-190: themis plan-check validates verify fields"

# D-190: Q3b plan-check quality criteria exists
q3b="$(quality_file q3b-plan-check)"
assert_file_exists "$q3b" "D-190: q3b-plan-check.yaml exists"
assert_file_contains "$q3b" "agent: themis" "D-190: q3b agent is themis"
assert_file_contains "$q3b" "Q3b-05" "D-190: q3b has verify check item"

# ── D-191: Embedded task verification ────────────────────────────────
daedalus="$(role_file daedalus)"
assert_file_contains "$daedalus" "embedded_verification:" "D-191: daedalus has embedded_verification section"
assert_file_contains "$daedalus" "Verify:" "D-191: daedalus references Verify: field"
assert_file_contains "$daedalus" "Done:" "D-191: daedalus references Done: field"

hephaestus="$(role_file hephaestus)"
assert_file_contains "$hephaestus" "embedded_verification:" "D-191: hephaestus has embedded_verification section"
assert_file_contains "$hephaestus" "VERIFY: PASS" "D-191: hephaestus records verify pass"
assert_file_contains "$hephaestus" "VERIFY: FAIL" "D-191: hephaestus records verify fail"
assert_file_contains "$hephaestus" "2 fix attempts" "D-191: hephaestus has 2 fix attempt limit"

# D-191: Q3 feasibility has verify/done check
q3="$(quality_file q3-feasibility)"
assert_file_contains "$q3" "Q3-07" "D-191: q3 has Q3-07 verify/done item"
assert_file_contains "$q3" "Verify:" "D-191: q3-07 checks Verify: field"

# ── D-192: Analysis paralysis guard ──────────────────────────────────
assert_file_contains "$hephaestus" "analysis_paralysis_guard:" "D-192: hephaestus has paralysis guard"
assert_file_contains "$hephaestus" "5+" "D-192: hephaestus paralysis threshold is 5+"

assert_file_contains "$daedalus" "analysis_paralysis_guard:" "D-192: daedalus has paralysis guard"
assert_file_contains "$daedalus" "5+" "D-192: daedalus paralysis threshold is 5+"

assert_file_contains "$themis" "analysis_paralysis_guard:" "D-192: themis has paralysis guard"
assert_file_contains "$themis" "5+" "D-192: themis paralysis threshold is 5+"

assert_file_contains "$hermes" "analysis_paralysis_guard:" "D-192: hermes has paralysis guard"
assert_file_contains "$hermes" "10+" "D-192: hermes paralysis threshold is 10+ (explorer)"

# ── D-193: Optimized Full pipeline ───────────────────────────────────
full="$(pipeline_file full)"
assert_file_contains "$full" "plan_check" "D-193: full.yaml has plan_check step"
assert_file_contains "$full" "build_test" "D-193: full.yaml has build_test step"
assert_file_contains "$full" "final_review" "D-193: full.yaml has final_review step"
assert_file_contains "$full" "mid_point_gate" "D-193: full.yaml has mid_point_gate"
assert_file_contains "$full" "gate_per_iteration: false" "D-193: full.yaml per-iteration gate is false"

# D-193: Full pipeline does NOT have aletheia in steps
if grep -q "agent: aletheia" "$full" 2>/dev/null; then
  fail "D-194: full.yaml still references aletheia agent"
else
  pass "D-194: full.yaml does not reference aletheia agent"
fi

# ── D-193: Optimized Standard pipeline ───────────────────────────────
standard="$(pipeline_file standard)"
assert_file_contains "$standard" "build_test" "D-193: standard.yaml has build_test step"
assert_file_contains "$standard" "plan_validate" "D-193: standard.yaml has plan_validate step"

# D-194: Standard pipeline does NOT have aletheia in steps
if grep -q "agent: aletheia" "$standard" 2>/dev/null; then
  fail "D-194: standard.yaml still references aletheia agent"
else
  pass "D-194: standard.yaml does not reference aletheia agent"
fi

# D-189: Standard pipeline does NOT have parallel hermes+athena
if grep -q "mode: parallel" "$standard" 2>/dev/null; then
  fail "D-189: standard.yaml still has parallel dispatch (should be hermes only)"
else
  pass "D-189: standard.yaml has no parallel dispatch"
fi

# ── D-189: Plan gate has 'analyze' option ────────────────────────────
assert_file_contains "$standard" "analyze" "D-189: standard plan gate has analyze option"
assert_file_contains "$full" "analyze" "D-189: full plan gate has analyze option"

# ── D-194: Quick pipeline test option dispatches hephaestus ──────────
quick="$(pipeline_file quick)"
if grep -A2 "test" "$quick" | grep -q "Hephaestus\|hephaestus\|D-194"; then
  pass "D-194: quick.yaml test option references Hephaestus/D-194"
else
  fail "D-194: quick.yaml test option may still reference Aletheia"
fi

# ── D-195: Decomposition pipeline has build_test, not aletheia ───────
decomp="$(pipeline_file decomposition)"
assert_file_contains "$decomp" "build_test\|build-test-runner" "D-195: decomposition.yaml has build_test step"
if grep -q "agent: aletheia" "$decomp" 2>/dev/null; then
  fail "D-195: decomposition.yaml still references aletheia agent"
else
  pass "D-195: decomposition.yaml does not reference aletheia agent"
fi

# ── D-189/D-194: Dispatch skill agent-to-gate mapping ────────────────
dispatch="$SRC_SKILLS/dispatch.md"
if [[ -f "$dispatch" ]]; then
  assert_file_contains "$dispatch" "Hermes.*Q1\|hermes.*Q1" "D-189: dispatch.md maps Hermes to Q1"
  assert_file_contains "$dispatch" "Q3b.*plan-check\|q3b.*plan.check" "D-190: dispatch.md has Q3b plan-check"
  # Check agent-to-gate mapping table (not comments) for Aletheia Q5
  if grep -v "^<!--" "$dispatch" | grep -v "^#" | grep -q "Aletheia.*| Q5\|aletheia.*| Q5" 2>/dev/null; then
    fail "D-194: dispatch.md still maps Aletheia to Q5 in agent-to-gate table"
  else
    pass "D-194: dispatch.md does not map Aletheia to Q5 in agent-to-gate table"
  fi
fi

# ── D-194: Q5 coverage no longer references aletheia ─────────────────
q5="$(quality_file q5-coverage)"
if grep -q "agent: aletheia" "$q5" 2>/dev/null; then
  fail "D-194: q5-coverage.yaml still references aletheia"
else
  pass "D-194: q5-coverage.yaml does not reference aletheia"
fi

# ── xref-manifest has Phase 16 entries ───────────────────────────────
xref="$SRC_DIR/global/core/xref-manifest.yaml"
if [[ -f "$xref" ]]; then
  assert_file_contains "$xref" "xref-023" "xref: has D-189 Q1 gap analysis entry"
  assert_file_contains "$xref" "xref-024" "xref: has D-190 plan-check entry"
  assert_file_contains "$xref" "xref-025" "xref: has D-191 embedded verify entry"
  assert_file_contains "$xref" "xref-026" "xref: has D-192 paralysis guard entry"
fi

# ── Build/test step ordering: build_test BEFORE final_review ─────────
if [[ -f "$full" ]]; then
  build_line=$(grep -n "build_test" "$full" | head -1 | cut -d: -f1)
  review_line=$(grep -n "final_review" "$full" | head -1 | cut -d: -f1)
  if [[ -n "$build_line" && -n "$review_line" && "$build_line" -lt "$review_line" ]]; then
    pass "D-194: full.yaml build_test step appears before final_review"
  else
    fail "D-194: full.yaml build_test step should appear before final_review"
  fi
fi

if [[ -f "$standard" ]]; then
  build_line=$(grep -n "build_test" "$standard" | head -1 | cut -d: -f1)
  review_line=$(grep -n "id: review" "$standard" | head -1 | cut -d: -f1)
  if [[ -n "$build_line" && -n "$review_line" && "$build_line" -lt "$review_line" ]]; then
    pass "D-194: standard.yaml build_test step appears before review"
  else
    fail "D-194: standard.yaml build_test step should appear before review"
  fi
fi

test_summary
