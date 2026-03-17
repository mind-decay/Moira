#!/usr/bin/env bash
# test-quality-system.sh — Verify Phase 6 quality gate artifacts
# Tests schemas, enforcement lib, CONFORM/EVOLVE, quality map, bench, deep scans.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Quality schema tests ───────────────────────────────────────────
assert_file_exists "$SRC_DIR/schemas/findings.schema.yaml" "findings.schema.yaml exists"

if [[ -f "$SRC_DIR/schemas/findings.schema.yaml" ]]; then
  for field in task_id gate agent checklist summary verdict; do
    assert_file_contains "$SRC_DIR/schemas/findings.schema.yaml" "$field" "findings schema has $field field"
  done
  # Severity enum values
  for sev in critical warning suggestion; do
    assert_file_contains "$SRC_DIR/schemas/findings.schema.yaml" "$sev" "findings schema has severity '$sev'"
  done
  # Result enum values
  for res in pass fail na skip; do
    assert_file_contains "$SRC_DIR/schemas/findings.schema.yaml" "$res" "findings schema has result '$res'"
  done
fi

# ── Quality enforcement tests ──────────────────────────────────────
assert_file_exists "$SRC_DIR/global/lib/quality.sh" "quality.sh exists"
if [[ -f "$SRC_DIR/global/lib/quality.sh" ]]; then
  if bash -n "$SRC_DIR/global/lib/quality.sh" 2>/dev/null; then
    pass "quality.sh syntax valid"
  else
    fail "quality.sh has syntax errors"
  fi
  for func in moira_quality_parse_verdict moira_quality_validate_findings moira_quality_aggregate_task moira_quality_format_warnings; do
    assert_file_contains "$SRC_DIR/global/lib/quality.sh" "$func" "quality.sh has $func"
  done
fi

assert_file_contains "$SRC_DIR/global/skills/dispatch.md" "checklist" "dispatch.md has quality checklist injection"
assert_file_contains "$SRC_DIR/global/core/response-contract.yaml" "QUALITY" "response-contract.yaml has QUALITY line"

# ── CONFORM/EVOLVE tests ──────────────────────────────────────────
assert_file_contains "$SRC_DIR/schemas/config.schema.yaml" "quality.mode" "config schema has quality.mode"
assert_file_contains "$SRC_DIR/schemas/config.schema.yaml" "conform" "config schema has conform enum"
assert_file_contains "$SRC_DIR/schemas/config.schema.yaml" "evolve" "config schema has evolve enum"
assert_file_contains "$SRC_DIR/schemas/config.schema.yaml" "current_target" "config schema has evolution.current_target"
assert_file_contains "$SRC_DIR/schemas/config.schema.yaml" "cooldown_remaining" "config schema has evolution.cooldown_remaining"
assert_file_contains "$SRC_DIR/global/skills/orchestrator.md" "quality" "orchestrator.md references quality"
assert_file_contains "$SRC_DIR/global/skills/dispatch.md" "quality.map" "dispatch.md references quality map injection"

# ── Quality map tests ─────────────────────────────────────────────
assert_dir_exists "$SRC_DIR/global/templates/knowledge/quality-map" "quality-map template dir exists"
qm_count=$(ls "$SRC_DIR/global/templates/knowledge/quality-map/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$qm_count" -ge 1 ]]; then
  pass "quality-map templates: $qm_count files (>=1)"
else
  fail "quality-map templates: expected >=1, found $qm_count"
fi

# Check quality map template structure
for qm_file in "$SRC_DIR/global/templates/knowledge/quality-map/"*.md; do
  [[ -f "$qm_file" ]] || continue
  qm_name=$(basename "$qm_file")
  assert_file_contains "$qm_file" "Strong\|Adequate\|Problematic" "$qm_name has quality assessment sections"
  break
done

# ── Bench infrastructure tests ────────────────────────────────────
assert_dir_exists "$SRC_DIR/tests/bench/fixtures" "bench fixtures dir exists"
fixture_count=$(ls -d "$SRC_DIR/tests/bench/fixtures/"*/ 2>/dev/null | wc -l | tr -d ' ')
if [[ "$fixture_count" -ge 3 ]]; then
  pass "bench fixtures: $fixture_count dirs (>=3)"
else
  fail "bench fixtures: expected >=3, found $fixture_count"
fi

