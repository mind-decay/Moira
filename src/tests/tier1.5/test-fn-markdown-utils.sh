#!/usr/bin/env bash
# test-fn-markdown-utils.sh — Functional tests for markdown-utils.sh
# Tests section extraction from markdown files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: markdown-utils.sh (functional)"

source "$SRC_LIB_DIR/markdown-utils.sh"
set +e

# ── Setup: create test markdown ──────────────────────────────────────

cat > "$TEMP_DIR/doc.md" << 'EOF'
# Top Level

Some intro text.

## Section One

Content of section one.
More content here.

### Subsection A

Nested content.

## Section Two

Content of section two.

## Section Three

Content of section three.
Last line.
EOF

# ── moira_md_extract_section: basic extraction ───────────────────────

run_fn moira_md_extract_section "$TEMP_DIR/doc.md" "Section One"
assert_exit_zero "extract_section: found → exit 0"
assert_output_contains "$FN_STDOUT" "Content of section one" "extract_section: returns content"
assert_output_contains "$FN_STDOUT" "Subsection A" "extract_section: includes nested subsections"
assert_output_not_contains "$FN_STDOUT" "Content of section two" "extract_section: stops at next ## heading"

# ── moira_md_extract_section: last section (to EOF) ──────────────────

run_fn moira_md_extract_section "$TEMP_DIR/doc.md" "Section Three"
assert_exit_zero "extract_section: last section → exit 0"
assert_output_contains "$FN_STDOUT" "Content of section three" "extract_section: last section content"
assert_output_contains "$FN_STDOUT" "Last line" "extract_section: includes to EOF"

# ── moira_md_extract_section: not found ──────────────────────────────

run_fn moira_md_extract_section "$TEMP_DIR/doc.md" "Nonexistent Section"
assert_exit_nonzero "extract_section: not found → exit 1"

# ── moira_md_extract_section: nonexistent file ───────────────────────

run_fn moira_md_extract_section "$TEMP_DIR/nonexistent.md" "Section One"
assert_exit_nonzero "extract_section: missing file → exit 1"

# ── moira_md_extract_section: empty section ──────────────────────────

cat > "$TEMP_DIR/empty-section.md" << 'EOF'
## Empty Section

## Next Section

Has content.
EOF

run_fn moira_md_extract_section "$TEMP_DIR/empty-section.md" "Empty Section"
assert_exit_zero "extract_section: empty section → exit 0"

# ── moira_md_extract_sections: multiple sections ─────────────────────

run_fn moira_md_extract_sections "$TEMP_DIR/doc.md" "Section One" "Section Three"
assert_exit_zero "extract_sections: found → exit 0"
assert_output_contains "$FN_STDOUT" "Content of section one" "extract_sections: includes first section"
assert_output_contains "$FN_STDOUT" "Content of section three" "extract_sections: includes second section"

# ── moira_md_extract_sections: none found ────────────────────────────

run_fn moira_md_extract_sections "$TEMP_DIR/doc.md" "Nonexistent A" "Nonexistent B"
assert_exit_nonzero "extract_sections: none found → exit 1"

test_summary
