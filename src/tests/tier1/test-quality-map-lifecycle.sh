#!/usr/bin/env bash
# test-quality-map-lifecycle.sh — Tier 1 tests for quality-map observation counting,
# category migration (demotion/promotion), and lifecycle tracking.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"

# Create temp directory for functional tests
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source knowledge library
source "$MOIRA_HOME/lib/knowledge.sh"

# ── Helper: create fixture quality map ──────────────────────────────

create_fixture_map() {
  local dir="$1"
  mkdir -p "$dir"

  cat > "$dir/full.md" << 'FIXTURE'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map

## Strong Patterns

### Consistent naming
- **Category**: naming
- **Evidence**: task-001 2026-01-01
- **File(s)**: src/
- **Confidence**: high
- **Observation count**: 5
- **Failed observations**: 0
- **Consecutive passes**: 5
- **Lifecycle**: STABLE

## Adequate Patterns

### Error handling
- **Category**: error-handling
- **Evidence**: task-002 2026-01-02
- **Confidence**: medium
- **Observation count**: 3
- **Failed observations**: 1
- **Consecutive passes**: 2
- **Lifecycle**: STABLE

## Problematic Patterns

### Magic numbers
- **Category**: code-quality
- **Evidence**: task-003 2026-01-03
- **Confidence**: high
- **Observation count**: 4
- **Failed observations**: 3
- **Consecutive passes**: 0
- **Lifecycle**: STABLE
FIXTURE

  cat > "$dir/summary.md" << 'SUMMARY'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map Summary

## Strong (follow): Consistent naming
## Adequate (follow with notes): Error handling
## Problematic (don't extend): Magic numbers
SUMMARY
}

# ── Helper: create Themis findings fixture ──────────────────────────

create_findings() {
  local task_dir="$1"
  local check_text="$2"
  local finding_id="${3:-Q4-001}"

  mkdir -p "$task_dir/findings"
  cat > "$task_dir/findings/themis-Q4.yaml" << EOF
findings:
  - id: ${finding_id}
    result: fail
    check: ${check_text}
    severity: medium
EOF
}

# ── 1. Observation count increments on failure ──────────────────────

QMAP_DIR="$TEMP_DIR/test1/quality-map"
TASK_DIR="$TEMP_DIR/test1/task"
create_fixture_map "$QMAP_DIR"

# Create a finding that matches "Magic numbers" (keyword: magic)
create_findings "$TASK_DIR" "Magic numbers in config" "Q4-100"

moira_knowledge_update_quality_map "$TASK_DIR" "$QMAP_DIR" "task-100"

obs_count=$(grep -A 10 "### Magic numbers" "$QMAP_DIR/full.md" | grep "Observation count" | sed 's/.*: //')
assert_equals "$obs_count" "5" "Observation count incremented from 4 to 5"

failed_count=$(grep -A 10 "### Magic numbers" "$QMAP_DIR/full.md" | grep "Failed observations" | sed 's/.*: //')
assert_equals "$failed_count" "4" "Failed observations incremented from 3 to 4"

consec_count=$(grep -A 10 "### Magic numbers" "$QMAP_DIR/full.md" | grep "Consecutive passes" | sed 's/.*: //')
assert_equals "$consec_count" "0" "Consecutive passes reset to 0 on failure"

# ── 2. Evidence line includes source parameter ─────────────────────

evidence_line=$(grep -A 10 "### Magic numbers" "$QMAP_DIR/full.md" | grep "Evidence")
if echo "$evidence_line" | grep -q "task-100" 2>/dev/null; then
  pass "Evidence line contains source parameter (task-100)"
else
  fail "Evidence line missing source parameter: $evidence_line"
fi

# ── 3. Demotion at 3 failed observations ───────────────────────────

QMAP_DIR2="$TEMP_DIR/test3/quality-map"
TASK_DIR2="$TEMP_DIR/test3/task"
mkdir -p "$QMAP_DIR2"
cat > "$QMAP_DIR2/full.md" << 'MAP2'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map

## Strong Patterns

## Adequate Patterns

### Weak validation
- **Category**: validation
- **Evidence**: task-010 2026-01-10
- **Confidence**: medium
- **Observation count**: 4
- **Failed observations**: 2
- **Consecutive passes**: 0
- **Lifecycle**: STABLE

## Problematic Patterns
MAP2
cat > "$QMAP_DIR2/summary.md" << 'SUM2'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map Summary

## Strong (follow): None detected yet
## Adequate (follow with notes): Weak validation
## Problematic (don't extend): None detected yet
SUM2

