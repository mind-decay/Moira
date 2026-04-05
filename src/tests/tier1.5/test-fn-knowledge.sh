#!/usr/bin/env bash
# test-fn-knowledge.sh — Functional tests for knowledge.sh
# Tests read/write, freshness decay, conflict detection, type validation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: knowledge.sh (functional)"

# Source the library under test
source "$SRC_LIB_DIR/knowledge.sh"
set +e

# ── Helper: create knowledge directory ───────────────────────────────
setup_knowledge() {
  local know_dir="$1"
  mkdir -p "$know_dir"/{project-model,conventions,decisions,patterns,failures,quality-map,libraries}
}

# ── Type validation: all valid types accepted ────────────────────────

valid_types="project-model conventions decisions patterns failures quality-map libraries"

for ktype in $valid_types; do
  run_fn _moira_valid_type "$ktype"
  assert_exit_zero "valid_type: '$ktype' accepted"
done

# ── Type validation: invalid type rejected ───────────────────────────

run_fn _moira_valid_type "bogus-type"
assert_exit_nonzero "valid_type: invalid type rejected"

# ── Level file mapping ───────────────────────────────────────────────

run_fn _moira_level_file "L0"
assert_output_equals "$FN_STDOUT" "index.md" "level_file: L0 → index.md"

run_fn _moira_level_file "L1"
assert_output_equals "$FN_STDOUT" "summary.md" "level_file: L1 → summary.md"

run_fn _moira_level_file "L2"
assert_output_equals "$FN_STDOUT" "full.md" "level_file: L2 → full.md"

run_fn _moira_level_file "L3"
assert_exit_nonzero "level_file: invalid level rejected"

# ── moira_knowledge_read: basic reads ────────────────────────────────

know_dir="$TEMP_DIR/know-read"
setup_knowledge "$know_dir"
echo "project index content" > "$know_dir/project-model/index.md"
echo "project summary content" > "$know_dir/project-model/summary.md"
echo "project full content" > "$know_dir/project-model/full.md"

run_fn moira_knowledge_read "$know_dir" "project-model" "L0"
assert_output_equals "$FN_STDOUT" "project index content" "read: L0 returns index.md"

run_fn moira_knowledge_read "$know_dir" "project-model" "L1"
assert_output_equals "$FN_STDOUT" "project summary content" "read: L1 returns summary.md"

run_fn moira_knowledge_read "$know_dir" "project-model" "L2"
assert_output_equals "$FN_STDOUT" "project full content" "read: L2 returns full.md"

# ── moira_knowledge_read: nonexistent file → empty ───────────────────

run_fn moira_knowledge_read "$know_dir" "conventions" "L0"
assert_exit_zero "read: nonexistent file → exit 0"
assert_output_empty "$FN_STDOUT" "read: nonexistent file → empty"

# ── moira_knowledge_read: quality-map L0 → empty (AD-6) ─────────────

echo "quality index" > "$know_dir/quality-map/index.md"
run_fn moira_knowledge_read "$know_dir" "quality-map" "L0"
assert_output_empty "$FN_STDOUT" "read: quality-map L0 returns empty (AD-6)"

# ── moira_knowledge_read: libraries L2 → empty ──────────────────────

echo "libraries full" > "$know_dir/libraries/full.md"
run_fn moira_knowledge_read "$know_dir" "libraries" "L2"
assert_output_empty "$FN_STDOUT" "read: libraries L2 returns empty"

# ── moira_knowledge_read: invalid type → error ───────────────────────

run_fn moira_knowledge_read "$know_dir" "bogus" "L0"
assert_exit_nonzero "read: invalid type → error"

# ── moira_knowledge_write: creates file with freshness marker ────────

know_write="$TEMP_DIR/know-write"
setup_knowledge "$know_write"

echo "## New Pattern" > "$TEMP_DIR/content.md"
echo "Description of pattern" >> "$TEMP_DIR/content.md"

moira_knowledge_write "$know_write" "conventions" "L1" "$TEMP_DIR/content.md" "task-2026-04-05-001"
assert_file_exists "$know_write/conventions/summary.md" "write: creates level file"
assert_file_contains "$know_write/conventions/summary.md" "moira:freshness" "write: includes freshness marker"
assert_file_contains "$know_write/conventions/summary.md" "task-2026-04-05-001" "write: includes task_id in marker"
assert_file_contains "$know_write/conventions/summary.md" "New Pattern" "write: includes content"

