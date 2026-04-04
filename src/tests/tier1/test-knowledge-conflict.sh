#!/usr/bin/env bash
# test-knowledge-conflict.sh — Tier 1 tests for knowledge conflict detection (D-221)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Knowledge Conflict Detection (D-221)"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source knowledge.sh (re-set +e after: library enables -e which breaks tests)
source "$SRC_DIR/global/lib/knowledge.sh"
set +e

# ── Setup: knowledge dir with decisions/full.md ──
mkdir -p "$TEMP_DIR/decisions/archive"
mkdir -p "$TEMP_DIR/patterns/archive"

cat > "$TEMP_DIR/decisions/full.md" << 'EOF'
# Decisions Full

## Decision: Use PostgreSQL for persistence
Content about PostgreSQL choice...

## Decision: Error handling strategy
Content about error handling...

## Decision: Use Redis for caching
Content about Redis...
EOF

# ── 1. Exact header collision detected ──
moira_knowledge_conflict_check "## Decision: Use PostgreSQL for persistence" "$TEMP_DIR/decisions/full.md"
rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "conflict check: exact header collision returns 1"
else
  fail "conflict check: expected rc=1 for exact collision, got $rc"
fi

# ── 2. Different header passes ──
moira_knowledge_conflict_check "## Decision: Use MongoDB for persistence" "$TEMP_DIR/decisions/full.md"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "conflict check: different header returns 0"
else
  fail "conflict check: expected rc=0 for different header, got $rc"
fi

# ── 3. Substring non-match (critical: grep -xF not -F) ──
moira_knowledge_conflict_check "## Decision: Use PostgreSQL" "$TEMP_DIR/decisions/full.md"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "conflict check: substring does NOT match (exact line only)"
else
  fail "conflict check: substring should NOT conflict (got rc=1)"
fi

# ── 4. Superset non-match ──
moira_knowledge_conflict_check "## Decision: Use PostgreSQL for persistence and replication" "$TEMP_DIR/decisions/full.md"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "conflict check: superset header does NOT match"
else
  fail "conflict check: superset should NOT conflict"
fi

# ── 5. Empty full.md → no conflict ──
echo "" > "$TEMP_DIR/decisions/empty.md"
moira_knowledge_conflict_check "## Decision: Anything" "$TEMP_DIR/decisions/empty.md"
rc=$?
assert_exit_code 0 "$rc" "conflict check: empty file returns 0"

# ── 6. Missing full.md → no conflict ──
moira_knowledge_conflict_check "## Decision: Anything" "$TEMP_DIR/nonexistent.md"
rc=$?
assert_exit_code 0 "$rc" "conflict check: missing file returns 0"

# ── 7. Contested write creates contested.md ──
cat > "$TEMP_DIR/new-content.md" << 'EOF'
Use PostgreSQL with Prisma connection management
instead of PgBouncer...
EOF

moira_knowledge_write_contested "$TEMP_DIR" "decisions" "## Decision: Use PostgreSQL for persistence" "$TEMP_DIR/new-content.md" "T-078"
assert_file_exists "$TEMP_DIR/decisions/contested.md" "contested write: contested.md created"
assert_file_contains "$TEMP_DIR/decisions/contested.md" "CONTESTED" "contested write: contains CONTESTED header"
assert_file_contains "$TEMP_DIR/decisions/contested.md" "T-078" "contested write: contains new task_id"
assert_file_contains "$TEMP_DIR/decisions/contested.md" "Prisma" "contested write: contains new content"

# ── 8. Third conflict appends to existing contested ──
cat > "$TEMP_DIR/third-content.md" << 'EOF'
Use PostgreSQL with Supabase managed connections...
EOF

moira_knowledge_write_contested "$TEMP_DIR" "decisions" "## Decision: Use PostgreSQL for persistence" "$TEMP_DIR/third-content.md" "T-099"
assert_file_contains "$TEMP_DIR/decisions/contested.md" "T-099" "contested write: third version appended"
assert_file_contains "$TEMP_DIR/decisions/contested.md" "Supabase" "contested write: third content present"

# ── 9. Guard clause bypass: quality-map L1 (graph.sh path) ──
# moira_knowledge_write for quality-map L1 should NOT check conflicts
mkdir -p "$TEMP_DIR/quality-map"
cat > "$TEMP_DIR/quality-map/summary.md" << 'EOF'
## Quality Summary
Some existing content
EOF
cat > "$TEMP_DIR/qm-content.md" << 'EOF'
## Quality Summary
Updated quality content
EOF
moira_knowledge_write "$TEMP_DIR" "quality-map" "L1" "$TEMP_DIR/qm-content.md" "T-100"
# Should write to summary.md, NOT to contested.md
if [[ ! -f "$TEMP_DIR/quality-map/contested.md" ]]; then
  pass "guard clause: quality-map L1 bypasses conflict check"
else
  fail "guard clause: quality-map L1 should NOT create contested.md"
fi

# ── 10. Guard clause bypass: decisions L0 ──
mkdir -p "$TEMP_DIR/decisions"
cat > "$TEMP_DIR/decisions/index.md" << 'EOF'
## Decision: Use PostgreSQL for persistence
One-liner summary
EOF
cat > "$TEMP_DIR/l0-content.md" << 'EOF'
## Decision: Use PostgreSQL for persistence
Updated one-liner
EOF
# Remove any contested.md from earlier tests for clean check
rm -f "$TEMP_DIR/decisions/contested.md" 2>/dev/null
moira_knowledge_write "$TEMP_DIR" "decisions" "L0" "$TEMP_DIR/l0-content.md" "T-101"
if [[ ! -f "$TEMP_DIR/decisions/contested.md" ]]; then
  pass "guard clause: decisions L0 bypasses conflict check"
else
  fail "guard clause: decisions L0 should NOT trigger conflict check"
fi

# ── 11. Guard clause fires: decisions L2 with duplicate header ──
# Re-create contested state: full.md has the header, write L2 with same header
rm -f "$TEMP_DIR/decisions/contested.md" 2>/dev/null
cat > "$TEMP_DIR/l2-content.md" << 'EOF'
## Decision: Use PostgreSQL for persistence
New conflicting content for L2 write
EOF
moira_knowledge_write "$TEMP_DIR" "decisions" "L2" "$TEMP_DIR/l2-content.md" "T-102"
if [[ -f "$TEMP_DIR/decisions/contested.md" ]]; then
  pass "guard clause: decisions L2 duplicate → contested.md created"
else
  fail "guard clause: decisions L2 with duplicate header should create contested.md"
fi

# ── 12. Guard clause pass-through: decisions L2 with new header ──
rm -f "$TEMP_DIR/decisions/contested.md" 2>/dev/null
cat > "$TEMP_DIR/l2-new-content.md" << 'EOF'
## Decision: Use GraphQL for API layer
Brand new decision content
EOF
moira_knowledge_write "$TEMP_DIR" "decisions" "L2" "$TEMP_DIR/l2-new-content.md" "T-103"
if [[ ! -f "$TEMP_DIR/decisions/contested.md" ]]; then
  pass "guard clause: decisions L2 new header → normal write (no contested)"
else
  fail "guard clause: new header should NOT create contested.md"
fi

test_summary
