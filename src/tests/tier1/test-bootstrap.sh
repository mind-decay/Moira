#!/usr/bin/env bash
# test-bootstrap.sh — Verify Phase 5 bootstrap engine artifacts
# Tests scanner templates, bootstrap.sh, CLAUDE.md template, init command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
COMMANDS_DIR="$HOME/.claude/commands/moira"

# ═══════════════════════════════════════════════════════════════════════
# Scanner template tests
# ═══════════════════════════════════════════════════════════════════════

for scanner in tech-scan structure-scan convention-scan pattern-scan; do
  assert_file_exists "$MOIRA_HOME/templates/scanners/${scanner}.md" "scanner template: ${scanner}.md exists"
done

for scanner in tech-scan structure-scan convention-scan pattern-scan; do
  tmpl="$MOIRA_HOME/templates/scanners/${scanner}.md"
  if [[ -f "$tmpl" ]]; then
    assert_file_contains "$tmpl" "## Objective" "${scanner}: has Objective section"
    assert_file_contains "$tmpl" "## Scan Strategy" "${scanner}: has Scan Strategy section"
    assert_file_contains "$tmpl" "## Output Format" "${scanner}: has Output Format section"
    assert_file_contains "$tmpl" "## Output Path" "${scanner}: has Output Path section"
    assert_file_contains "$tmpl" "## Constraints" "${scanner}: has Constraints section"
    assert_file_contains "$tmpl" "NO opinions" "${scanner}: has Explorer NEVER constraints"
    assert_file_contains "$tmpl" ".claude/moira/" "${scanner}: output path under .claude/moira/"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# Bootstrap library tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/lib/bootstrap.sh" "bootstrap.sh exists"