# ── moira_knowledge_write: invalid type → error ──────────────────────

run_fn moira_knowledge_write "$know_write" "bogus" "L1" "$TEMP_DIR/content.md" "task-001"
assert_exit_nonzero "write: invalid type → error"

# ── Exponential decay: _moira_knowledge_exp_decay ────────────────────

# distance 0 → 100
run_fn _moira_knowledge_exp_decay 5 0
assert_output_equals "$FN_STDOUT" "100" "exp_decay: distance 0 → 100"

# distance 1, lambda 5 → ~95
run_fn _moira_knowledge_exp_decay 5 1
assert_numeric_range "$FN_STDOUT" 93 97 "exp_decay: λ=0.05 d=1 → ~95"

# distance 10, lambda 5 → ~60
run_fn _moira_knowledge_exp_decay 5 10
assert_numeric_range "$FN_STDOUT" 55 65 "exp_decay: λ=0.05 d=10 → ~60"

# distance 50, lambda 5 → ~8
run_fn _moira_knowledge_exp_decay 5 50
assert_numeric_range "$FN_STDOUT" 0 15 "exp_decay: λ=0.05 d=50 → low"

# high lambda, moderate distance → fast decay
run_fn _moira_knowledge_exp_decay 8 20
assert_numeric_range "$FN_STDOUT" 0 25 "exp_decay: λ=0.08 d=20 → very low"

# low lambda → slow decay
run_fn _moira_knowledge_exp_decay 1 10
assert_numeric_range "$FN_STDOUT" 85 95 "exp_decay: λ=0.01 d=10 → still high"

# very large distance → 0
run_fn _moira_knowledge_exp_decay 5 500
assert_output_equals "$FN_STDOUT" "0" "exp_decay: very large distance → 0"

# ── Lambda lookup: _moira_knowledge_get_lambda ───────────────────────

run_fn _moira_knowledge_get_lambda "conventions"
assert_output_equals "$FN_STDOUT" "2" "get_lambda: conventions → 2"

run_fn _moira_knowledge_get_lambda "project-model"
assert_output_equals "$FN_STDOUT" "8" "get_lambda: project-model → 8"

run_fn _moira_knowledge_get_lambda "decisions"
assert_output_equals "$FN_STDOUT" "1" "get_lambda: decisions → 1"

run_fn _moira_knowledge_get_lambda "failures"
assert_output_equals "$FN_STDOUT" "3" "get_lambda: failures → 3"

# ── Freshness category mapping ───────────────────────────────────────

run_fn moira_knowledge_freshness_category 80
assert_output_equals "$FN_STDOUT" "trusted" "freshness_category: 80 → trusted"

run_fn moira_knowledge_freshness_category 71
assert_output_equals "$FN_STDOUT" "trusted" "freshness_category: 71 → trusted"

run_fn moira_knowledge_freshness_category 70
assert_output_equals "$FN_STDOUT" "usable" "freshness_category: 70 → usable"

run_fn moira_knowledge_freshness_category 50
assert_output_equals "$FN_STDOUT" "usable" "freshness_category: 50 → usable"

run_fn moira_knowledge_freshness_category 31
assert_output_equals "$FN_STDOUT" "usable" "freshness_category: 31 → usable"

run_fn moira_knowledge_freshness_category 30
assert_output_equals "$FN_STDOUT" "needs-verification" "freshness_category: 30 → needs-verification"

run_fn moira_knowledge_freshness_category 0
assert_output_equals "$FN_STDOUT" "needs-verification" "freshness_category: 0 → needs-verification"

# ── Freshness score: end-to-end ──────────────────────────────────────

know_fresh="$TEMP_DIR/know-fresh"
setup_knowledge "$know_fresh"

# Write a summary with freshness marker at task 10
cat > "$know_fresh/conventions/summary.md" << 'EOF'
<!-- moira:freshness task-2026-04-05-010 2026-04-05 λ=0.02 -->

# Conventions summary
EOF

