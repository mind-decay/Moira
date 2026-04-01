#!/usr/bin/env bash
# test-knowledge-system.sh — Tier 1 tests for Moira knowledge system
# Tests knowledge read/write/freshness/archival/consistency operations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"

# Create temp directory for functional tests
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source knowledge library
source "$MOIRA_HOME/lib/knowledge.sh"

# ── 1. Knowledge directory structure (installed) ─────────────────────

assert_dir_exists "$MOIRA_HOME/templates/knowledge" "templates/knowledge/ exists"

for ktype in project-model conventions decisions patterns failures quality-map libraries; do
  assert_dir_exists "$MOIRA_HOME/templates/knowledge/$ktype" "templates/knowledge/$ktype/ exists"
done

# Template file count
template_count=$(find "$MOIRA_HOME/templates/knowledge" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$template_count" "19" "19 knowledge template files exist"

# Quality-map has NO index.md (L0)
if [[ ! -f "$MOIRA_HOME/templates/knowledge/quality-map/index.md" ]]; then
  pass "quality-map has no index.md (L0 not applicable per AD-6)"
else
  fail "quality-map should NOT have index.md"
fi

# ── 2. moira_knowledge_read ──────────────────────────────────────────

# Set up temp knowledge dir with test content
KNOW_DIR="$TEMP_DIR/knowledge"
mkdir -p "$KNOW_DIR/project-model"
mkdir -p "$KNOW_DIR/conventions"
mkdir -p "$KNOW_DIR/quality-map"

echo "index content here" > "$KNOW_DIR/project-model/index.md"
echo "summary content here" > "$KNOW_DIR/project-model/summary.md"
echo "full content here" > "$KNOW_DIR/project-model/full.md"
echo "conventions summary" > "$KNOW_DIR/conventions/summary.md"
echo "quality summary" > "$KNOW_DIR/quality-map/summary.md"

# Read L0
result=$(moira_knowledge_read "$KNOW_DIR" "project-model" "L0")
assert_equals "$result" "index content here" "read L0 returns index.md content"

# Read L1
result=$(moira_knowledge_read "$KNOW_DIR" "project-model" "L1")
assert_equals "$result" "summary content here" "read L1 returns summary.md content"

# Read L2
result=$(moira_knowledge_read "$KNOW_DIR" "project-model" "L2")
assert_equals "$result" "full content here" "read L2 returns full.md content"

# Read quality-map L0 → returns empty (no L0 for quality-map)
result=$(moira_knowledge_read "$KNOW_DIR" "quality-map" "L0")
assert_equals "$result" "" "read quality-map L0 returns empty"

# Read nonexistent file → returns empty
result=$(moira_knowledge_read "$KNOW_DIR" "decisions" "L0")
assert_equals "$result" "" "read nonexistent type file returns empty"

# ── 3. moira_knowledge_read_for_agent ────────────────────────────────

# Set up test knowledge + matrix
AGENT_KNOW_DIR="$TEMP_DIR/agent-knowledge"
for ktype in project-model conventions decisions patterns failures quality-map libraries; do
  mkdir -p "$AGENT_KNOW_DIR/$ktype"
done

echo "pm-index" > "$AGENT_KNOW_DIR/project-model/index.md"
echo "pm-summary" > "$AGENT_KNOW_DIR/project-model/summary.md"
echo "pm-full" > "$AGENT_KNOW_DIR/project-model/full.md"
echo "conv-index" > "$AGENT_KNOW_DIR/conventions/index.md"
echo "conv-summary" > "$AGENT_KNOW_DIR/conventions/summary.md"
echo "conv-full" > "$AGENT_KNOW_DIR/conventions/full.md"
echo "dec-index" > "$AGENT_KNOW_DIR/decisions/index.md"
echo "dec-summary" > "$AGENT_KNOW_DIR/decisions/summary.md"
echo "dec-full" > "$AGENT_KNOW_DIR/decisions/full.md"
echo "pat-index" > "$AGENT_KNOW_DIR/patterns/index.md"
echo "pat-summary" > "$AGENT_KNOW_DIR/patterns/summary.md"
echo "pat-full" > "$AGENT_KNOW_DIR/patterns/full.md"
echo "fail-index" > "$AGENT_KNOW_DIR/failures/index.md"
echo "fail-summary" > "$AGENT_KNOW_DIR/failures/summary.md"
echo "fail-full" > "$AGENT_KNOW_DIR/failures/full.md"
echo "qm-summary" > "$AGENT_KNOW_DIR/quality-map/summary.md"
echo "qm-full" > "$AGENT_KNOW_DIR/quality-map/full.md"
mkdir -p "$AGENT_KNOW_DIR/libraries"
echo "lib-index" > "$AGENT_KNOW_DIR/libraries/index.md"
echo "lib-summary" > "$AGENT_KNOW_DIR/libraries/summary.md"

# Use the real matrix file
MATRIX_FILE="$MOIRA_HOME/core/knowledge-access-matrix.yaml"

# Hermes: only project-model L1 (D-189: L0→L1 for gap analysis context)
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "hermes" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-summary" && ! echo "$result" | grep -q "conv-" && ! echo "$result" | grep -q "fail-" && ! echo "$result" | grep -q "qm-"; then
  pass "hermes gets only project-model L1 (D-189)"
else
  fail "hermes access incorrect: $result"
fi

# Hephaestus: project-model L0 + conventions L2 + patterns L1 (no quality-map, failures, decisions)
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "hephaestus" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-index" && echo "$result" | grep -q "conv-full" && echo "$result" | grep -q "pat-summary" && ! echo "$result" | grep -q "fail-" && ! echo "$result" | grep -q "qm-"; then
  pass "hephaestus gets project-model L0 + conventions L2 + patterns L1 (no failures/quality-map)"
else
  fail "hephaestus access incorrect: $result"
fi

# Metis: project-model L1 + conventions L0 + decisions L2 + patterns L1 + quality-map L1 + failures L0
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "metis" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-summary" && echo "$result" | grep -q "conv-index" && echo "$result" | grep -q "dec-full" && echo "$result" | grep -q "pat-summary" && echo "$result" | grep -q "qm-summary" && echo "$result" | grep -q "fail-index"; then
  pass "metis gets project-model L1 + conventions L0 + decisions L2 + patterns L1 + quality-map L1 + failures L0"
else
  fail "metis access incorrect: $result"
fi

# Mnemosyne: all 7 types at L2 (libraries L2 gets L1 content)
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "mnemosyne" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-full" && echo "$result" | grep -q "conv-full" && echo "$result" | grep -q "dec-full" && echo "$result" | grep -q "pat-full" && echo "$result" | grep -q "qm-full" && echo "$result" | grep -q "fail-full" && echo "$result" | grep -q "lib-summary"; then
  pass "mnemosyne gets all 7 types (libraries L2 loads L1)"
else
  fail "mnemosyne access incorrect: $result"
fi

# Output contains section headers
if echo "$result" | grep -q "## Knowledge:"; then
  pass "output contains section headers"
else
  fail "output missing section headers"
fi

# Daedalus: project-model L1 + conventions L1 + decisions L0 + patterns L0 + quality-map L2 + libraries L0
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "daedalus" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-summary" && echo "$result" | grep -q "conv-summary" && echo "$result" | grep -q "dec-index" && echo "$result" | grep -q "pat-index" && echo "$result" | grep -q "qm-full" && echo "$result" | grep -q "lib-index"; then
  pass "daedalus gets project-model L1 + conventions L1 + decisions L0 + patterns L0 + quality-map L2 + libraries L0"
else
  fail "daedalus access incorrect: $result"
fi

# ── 4. Freshness markers ─────────────────────────────────────────────

FRESH_DIR="$TEMP_DIR/freshness"
mkdir -p "$FRESH_DIR/project-model"

# Write knowledge with task ID
echo "test content" > "$TEMP_DIR/content.md"
moira_knowledge_write "$FRESH_DIR" "project-model" "L1" "$TEMP_DIR/content.md" "task-2024-01-15-042"

# Check freshness tag exists (with λ parameter)
if grep -q '<!-- moira:freshness task-2024-01-15-042' "$FRESH_DIR/project-model/summary.md"; then
  pass "write adds freshness tag"
else
  fail "freshness tag not found after write"
fi

# Check λ parameter in freshness tag
if grep -q 'λ=' "$FRESH_DIR/project-model/summary.md"; then
  pass "write includes λ parameter in freshness tag"
else
  fail "freshness tag missing λ parameter"
fi

# Check content is present
if grep -q "test content" "$FRESH_DIR/project-model/summary.md"; then
  pass "write preserves content"
else
  fail "content not found after write"
fi

# Exponential decay: freshness score returns 0-100
score=$(moira_knowledge_freshness_score "$FRESH_DIR" "project-model" "45")
if [[ $score -ge 0 && $score -le 100 ]]; then
  pass "freshness_score returns valid range 0-100 (got: $score)"
else
  fail "freshness_score out of range: $score"
fi

# Close distance → high confidence
score_close=$(moira_knowledge_freshness_score "$FRESH_DIR" "project-model" "45")
if [[ $score_close -gt 70 ]]; then
  pass "freshness_score: distance 3 → high confidence ($score_close > 70)"
else
  fail "freshness_score: distance 3 → expected >70, got $score_close"
fi

# Backward compatibility: moira_knowledge_freshness still returns fresh/aging/stale
result=$(moira_knowledge_freshness "$FRESH_DIR" "project-model" "45")
assert_equals "$result" "fresh" "freshness: distance 3 = fresh (backward compat)"

# Large distance → low confidence
result=$(moira_knowledge_freshness "$FRESH_DIR" "project-model" "100")
assert_equals "$result" "stale" "freshness: distance 58 = stale (backward compat)"

# Category mapping
cat_trusted=$(moira_knowledge_freshness_category "85")
assert_equals "$cat_trusted" "trusted" "category: 85 = trusted"
cat_usable=$(moira_knowledge_freshness_category "50")
assert_equals "$cat_usable" "usable" "category: 50 = usable"
cat_needs=$(moira_knowledge_freshness_category "20")
assert_equals "$cat_needs" "needs-verification" "category: 20 = needs-verification"

# No freshness tag → unknown
NOFRESH_DIR="$TEMP_DIR/nofresh"
mkdir -p "$NOFRESH_DIR/conventions"
echo "no tag here" > "$NOFRESH_DIR/conventions/summary.md"
result=$(moira_knowledge_freshness "$NOFRESH_DIR" "conventions" "50")
assert_equals "$result" "unknown" "freshness: no tag = unknown"

# Old format marker (without λ) still works
OLD_DIR="$TEMP_DIR/old-format"
mkdir -p "$OLD_DIR/patterns"
echo '<!-- moira:freshness task-040 2024-01-15 -->' > "$OLD_DIR/patterns/summary.md"
echo "old format content" >> "$OLD_DIR/patterns/summary.md"
score_old=$(moira_knowledge_freshness_score "$OLD_DIR" "patterns" "45")
if [[ $score_old -ge 0 && $score_old -le 100 ]]; then
  pass "old format marker (without λ) works: score=$score_old"
else
  fail "old format marker failed: score=$score_old"
fi

# ── 5. Stale entry detection ────────────────────────────────────────

STALE_DIR="$TEMP_DIR/stale"
for ktype in project-model conventions decisions patterns failures quality-map libraries; do
  mkdir -p "$STALE_DIR/$ktype"
done
echo "<!-- moira:freshness task-010 2024-01-01 -->" > "$STALE_DIR/project-model/summary.md"
echo "<!-- moira:freshness task-040 2024-02-01 -->" > "$STALE_DIR/conventions/summary.md"

stale_result=$(moira_knowledge_stale_entries "$STALE_DIR" "50")
if echo "$stale_result" | grep -q "project-model"; then
  pass "stale detection finds entries with low confidence"
else
  fail "stale detection missed low-confidence entry"
fi
if echo "$stale_result" | grep -q "conventions"; then
  fail "stale detection incorrectly flagged high-confidence entry"
else
  pass "stale detection correctly skips high-confidence entries"
fi
# Verify confidence score is included in output
if echo "$stale_result" | grep -q "confidence="; then
  pass "stale detection includes confidence score in output"
else
  fail "stale detection missing confidence score"
fi

# ── 6. Archive rotation ─────────────────────────────────────────────

ARCH_DIR="$TEMP_DIR/archive"
mkdir -p "$ARCH_DIR/decisions/archive"

# Create full.md with 25 entries
{
  echo "# Decisions Full"
  echo ""
  for i in $(seq 1 25); do
    printf "## [2024-01-%02d] Decision %d\nContent for decision %d\n\n" "$i" "$i" "$i"
  done
} > "$ARCH_DIR/decisions/full.md"

count_before=$(grep -c '^## ' "$ARCH_DIR/decisions/full.md")
assert_equals "$count_before" "25" "archive: 25 entries before rotation"

moira_knowledge_archive_rotate "$ARCH_DIR" "decisions" 20

count_after=$(grep -c '^## ' "$ARCH_DIR/decisions/full.md")
assert_equals "$count_after" "20" "archive: 20 entries after rotation"

assert_file_exists "$ARCH_DIR/decisions/archive/batch-001.md" "archive: batch-001.md created"

archive_count=$(grep -c '^## ' "$ARCH_DIR/decisions/archive/batch-001.md")
assert_equals "$archive_count" "5" "archive: batch-001.md has 5 entries"

# Second rotation: add more entries, verify batch-002 created
{
  cat "$ARCH_DIR/decisions/full.md"
  for i in $(seq 26 30); do
    printf "## [2024-02-%02d] Decision %d\nContent for decision %d\n\n" "$i" "$i" "$i"
  done
} > "$TEMP_DIR/full-extended.md"
mv "$TEMP_DIR/full-extended.md" "$ARCH_DIR/decisions/full.md"

moira_knowledge_archive_rotate "$ARCH_DIR" "decisions" 20

assert_file_exists "$ARCH_DIR/decisions/archive/batch-002.md" "archive: batch-002.md created (sequential numbering)"
archive2_count=$(grep -c '^## ' "$ARCH_DIR/decisions/archive/batch-002.md")
assert_equals "$archive2_count" "5" "archive: batch-002.md has 5 entries"

# ── 7. Consistency validation ────────────────────────────────────────

CONS_DIR="$TEMP_DIR/consistency"
mkdir -p "$CONS_DIR/conventions"

echo "language: TypeScript
framework: Next.js" > "$CONS_DIR/conventions/summary.md"

# Same keys, same values → confirm
echo "language: TypeScript
framework: Next.js" > "$TEMP_DIR/new-confirm.md"
result=$(moira_knowledge_validate_consistency "$CONS_DIR" "conventions" "$TEMP_DIR/new-confirm.md")
assert_equals "$result" "confirm" "consistency: same values = confirm"

# New keys → extend
echo "language: TypeScript
orm: Prisma" > "$TEMP_DIR/new-extend.md"
result=$(moira_knowledge_validate_consistency "$CONS_DIR" "conventions" "$TEMP_DIR/new-extend.md")
assert_equals "$result" "extend" "consistency: new keys = extend"

# Same key, different value → conflict
echo "language: Python
framework: Django" > "$TEMP_DIR/new-conflict.md"
result=$(moira_knowledge_validate_consistency "$CONS_DIR" "conventions" "$TEMP_DIR/new-conflict.md" 2>/dev/null)
assert_equals "$result" "conflict" "consistency: different values = conflict"

# ── 8. Art 5.1: Knowledge templates include evidence reference guidance ─

# Templates should guide users to include evidence (structural check)
for ktype in decisions patterns failures; do
  full_template="$MOIRA_HOME/templates/knowledge/$ktype/full.md"
  if [[ -f "$full_template" ]]; then
    if grep -qi "evidence\|reference\|source\|task" "$full_template" 2>/dev/null; then
      pass "Art 5.1: $ktype template mentions evidence/references"
    else
      fail "Art 5.1: $ktype template missing evidence guidance"
    fi
  fi
done

test_summary
