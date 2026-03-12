#!/usr/bin/env bash
# test-bootstrap.sh — Verify Phase 5 bootstrap engine artifacts
# Tests scanner templates, stack presets, bootstrap.sh, CLAUDE.md template, init command.

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
# Stack preset tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/templates/stack-presets/generic.yaml" "preset: generic.yaml exists"

# Count non-generic presets
preset_count=$(ls "$MOIRA_HOME/templates/stack-presets/"*.yaml 2>/dev/null | wc -l | tr -d ' ')
if [[ "$preset_count" -ge 6 ]]; then
  pass "preset: $preset_count presets (>=6 including generic)"
else
  fail "preset: expected >=6, found $preset_count"
fi

for preset_file in "$MOIRA_HOME/templates/stack-presets/"*.yaml; do
  [[ -f "$preset_file" ]] || continue
  name=$(basename "$preset_file")
  assert_file_contains "$preset_file" "_meta:" "${name}: has _meta section"
  assert_file_contains "$preset_file" "stack:" "${name}: has stack section"
  assert_file_contains "$preset_file" "conventions:" "${name}: has conventions section"
  assert_file_contains "$preset_file" "patterns:" "${name}: has patterns section"
  assert_file_contains "$preset_file" "boundaries:" "${name}: has boundaries section"
done

# generic.yaml has stack_id: generic
assert_file_contains "$MOIRA_HOME/templates/stack-presets/generic.yaml" "stack_id: generic" "generic.yaml: has stack_id: generic"

# Check all stack_ids are unique
all_ids=$(grep 'stack_id:' "$MOIRA_HOME/templates/stack-presets/"*.yaml 2>/dev/null | sed 's/.*stack_id:[[:space:]]*//' | sort)
unique_ids=$(echo "$all_ids" | sort -u)
if [[ "$all_ids" == "$unique_ids" ]]; then
  pass "preset: all stack_id values are unique"
else
  fail "preset: duplicate stack_id values found"
fi

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

  for func in moira_bootstrap_match_preset moira_bootstrap_generate_config moira_bootstrap_generate_project_rules moira_bootstrap_populate_knowledge moira_bootstrap_inject_claude_md moira_bootstrap_setup_gitignore; do
    if grep -q "$func" "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
      pass "bootstrap.sh: function $func declared"
    else
      fail "bootstrap.sh: function $func not found"
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
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "NEVER read" "template: has orchestrator NEVER rules"
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

  # Check all steps present
  for step_num in 1 2 3 4 5 6 7 8 9 10; do
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

  # ── Preset matching: nextjs ──
  TEST_SUB6="$TEST_DIR/sub6"
  mkdir -p "$TEST_SUB6"
  cat > "$TEST_SUB6/tech-scan.md" << 'EOF'
## Framework
- Name: Next.js 14.1
- Type: web

## Build & Tooling
- Package manager: npm
EOF

  result=$(moira_bootstrap_match_preset "$TEST_SUB6/tech-scan.md" "$MOIRA_HOME/templates/stack-presets")
  if [[ "$result" == "nextjs.yaml" ]]; then
    pass "preset match: nextjs scan → nextjs.yaml"
  else
    fail "preset match: expected nextjs.yaml, got $result"
  fi

  # ── Preset matching: unknown stack ──
  cat > "$TEST_SUB6/unknown-scan.md" << 'EOF'
## Framework
- Name: SomeObscureFramework 1.0
EOF

  result=$(moira_bootstrap_match_preset "$TEST_SUB6/unknown-scan.md" "$MOIRA_HOME/templates/stack-presets")
  if [[ "$result" == "generic.yaml" ]]; then
    pass "preset match: unknown stack → generic.yaml"
  else
    fail "preset match: expected generic.yaml, got $result"
  fi
fi

test_summary