# Current task is 12 → distance 2 → should be high confidence
run_fn moira_knowledge_freshness_score "$know_fresh" "conventions" "12"
assert_numeric_range "$FN_STDOUT" 90 100 "freshness_score: distance 2, λ=0.02 → high"

# Current task is 100 → distance 90 → should be low
run_fn moira_knowledge_freshness_score "$know_fresh" "conventions" "100"
assert_numeric_range "$FN_STDOUT" 0 30 "freshness_score: distance 90, λ=0.02 → low"

# ── Freshness: no file → 0 ──────────────────────────────────────────

run_fn moira_knowledge_freshness_score "$know_fresh" "patterns" "10"
assert_output_equals "$FN_STDOUT" "0" "freshness_score: no file → 0"

# ── Freshness: no tag → 0 ───────────────────────────────────────────

echo "# No freshness tag here" > "$know_fresh/patterns/summary.md"
run_fn moira_knowledge_freshness_score "$know_fresh" "patterns" "10"
assert_output_equals "$FN_STDOUT" "0" "freshness_score: no tag → 0"

# ── Freshness backward compat: fresh/aging/stale/unknown ─────────────

run_fn moira_knowledge_freshness "$know_fresh" "conventions" "12"
assert_output_equals "$FN_STDOUT" "fresh" "freshness: distance 2 → fresh"

run_fn moira_knowledge_freshness "$know_fresh" "conventions" "100"
assert_output_equals "$FN_STDOUT" "stale" "freshness: distance 90 → stale"

know_no_file="$TEMP_DIR/know-no-file"
setup_knowledge "$know_no_file"
run_fn moira_knowledge_freshness "$know_no_file" "decisions" "10"
assert_output_equals "$FN_STDOUT" "unknown" "freshness: no file → unknown"

# ── Freshness marker write + read ────────────────────────────────────

marker_file="$TEMP_DIR/marker-test.md"
echo "# Some content" > "$marker_file"

moira_knowledge_freshness_marker_write "$marker_file" "task-005" "2026-04-05" "conventions"
assert_file_contains "$marker_file" "moira:freshness task-005" "marker_write: writes marker"
assert_file_contains "$marker_file" "λ=0.02" "marker_write: includes lambda for conventions"

run_fn moira_knowledge_freshness_marker_read "$marker_file"
assert_output_contains "$FN_STDOUT" "task_id: task-005" "marker_read: parses task_id"
assert_output_contains "$FN_STDOUT" "date: 2026-04-05" "marker_read: parses date"

# ── Conflict check: no file → no conflict ────────────────────────────

run_fn moira_knowledge_conflict_check "## Some Header" "$TEMP_DIR/nonexistent.md"
assert_exit_zero "conflict_check: no file → no conflict"

# ── Conflict check: no duplicate → no conflict ──────────────────────

cat > "$TEMP_DIR/existing.md" << 'EOF'
## Existing Pattern A
Content A
## Existing Pattern B
Content B
EOF

run_fn moira_knowledge_conflict_check "## New Pattern C" "$TEMP_DIR/existing.md"
assert_exit_zero "conflict_check: no duplicate → no conflict"

# ── Conflict check: duplicate → conflict ─────────────────────────────

run_fn moira_knowledge_conflict_check "## Existing Pattern A" "$TEMP_DIR/existing.md"
assert_exit_nonzero "conflict_check: duplicate header → conflict"

# ── Archive rotation: below threshold → no-op ────────────────────────

know_archive="$TEMP_DIR/know-archive"
setup_knowledge "$know_archive"

cat > "$know_archive/decisions/full.md" << 'EOF'
## Decision One
Content one
## Decision Two
Content two
EOF

run_fn moira_knowledge_archive_rotate "$know_archive" "decisions" "5"
assert_exit_zero "archive_rotate: below threshold → exit 0"
# Should not create archive dir
if [[ ! -d "$know_archive/decisions/archive" ]]; then
  pass "archive_rotate: no archive created when below threshold"
else
  fail "archive_rotate: archive should not exist below threshold"
fi

# ── Archive rotation: invalid type → error ───────────────────────────

run_fn moira_knowledge_archive_rotate "$know_archive" "conventions" "5"
assert_exit_nonzero "archive_rotate: invalid type (conventions) → error"

test_summary