if [[ -f "$MOIRA_HOME/lib/bootstrap.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
    pass "bootstrap.sh syntax valid"
  else
    fail "bootstrap.sh has syntax errors"
  fi

  for func in moira_bootstrap_generate_config moira_bootstrap_generate_project_rules \
              moira_bootstrap_populate_knowledge moira_bootstrap_inject_claude_md \
              moira_bootstrap_setup_gitignore moira_bootstrap_inject_hooks \
              _moira_parse_frontmatter _moira_parse_frontmatter_list; do
    if grep -q "$func" "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
      pass "bootstrap.sh: function $func declared"
    else
      fail "bootstrap.sh: function $func not found"
    fi
  done

  # Verify deleted functions are gone
  for func in moira_bootstrap_match_preset _extract_scan_value \
              _extract_table_value _extract_preset_field; do
    if grep -q "^${func}()" "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
      fail "bootstrap.sh: deleted function $func still exists"
    else
      pass "bootstrap.sh: function $func correctly removed"
    fi
  done
fi

# ═══════════════════════════════════════════════════════════════════════
# CLAUDE.md template tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/templates/project-claude-md.tmpl" "CLAUDE.md template exists"

if [[ -f "$MOIRA_HOME/templates/project-claude-md.tmpl" ]]; then
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "<!-- moira:start -->" "template: has moira:start marker"
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "<!-- moira:end -->" "template: has moira:end marker"
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "Moira Orchestration System" "template: has heading"
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "/moira:task" "template: has /moira:task reference"
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "NEVER" "template: has orchestrator NEVER rules"
fi

# ═══════════════════════════════════════════════════════════════════════
# Init command tests
# ═══════════════════════════════════════════════════════════════════════

init_file="$COMMANDS_DIR/init.md"
assert_file_exists "$init_file" "init.md exists"

if [[ -f "$init_file" ]]; then
  assert_file_contains "$init_file" "name: moira:init" "init.md: has correct name"
  assert_file_contains "$init_file" "Agent" "init.md: allowed-tools includes Agent"
  assert_file_contains "$init_file" "Read" "init.md: allowed-tools includes Read"
  assert_file_contains "$init_file" "Write" "init.md: allowed-tools includes Write"
  assert_file_contains "$init_file" "Bash" "init.md: allowed-tools includes Bash"

  # Check not a stub (more than 20 lines of content)
  line_count=$(wc -l < "$init_file" | tr -d ' ')
  if [[ "$line_count" -gt 20 ]]; then
    pass "init.md: not a stub ($line_count lines)"
  else
    fail "init.md: appears to be a stub ($line_count lines)"
  fi

  # Check all steps present (11 steps after Phase 8 hook injection step)
  for step_num in 1 2 3 4 5 6 7 8 9 10 11; do
    assert_file_contains "$init_file" "Step ${step_num}" "init.md: Step $step_num present"
  done

  # Check approval gate
  assert_file_contains "$init_file" "APPROVAL GATE" "init.md: has approval gate"
fi

# ═══════════════════════════════════════════════════════════════════════
# Functional tests (in temp dir)
# ═══════════════════════════════════════════════════════════════════════

# Source bootstrap.sh for functional tests
if [[ -f "$MOIRA_HOME/lib/bootstrap.sh" ]]; then
  source "$MOIRA_HOME/lib/bootstrap.sh"

  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' EXIT

  # All sub-tests use subdirs of TEST_DIR for reliable cleanup
  TEST_SUBDIR="$TEST_DIR/sub1"
  mkdir -p "$TEST_SUBDIR"

  # ── CLAUDE.md injection: empty dir ──
  moira_bootstrap_inject_claude_md "$TEST_SUBDIR" "$MOIRA_HOME"
  if [[ -f "$TEST_SUBDIR/.claude/CLAUDE.md" ]]; then
    pass "inject CLAUDE.md: creates file in empty dir"
    assert_file_contains "$TEST_SUBDIR/.claude/CLAUDE.md" "<!-- moira:start -->" "inject CLAUDE.md: has start marker"
    assert_file_contains "$TEST_SUBDIR/.claude/CLAUDE.md" "<!-- moira:end -->" "inject CLAUDE.md: has end marker"
  else
    fail "inject CLAUDE.md: file not created"
  fi

  # ── CLAUDE.md injection: existing without markers ──
  TEST_SUB2="$TEST_DIR/sub2"
  mkdir -p "$TEST_SUB2/.claude"
  echo "# Existing Project Rules" > "$TEST_SUB2/.claude/CLAUDE.md"
  echo "Some existing content" >> "$TEST_SUB2/.claude/CLAUDE.md"

  moira_bootstrap_inject_claude_md "$TEST_SUB2" "$MOIRA_HOME"
  if grep -q "Existing Project Rules" "$TEST_SUB2/.claude/CLAUDE.md" && \
     grep -q "<!-- moira:start -->" "$TEST_SUB2/.claude/CLAUDE.md"; then
    pass "inject CLAUDE.md: preserves existing + appends markers"
  else
    fail "inject CLAUDE.md: lost existing content or missing markers"
  fi

  # ── CLAUDE.md injection: existing WITH markers (idempotent) ──
  TEST_SUB3="$TEST_DIR/sub3"
  mkdir -p "$TEST_SUB3/.claude"
  cat > "$TEST_SUB3/.claude/CLAUDE.md" << 'EOF'
# My Project
Some rules here.

<!-- moira:start -->
Old moira content
<!-- moira:end -->

# More stuff
Other content below.
EOF

  moira_bootstrap_inject_claude_md "$TEST_SUB3" "$MOIRA_HOME"
  if grep -q "My Project" "$TEST_SUB3/.claude/CLAUDE.md" && \
     grep -q "More stuff" "$TEST_SUB3/.claude/CLAUDE.md" && \
     grep -q "Moira Orchestration System" "$TEST_SUB3/.claude/CLAUDE.md" && \
     ! grep -q "Old moira content" "$TEST_SUB3/.claude/CLAUDE.md"; then
    pass "inject CLAUDE.md: replaces between markers, preserves surrounding"
  else
    fail "inject CLAUDE.md: idempotent replacement failed"
  fi

  # ── Gitignore: empty dir ──
  TEST_SUB4="$TEST_DIR/sub4"
  mkdir -p "$TEST_SUB4"
  moira_bootstrap_setup_gitignore "$TEST_SUB4"
  if [[ -f "$TEST_SUB4/.gitignore" ]] && grep -q ".claude/moira/state/tasks/" "$TEST_SUB4/.gitignore"; then
    pass "gitignore: creates .gitignore with moira entries"
  else
    fail "gitignore: failed to create with entries"
  fi

  # ── Gitignore: existing file ──
  TEST_SUB5="$TEST_DIR/sub5"
  mkdir -p "$TEST_SUB5"
  echo "node_modules/" > "$TEST_SUB5/.gitignore"
  moira_bootstrap_setup_gitignore "$TEST_SUB5"
  if grep -q "node_modules/" "$TEST_SUB5/.gitignore" && \
     grep -q ".claude/moira/state/tasks/" "$TEST_SUB5/.gitignore"; then
    pass "gitignore: appends to existing, preserves content"
  else
    fail "gitignore: failed to append or lost existing content"
  fi

  # ── Gitignore: idempotent (no duplicates) ──
  moira_bootstrap_setup_gitignore "$TEST_SUB5"
  dup_count=$(grep -c ".claude/moira/state/tasks/" "$TEST_SUB5/.gitignore" || true)
  if [[ "$dup_count" -eq 1 ]]; then
    pass "gitignore: idempotent — no duplicates"
  else
    fail "gitignore: duplicate entries found ($dup_count)"
  fi

  # ═══════════════════════════════════════════════════════════════════════
  # Frontmatter parser tests
  # ═══════════════════════════════════════════════════════════════════════

  FM_TEST="$TEST_DIR/fm-test.md"
  cat > "$FM_TEST" << 'EOF'
---
language: TypeScript
framework: SvelteKit
runtime: Node.js
max_line_length: 100
entry_points:
  - src/app.html
  - src/hooks.server.ts
do_not_modify:
  - node_modules/
  - .svelte-kit/
---

## Body Content
framework: This should not be parsed
EOF

  # Scalar: existing field
  result=$(_moira_parse_frontmatter "$FM_TEST" "language")
  if [[ "$result" == "TypeScript" ]]; then
    pass "frontmatter: scalar field extraction"
  else
    fail "frontmatter: expected 'TypeScript', got '$result'"
  fi

  # Scalar: numeric value
  result=$(_moira_parse_frontmatter "$FM_TEST" "max_line_length")
  if [[ "$result" == "100" ]]; then
    pass "frontmatter: numeric value as string"
  else
    fail "frontmatter: expected '100', got '$result'"
  fi

  # Scalar: missing field
  result=$(_moira_parse_frontmatter "$FM_TEST" "nonexistent")
  if [[ -z "$result" ]]; then
    pass "frontmatter: missing field returns empty"
  else
    fail "frontmatter: expected empty, got '$result'"
  fi

  # Scalar: ignores body content
  result=$(_moira_parse_frontmatter "$FM_TEST" "framework")
  if [[ "$result" == "SvelteKit" ]]; then
    pass "frontmatter: returns frontmatter value, ignores body"
  else
    fail "frontmatter: expected 'SvelteKit', got '$result'"
  fi

  # List: extraction
  result=$(_moira_parse_frontmatter_list "$FM_TEST" "entry_points")
  expected="src/app.html
src/hooks.server.ts"
  if [[ "$result" == "$expected" ]]; then
    pass "frontmatter: list extraction"
  else
    fail "frontmatter: list mismatch, got '$result'"
  fi

  # List: missing field
  result=$(_moira_parse_frontmatter_list "$FM_TEST" "nonexistent")
  if [[ -z "$result" ]]; then
    pass "frontmatter: missing list returns empty"
  else
    fail "frontmatter: expected empty list, got '$result'"
  fi

  # List: do_not_modify extraction
  result=$(_moira_parse_frontmatter_list "$FM_TEST" "do_not_modify")
  expected="node_modules/
.svelte-kit/"
  if [[ "$result" == "$expected" ]]; then
    pass "frontmatter: do_not_modify list extraction"
  else
    fail "frontmatter: do_not_modify mismatch, got '$result'"
  fi
fi

test_summary