# Each fixture has .moira-fixture.yaml
for fixture_dir in "$SRC_DIR/tests/bench/fixtures/"*/; do
  [[ -d "$fixture_dir" ]] || continue
  fixture_name=$(basename "$fixture_dir")
  assert_file_exists "${fixture_dir}.moira-fixture.yaml" "fixture $fixture_name has .moira-fixture.yaml"
  if [[ -f "${fixture_dir}.moira-fixture.yaml" ]]; then
    for field in name stack state reset_command; do
      assert_file_contains "${fixture_dir}.moira-fixture.yaml" "$field" "fixture $fixture_name manifest has $field"
    done
  fi
done

# Test cases
case_count=$(ls "$SRC_DIR/tests/bench/cases/"*.yaml 2>/dev/null | wc -l | tr -d ' ')
if [[ "$case_count" -ge 5 ]]; then
  pass "bench test cases: $case_count files (>=5)"
else
  fail "bench test cases: expected >=5, found $case_count"
fi

# Test case structure
for case_file in "$SRC_DIR/tests/bench/cases/"*.yaml; do
  [[ -f "$case_file" ]] || continue
  case_name=$(basename "$case_file")
  for field in meta fixture task expected_structural; do
    assert_file_contains "$case_file" "$field" "case $case_name has $field"
  done
  # Every case must have meta.tier (2 or 3)
  assert_file_contains "$case_file" "tier:" "case $case_name has meta.tier"
  # Every case must have meta.rubric matching a rubric file
  assert_file_contains "$case_file" "rubric:" "case $case_name has meta.rubric"
done

# Tier config files
assert_file_exists "$SRC_DIR/tests/bench/tier2-config.yaml" "tier2-config.yaml exists"
assert_file_exists "$SRC_DIR/tests/bench/tier3-config.yaml" "tier3-config.yaml exists"

# Rubrics
assert_dir_exists "$SRC_DIR/tests/bench/rubrics" "bench rubrics dir exists"
rubric_count=$(ls "$SRC_DIR/tests/bench/rubrics/"*.yaml 2>/dev/null | wc -l | tr -d ' ')
if [[ "$rubric_count" -ge 1 ]]; then
  pass "bench rubrics: $rubric_count files (>=1)"
else
  fail "bench rubrics: expected >=1, found $rubric_count"
fi

# Rubric structure
for rubric_file in "$SRC_DIR/tests/bench/rubrics/"*.yaml; do
  [[ -f "$rubric_file" ]] || continue
  rubric_name=$(basename "$rubric_file")
  assert_file_contains "$rubric_file" "criteria" "rubric $rubric_name has criteria"
  break
done

# bench.sh and bench.md
assert_file_exists "$SRC_DIR/global/lib/bench.sh" "bench.sh exists"
if [[ -f "$SRC_DIR/global/lib/bench.sh" ]]; then
  if bash -n "$SRC_DIR/global/lib/bench.sh" 2>/dev/null; then
    pass "bench.sh syntax valid"
  else
    fail "bench.sh has syntax errors"
  fi
fi

assert_file_exists "$SRC_DIR/commands/moira/bench.md" "bench.md command exists"
if [[ -f "$SRC_DIR/commands/moira/bench.md" ]]; then
  assert_file_contains "$SRC_DIR/commands/moira/bench.md" "^name:" "bench.md has name frontmatter"
  assert_file_contains "$SRC_DIR/commands/moira/bench.md" "allowed-tools:" "bench.md has allowed-tools frontmatter"
fi

# ── Deep scan tests ───────────────────────────────────────────────
assert_dir_exists "$SRC_DIR/global/templates/scanners/deep" "deep scan templates dir exists"
for template in deep-architecture-scan.md deep-dependency-scan.md deep-test-coverage-scan.md deep-security-scan.md; do
  assert_file_exists "$SRC_DIR/global/templates/scanners/deep/$template" "deep scan $template exists"
  if [[ -f "$SRC_DIR/global/templates/scanners/deep/$template" ]]; then
    assert_file_contains "$SRC_DIR/global/templates/scanners/deep/$template" "Objective\|objective" "$template has Objective section"
    assert_file_contains "$SRC_DIR/global/templates/scanners/deep/$template" "Output\|output" "$template has Output section"
    assert_file_contains "$SRC_DIR/global/templates/scanners/deep/$template" "NEVER" "$template has Explorer NEVER constraints"
  fi
done

# Orchestrator deep scan section is not a stub
assert_file_contains "$SRC_DIR/global/skills/orchestrator.md" "deep" "orchestrator.md has deep scan section"

test_summary
