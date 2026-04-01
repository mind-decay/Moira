#!/usr/bin/env bash
# test-markdown-utils.sh — Tier 1 tests for markdown extraction (D-201)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Markdown Utils (D-201)"

# ── Setup ──
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

source "$SRC_DIR/global/lib/markdown-utils.sh"

# ── Test file with various section types ──
cat > "$TEST_TMP/test.md" << 'EOF'
# Top Level Header

Some intro text.

## Problem Statement

This is the problem statement.
It has multiple lines.

### Nested Subsection

With nested content.

## Scope

### In Scope
- Item 1
- Item 2

### Out of Scope
- Item 3

## Empty Section

## Acceptance Criteria

1. Criterion one
2. Criterion two
3. Criterion three
EOF

# ── Test 1: Basic section extraction ──
result=$(moira_md_extract_section "$TEST_TMP/test.md" "Problem Statement")
if echo "$result" | grep -q "This is the problem statement"; then
  pass "extracts basic section content"
else
  fail "should extract basic section content"
fi

# ── Test 2: Nested subsections included ──
if echo "$result" | grep -q "### Nested Subsection"; then
  pass "includes nested ### subsections"
else
  fail "should include nested ### subsections"
fi
if echo "$result" | grep -q "With nested content"; then
  pass "includes nested subsection content"
else
  fail "should include nested subsection content"
fi

# ── Test 3: Section with nested ### children ──
scope=$(moira_md_extract_section "$TEST_TMP/test.md" "Scope")
if echo "$scope" | grep -q "### In Scope"; then
  pass "scope includes In Scope subsection"
else
  fail "scope should include In Scope subsection"
fi
if echo "$scope" | grep -q "### Out of Scope"; then
  pass "scope includes Out of Scope subsection"
else
  fail "scope should include Out of Scope subsection"
fi
if echo "$scope" | grep -q "Item 3"; then
  pass "scope includes all items"
else
  fail "scope should include Item 3"
fi

# ── Test 4: Empty section ──
empty=$(moira_md_extract_section "$TEST_TMP/test.md" "Empty Section")
rc=$?
assert_equals "0" "$rc" "empty section returns exit 0"

# ── Test 5: Section at EOF ──
eof_section=$(moira_md_extract_section "$TEST_TMP/test.md" "Acceptance Criteria")
if echo "$eof_section" | grep -q "Criterion one"; then
  pass "extracts section at EOF"
else
  fail "should extract section at EOF"
fi
if echo "$eof_section" | grep -q "Criterion three"; then
  pass "EOF section includes last line"
else
  fail "EOF section should include last line"
fi

# ── Test 6: Missing section returns exit 1 ──
rc=0
moira_md_extract_section "$TEST_TMP/test.md" "Nonexistent" >/dev/null 2>&1 || rc=$?
assert_equals "1" "$rc" "missing section returns exit 1"

# ── Test 7: Missing file returns exit 1 ──
rc=0
moira_md_extract_section "$TEST_TMP/no-such-file.md" "Scope" >/dev/null 2>&1 || rc=$?
assert_equals "1" "$rc" "missing file returns exit 1"

# ── Test 8: Section with trailing whitespace ──
cat > "$TEST_TMP/whitespace.md" << 'EOF'
## Problem Statement

Content here.

## Next
EOF
ws_result=$(moira_md_extract_section "$TEST_TMP/whitespace.md" "Problem Statement")
if echo "$ws_result" | grep -q "Content here"; then
  pass "handles heading with trailing whitespace"
else
  fail "should handle heading with trailing whitespace"
fi

# ── Test 9: Multi-section extraction ──
multi=$(moira_md_extract_sections "$TEST_TMP/test.md" "Scope" "Acceptance Criteria" "Nonexistent")
if echo "$multi" | grep -q "### Scope"; then
  pass "multi-section includes Scope"
else
  fail "multi-section should include Scope"
fi
if echo "$multi" | grep -q "### Acceptance Criteria"; then
  pass "multi-section includes Acceptance Criteria"
else
  fail "multi-section should include Acceptance Criteria"
fi
# Nonexistent should be silently skipped
if ! echo "$multi" | grep -q "Nonexistent"; then
  pass "multi-section skips missing sections"
else
  fail "multi-section should skip missing sections"
fi

# ── Test 10: Unicode content ──
cat > "$TEST_TMP/unicode.md" << 'EOF'
## Рекомендация

Используйте паттерн Observer для событий.

## Следующий раздел
EOF
unicode_result=$(moira_md_extract_section "$TEST_TMP/unicode.md" "Рекомендация")
if echo "$unicode_result" | grep -q "Observer"; then
  pass "handles Unicode content"
else
  fail "should handle Unicode content"
fi

test_summary