create_findings "$TASK_DIR2" "Weak validation in forms" "Q4-200"

moira_knowledge_update_quality_map "$TASK_DIR2" "$QMAP_DIR2" "task-200"

# After this, Failed observations = 3, should trigger demotion Adequate -> Problematic
if grep -A 15 "## Problematic" "$QMAP_DIR2/full.md" | grep -q "### Weak validation"; then
  pass "Entry demoted from Adequate to Problematic at 3 failed observations"
else
  fail "Entry not demoted: $(cat "$QMAP_DIR2/full.md")"
fi

demoted_lifecycle=$(grep -A 10 "### Weak validation" "$QMAP_DIR2/full.md" | grep "Lifecycle" | sed 's/.*: //')
assert_equals "$demoted_lifecycle" "DEMOTED" "Lifecycle set to DEMOTED after demotion"

# ── 4. Double demotion (Strong -> Adequate -> Problematic) ──────────

QMAP_DIR3="$TEMP_DIR/test4/quality-map"
mkdir -p "$QMAP_DIR3"
cat > "$QMAP_DIR3/full.md" << 'MAP3'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map

## Strong Patterns

### Good logging
- **Category**: observability
- **Evidence**: init 2026-01-01
- **Confidence**: high
- **Observation count**: 2
- **Failed observations**: 2
- **Consecutive passes**: 0
- **Lifecycle**: STABLE

## Adequate Patterns

## Problematic Patterns
MAP3
cat > "$QMAP_DIR3/summary.md" << 'SUM3'
<!-- moira:freshness task 2026-01-01 -->
# Quality Map Summary
## Strong (follow): Good logging
## Adequate (follow with notes): None detected yet
## Problematic (don't extend): None detected yet
SUM3

# First failure: Failed=3 -> demote Strong -> Adequate
TASK_DIR3A="$TEMP_DIR/test4/task-a"
create_findings "$TASK_DIR3A" "Good logging not consistent" "Q4-300"
moira_knowledge_update_quality_map "$TASK_DIR3A" "$QMAP_DIR3" "task-300"

if grep -A 15 "## Adequate" "$QMAP_DIR3/full.md" | grep -q "### Good logging"; then
  pass "Entry demoted from Strong to Adequate"
else
  fail "First demotion failed"
fi

# Add more failures to trigger second demotion
for i in 1 2 3; do
  TASK_DIR3B="$TEMP_DIR/test4/task-b${i}"
  create_findings "$TASK_DIR3B" "Good logging inconsistent again" "Q4-30${i}"
  moira_knowledge_update_quality_map "$TASK_DIR3B" "$QMAP_DIR3" "task-30${i}"
done

if grep -A 15 "## Problematic" "$QMAP_DIR3/full.md" | grep -q "### Good logging"; then
  pass "Entry double-demoted from Adequate to Problematic"
else
  fail "Second demotion failed"
fi

# ── 5. Pass observation + promotion (Problematic -> Adequate -> Strong) ──

QMAP_DIR4="$TEMP_DIR/test5/quality-map"
mkdir -p "$QMAP_DIR4"
cat > "$QMAP_DIR4/full.md" << 'MAP4'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map

## Strong Patterns

## Adequate Patterns

## Problematic Patterns

### Inconsistent formatting
- **Category**: style
- **Evidence**: task-400 2026-01-20
- **Confidence**: medium
- **Observation count**: 5
- **Failed observations**: 4
- **Consecutive passes**: 0
- **Lifecycle**: STABLE
MAP4
cat > "$QMAP_DIR4/summary.md" << 'SUM4'
<!-- moira:freshness task 2026-01-01 -->
# Quality Map Summary
## Strong (follow): None detected yet
## Adequate (follow with notes): None detected yet
## Problematic (don't extend): Inconsistent formatting
SUM4

# 3 pass observations -> promote to Adequate
for i in 1 2 3; do
  moira_knowledge_quality_map_pass_observation "$QMAP_DIR4" "Inconsistent formatting" "task-50${i}"
done

if grep -A 15 "## Adequate" "$QMAP_DIR4/full.md" | grep -q "### Inconsistent formatting"; then
  pass "Entry promoted from Problematic to Adequate after 3 consecutive passes"
else
  fail "Promotion from Problematic to Adequate failed"
fi

promoted_lifecycle=$(grep -A 10 "### Inconsistent formatting" "$QMAP_DIR4/full.md" | grep "Lifecycle" | sed 's/.*: //')
assert_equals "$promoted_lifecycle" "PROMOTED" "Lifecycle set to PROMOTED after promotion"

