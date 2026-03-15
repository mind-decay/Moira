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

for ktype in project-model conventions decisions patterns failures quality-map; do
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
for ktype in project-model conventions decisions patterns failures quality-map; do
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

# Use the real matrix file
MATRIX_FILE="$MOIRA_HOME/core/knowledge-access-matrix.yaml"

# Hermes: only project-model L0
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "hermes" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-index" && ! echo "$result" | grep -q "conv-" && ! echo "$result" | grep -q "fail-" && ! echo "$result" | grep -q "qm-"; then
  pass "hermes gets only project-model L0"
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

# Mnemosyne: all 6 types at L2
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "mnemosyne" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-full" && echo "$result" | grep -q "conv-full" && echo "$result" | grep -q "dec-full" && echo "$result" | grep -q "pat-full" && echo "$result" | grep -q "qm-full" && echo "$result" | grep -q "fail-full"; then
  pass "mnemosyne gets all 6 types at L2"
else
  fail "mnemosyne access incorrect: $result"
fi

# Output contains section headers
if echo "$result" | grep -q "## Knowledge:"; then
  pass "output contains section headers"
else
  fail "output missing section headers"
fi

# Daedalus: project-model L1 + conventions L1 + decisions L0 + patterns L0 + quality-map L2
result=$(moira_knowledge_read_for_agent "$AGENT_KNOW_DIR" "daedalus" "$MATRIX_FILE")
if echo "$result" | grep -q "pm-summary" && echo "$result" | grep -q "conv-summary" && echo "$result" | grep -q "dec-index" && echo "$result" | grep -q "pat-index" && echo "$result" | grep -q "qm-full"; then
  pass "daedalus gets project-model L1 + conventions L1 + decisions L0 + patterns L0 + quality-map L2"
else
  fail "daedalus access incorrect: $result"
fi

# ── 4. Freshness markers ─────────────────────────────────────────────

FRESH_DIR="$TEMP_DIR/freshness"
mkdir -p "$FRESH_DIR/project-model"

# Write knowledge with task ID
echo "test content" > "$TEMP_DIR/content.md"
moira_knowledge_write "$FRESH_DIR" "project-model" "L1" "$TEMP_DIR/content.md" "task-2024-01-15-042"

# Check freshness tag exists
if grep -q '<!-- moira:freshness task-2024-01-15-042' "$FRESH_DIR/project-model/summary.md"; then
  pass "write adds freshness tag"
else
  fail "freshness tag not found after write"
fi

# Check content is present
if grep -q "test content" "$FRESH_DIR/project-model/summary.md"; then
  pass "write preserves content"
else
  fail "content not found after write"
fi

# Freshness categorization: fresh (<10 tasks)
result=$(moira_knowledge_freshness "$FRESH_DIR" "project-model" "45")
assert_equals "$result" "fresh" "freshness: distance 3 = fresh"

# Freshness categorization: aging (10-20 tasks)
result=$(moira_knowledge_freshness "$FRESH_DIR" "project-model" "55")
assert_equals "$result" "aging" "freshness: distance 13 = aging"

# Freshness categorization: stale (>20 tasks)
result=$(moira_knowledge_freshness "$FRESH_DIR" "project-model" "70")
assert_equals "$result" "stale" "freshness: distance 28 = stale"

# No freshness tag → unknown
NOFRESH_DIR="$TEMP_DIR/nofresh"
mkdir -p "$NOFRESH_DIR/conventions"
echo "no tag here" > "$NOFRESH_DIR/conventions/summary.md"
result=$(moira_knowledge_freshness "$NOFRESH_DIR" "conventions" "50")
assert_equals "$result" "unknown" "freshness: no tag = unknown"

# ── 5. Stale entry detection ────────────────────────────────────────

STALE_DIR="$TEMP_DIR/stale"
for ktype in project-model conventions decisions patterns failures quality-map; do
  mkdir -p "$STALE_DIR/$ktype"
done
echo "<!-- moira:freshness task-010 2024-01-01 -->" > "$STALE_DIR/project-model/summary.md"
echo "<!-- moira:freshness task-040 2024-02-01 -->" > "$STALE_DIR/conventions/summary.md"

stale_result=$(moira_knowledge_stale_entries "$STALE_DIR" "50")
if echo "$stale_result" | grep -q "project-model"; then
  pass "stale detection finds entries older than 20 tasks"
else
  fail "stale detection missed old entry"
fi
if echo "$stale_result" | grep -q "conventions"; then
  fail "stale detection incorrectly flagged fresh entry"
else
  pass "stale detection correctly skips fresh entries"
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
