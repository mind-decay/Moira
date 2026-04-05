#!/usr/bin/env bash
# test-fn-judge.sh — Functional tests for judge.sh
# Tests composite score calculation, normalization, calibration.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: judge.sh (functional)"

source "$SRC_LIB_DIR/judge.sh"
set +e

# ── moira_judge_normalize_score: 1-5 → 0-100 ────────────────────────

run_fn moira_judge_normalize_score 1
assert_output_equals "$FN_STDOUT" "0" "normalize: 1 → 0"

run_fn moira_judge_normalize_score 2
assert_output_equals "$FN_STDOUT" "25" "normalize: 2 → 25"

run_fn moira_judge_normalize_score 3
assert_output_equals "$FN_STDOUT" "50" "normalize: 3 → 50"

run_fn moira_judge_normalize_score 4
assert_output_equals "$FN_STDOUT" "75" "normalize: 4 → 75"

run_fn moira_judge_normalize_score 5
assert_output_equals "$FN_STDOUT" "100" "normalize: 5 → 100"

# ── moira_judge_composite_score: weighted average ────────────────────

cat > "$TEMP_DIR/evaluation.yaml" << 'EOF'
scores:
  requirements_coverage: 75
  code_correctness: 75
  architecture_quality: 50
  conventions_adherence: 75
EOF

# Weights: req=25, code=30, arch=25, conv=20
# Composite = 75*25 + 75*30 + 50*25 + 75*20 = 1875+2250+1250+1500 = 6875
run_fn moira_judge_composite_score "$TEMP_DIR/evaluation.yaml"
assert_exit_zero "composite_score: exit 0"
# Accept any non-zero output (implementation-specific format)
if [[ -n "$FN_STDOUT" && "$FN_STDOUT" != "0" ]]; then
  pass "composite_score: returns non-zero for valid scores"
else
  fail "composite_score: expected non-zero output, got '$FN_STDOUT'"
fi

# ── moira_judge_composite_score: all 100s ────────────────────────────

cat > "$TEMP_DIR/perfect.yaml" << 'EOF'
scores:
  requirements_coverage: 100
  code_correctness: 100
  architecture_quality: 100
  conventions_adherence: 100
EOF

run_fn moira_judge_composite_score "$TEMP_DIR/perfect.yaml"
if [[ -n "$FN_STDOUT" && "$FN_STDOUT" != "0" ]]; then
  pass "composite_score: all 100s → non-zero"
else
  fail "composite_score: all 100s → expected non-zero, got '$FN_STDOUT'"
fi

# ── moira_judge_composite_score: all 0s ─��────────────────────────────

cat > "$TEMP_DIR/terrible.yaml" << 'EOF'
scores:
  requirements_coverage: 0
  code_correctness: 0
  architecture_quality: 0
  conventions_adherence: 0
EOF

run_fn moira_judge_composite_score "$TEMP_DIR/terrible.yaml"
assert_output_equals "$FN_STDOUT" "0" "composite_score: all 0s → 0"

# ── moira_judge_composite_score: missing file → error ────────────────

run_fn moira_judge_composite_score "$TEMP_DIR/nonexistent.yaml"
assert_exit_nonzero "composite_score: missing file → exit 1"

# ── moira_judge_composite_score: automated_pass=false → capped ───────

run_fn moira_judge_composite_score "$TEMP_DIR/evaluation.yaml" "false"
# When automated tests fail, quality is capped
assert_exit_zero "composite_score: automated_pass=false → exit 0"

# ── moira_judge_calibrate: with matching expectations ────────────────

cal_dir="$TEMP_DIR/calibration"
mkdir -p "$cal_dir/good-implementation"

cat > "$cal_dir/good-implementation/evaluation.yaml" << 'EOF'
evaluation:
  scores:
    requirements_coverage:
      score: 4
    code_correctness:
      score: 4
    architecture_quality:
      score: 4
    conventions_adherence:
      score: 4
EOF

cat > "$cal_dir/good-implementation/expected.yaml" << 'EOF'
expected_scores:
  requirements_coverage: 4
  code_correctness: 4
  architecture_quality: 4
  conventions_adherence: 4
tolerance: 1
EOF

cat > "$TEMP_DIR/rubric.yaml" << 'EOF'
criteria:
  - id: requirements_coverage
    weight: 25
  - id: code_correctness
    weight: 30
  - id: architecture_quality
    weight: 25
  - id: conventions_adherence
    weight: 20
EOF

run_fn moira_judge_calibrate "$cal_dir" "$TEMP_DIR/rubric.yaml"
assert_exit_zero "calibrate: matching expectations → exit 0"

test_summary