# 3 more passes -> promote to Strong
for i in 1 2 3; do
  moira_knowledge_quality_map_pass_observation "$QMAP_DIR4" "Inconsistent formatting" "task-60${i}"
done

if grep -A 15 "## Strong" "$QMAP_DIR4/full.md" | grep -q "### Inconsistent formatting"; then
  pass "Entry promoted from Adequate to Strong after 3 more consecutive passes"
else
  fail "Promotion from Adequate to Strong failed"
fi

# ── 6. Consecutive passes reset on failure ──────────────────────────

QMAP_DIR5="$TEMP_DIR/test6/quality-map"
mkdir -p "$QMAP_DIR5"
cat > "$QMAP_DIR5/full.md" << 'MAP5'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map

## Strong Patterns

## Adequate Patterns

## Problematic Patterns

### Hardcoded paths
- **Category**: config
- **Evidence**: task-700 2026-01-25
- **Confidence**: medium
- **Observation count**: 3
- **Failed observations**: 2
- **Consecutive passes**: 2
- **Lifecycle**: STABLE
MAP5
cat > "$QMAP_DIR5/summary.md" << 'SUM5'
<!-- moira:freshness task 2026-01-01 -->
# Quality Map Summary
## Strong (follow): None detected yet
## Adequate (follow with notes): None detected yet
## Problematic (don't extend): Hardcoded paths
SUM5

# Cause a failure — should reset consecutive passes
TASK_DIR5="$TEMP_DIR/test6/task"
create_findings "$TASK_DIR5" "Hardcoded paths in config" "Q4-700"
moira_knowledge_update_quality_map "$TASK_DIR5" "$QMAP_DIR5" "task-700"

consec=$(grep -A 10 "### Hardcoded paths" "$QMAP_DIR5/full.md" | grep "Consecutive passes" | sed 's/.*: //')
assert_equals "$consec" "0" "Consecutive passes reset to 0 on failure"

# ── 7. Legacy entries without Observation count field ───────────────

QMAP_DIR6="$TEMP_DIR/test7/quality-map"
mkdir -p "$QMAP_DIR6"
cat > "$QMAP_DIR6/full.md" << 'MAP6'
<!-- moira:freshness task 2026-01-01 -->

# Quality Map

## Strong Patterns

## Adequate Patterns

## Problematic Patterns

### Legacy pattern
- **Category**: legacy
- **Evidence**: old-task 2025-01-01
- **Confidence**: low
- **Lifecycle**: NEW
MAP6
cat > "$QMAP_DIR6/summary.md" << 'SUM6'
<!-- moira:freshness task 2026-01-01 -->
# Quality Map Summary
## Strong (follow): None detected yet
## Adequate (follow with notes): None detected yet
## Problematic (don't extend): Legacy pattern
SUM6

# Pass observation on legacy entry without Observation count/Failed observations/Consecutive passes
moira_knowledge_quality_map_pass_observation "$QMAP_DIR6" "Legacy pattern" "task-800"

obs=$(grep -A 10 "### Legacy pattern" "$QMAP_DIR6/full.md" | grep "Observation count" | sed 's/.*: //')
assert_equals "$obs" "1" "Legacy entry gets Observation count initialized to 1"

failed=$(grep -A 10 "### Legacy pattern" "$QMAP_DIR6/full.md" | grep "Failed observations" | sed 's/.*: //')
assert_equals "$failed" "0" "Legacy entry gets Failed observations initialized to 0"

consec=$(grep -A 10 "### Legacy pattern" "$QMAP_DIR6/full.md" | grep "Consecutive passes" | sed 's/.*: //')
assert_equals "$consec" "1" "Legacy entry gets Consecutive passes initialized to 1"

# ── 8. Source parameter appears in evidence lines ───────────────────

QMAP_DIR7="$TEMP_DIR/test8/quality-map"
TASK_DIR7="$TEMP_DIR/test8/task"
create_fixture_map "$QMAP_DIR7"
create_findings "$TASK_DIR7" "Error handling missing try-catch" "Q4-900"

moira_knowledge_update_quality_map "$TASK_DIR7" "$QMAP_DIR7" "refresh"

evidence=$(grep -A 10 "### Error handling" "$QMAP_DIR7/full.md" | grep "Evidence")
if echo "$evidence" | grep -q "refresh" 2>/dev/null; then
  pass "Source parameter 'refresh' appears in evidence line"
else
  fail "Source parameter not in evidence: $evidence"
fi

# ── Summary ─────────────────────────────────────────────────────────

test_summary
