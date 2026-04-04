#!/usr/bin/env bash
# test-knowledge-archival.sh — Tier 1 tests for knowledge archival rotation (D-218)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Knowledge Archival Rotation (D-218)"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

source "$SRC_DIR/global/lib/knowledge.sh"
set +e

# ── 1. Rotation creates batch when entries > max ──
mkdir -p "$TEMP_DIR/k1/decisions/archive"
{
  echo "# Decisions Full"
  echo ""
  for i in $(seq 1 25); do
    printf "## [2024-01-%02d] Decision %d\nContent for decision %d\n\n" "$i" "$i" "$i"
  done
} > "$TEMP_DIR/k1/decisions/full.md"

moira_knowledge_archive_rotate "$TEMP_DIR/k1" "decisions" 20
count_after=$(grep -c '^## ' "$TEMP_DIR/k1/decisions/full.md")
assert_equals "$count_after" "20" "rotation: 25→20 entries after max_entries=20"
assert_file_exists "$TEMP_DIR/k1/decisions/archive/batch-001.md" "rotation: batch-001.md created"
archive_count=$(grep -c '^## ' "$TEMP_DIR/k1/decisions/archive/batch-001.md")
assert_equals "$archive_count" "5" "rotation: batch has 5 archived entries"

# ── 2. No rotation when count ≤ max ──
mkdir -p "$TEMP_DIR/k2/decisions/archive"
{
  echo "# Decisions Full"
  echo ""
  for i in $(seq 1 10); do
    printf "## Decision %d\nContent %d\n\n" "$i" "$i"
  done
} > "$TEMP_DIR/k2/decisions/full.md"

moira_knowledge_archive_rotate "$TEMP_DIR/k2" "decisions" 20
if [[ ! -f "$TEMP_DIR/k2/decisions/archive/batch-001.md" ]]; then
  pass "no rotation: count <= max_entries"
else
  fail "no rotation: should not create batch when count <= max"
fi

# ── 3. Custom max_entries from config ──
mkdir -p "$TEMP_DIR/k3/decisions/archive"
{
  echo "# Decisions Full"
  echo ""
  for i in $(seq 1 15); do
    printf "## Decision %d\nContent %d\n\n" "$i" "$i"
  done
} > "$TEMP_DIR/k3/decisions/full.md"

moira_knowledge_archive_rotate "$TEMP_DIR/k3" "decisions" 10
count_after=$(grep -c '^## ' "$TEMP_DIR/k3/decisions/full.md")
assert_equals "$count_after" "10" "custom max: 15→10 with max_entries=10"

# ── 4. Sequential batch numbering ──
moira_knowledge_archive_rotate "$TEMP_DIR/k1" "decisions" 15
# Should create batch-002 (batch-001 already exists)
assert_file_exists "$TEMP_DIR/k1/decisions/archive/batch-002.md" "sequential: batch-002 created"

# ── 5. Patterns type also supported ──
mkdir -p "$TEMP_DIR/k5/patterns/archive"
{
  echo "# Patterns Full"
  echo ""
  for i in $(seq 1 25); do
    printf "## Pattern %d\nContent %d\n\n" "$i" "$i"
  done
} > "$TEMP_DIR/k5/patterns/full.md"

moira_knowledge_archive_rotate "$TEMP_DIR/k5" "patterns" 20
assert_file_exists "$TEMP_DIR/k5/patterns/archive/batch-001.md" "patterns: rotation works for patterns type"

# ── 6. Invalid type rejected ──
result=$(moira_knowledge_archive_rotate "$TEMP_DIR/k5" "quality-map" 20 2>&1) || true
if echo "$result" | grep -q "Error"; then
  pass "invalid type: quality-map rejected"
else
  fail "invalid type: quality-map should be rejected"
fi

# ── 7. Missing full.md → no-op ──
mkdir -p "$TEMP_DIR/k7/decisions/archive"
moira_knowledge_archive_rotate "$TEMP_DIR/k7" "decisions" 20
rc=$?
assert_exit_code 0 "$rc" "missing full.md: returns 0 (no-op)"

# ── 8. Idempotency: double rotation same state ──
mkdir -p "$TEMP_DIR/k8/decisions/archive"
{
  echo "# Decisions"
  for i in $(seq 1 25); do printf "## D%d\nC%d\n\n" "$i" "$i"; done
} > "$TEMP_DIR/k8/decisions/full.md"
moira_knowledge_archive_rotate "$TEMP_DIR/k8" "decisions" 20
moira_knowledge_archive_rotate "$TEMP_DIR/k8" "decisions" 20
count=$(grep -c '^## ' "$TEMP_DIR/k8/decisions/full.md")
assert_equals "$count" "20" "idempotency: double rotation still has 20 entries"

test_summary
