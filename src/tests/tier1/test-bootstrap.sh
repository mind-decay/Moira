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

for scanner in tech-scan structure-scan convention-scan pattern-scan mcp-scan; do
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
    assert_file_contains "$tmpl" ".moira/" "${scanner}: output path under .moira/"
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
              moira_bootstrap_scan_mcp \
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

  # Check all steps present (12 steps after Phase 9 MCP discovery step)
  for step_num in 1 2 3 4 5 6 7 8 9 10 11 12; do
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
  if [[ -f "$TEST_SUB4/.gitignore" ]] && grep -q ".moira/state/" "$TEST_SUB4/.gitignore"; then
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
     grep -q ".moira/state/" "$TEST_SUB5/.gitignore"; then
    pass "gitignore: appends to existing, preserves content"
  else
    fail "gitignore: failed to append or lost existing content"
  fi

  # ── Gitignore: idempotent (no duplicates) ──
  moira_bootstrap_setup_gitignore "$TEST_SUB5"
  dup_count=$(grep -c ".moira/state/" "$TEST_SUB5/.gitignore" || true)
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

  # ═══════════════════════════════════════════════════════════════════════
  # Frontmatter alias tests
  # ═══════════════════════════════════════════════════════════════════════

  FM_ALIAS_TEST="$TEST_DIR/fm-alias-test.md"
  cat > "$FM_ALIAS_TEST" << 'EOF'
---
primary_language: TypeScript
css_framework: Tailwind CSS
framework: SvelteKit
---
EOF

  # Alias: primary_language → language fallback
  result=$(_moira_parse_frontmatter_alias "$FM_ALIAS_TEST" "language" "primary_language" "lang")
  if [[ "$result" == "TypeScript" ]]; then
    pass "frontmatter alias: falls back to primary_language"
  else
    fail "frontmatter alias: expected 'TypeScript', got '$result'"
  fi

  # Alias: css_framework → styling fallback
  result=$(_moira_parse_frontmatter_alias "$FM_ALIAS_TEST" "styling" "css_framework" "css")
  if [[ "$result" == "Tailwind CSS" ]]; then
    pass "frontmatter alias: falls back to css_framework"
  else
    fail "frontmatter alias: expected 'Tailwind CSS', got '$result'"
  fi

  # Alias: direct match takes priority
  result=$(_moira_parse_frontmatter_alias "$FM_ALIAS_TEST" "framework" "primary_framework")
  if [[ "$result" == "SvelteKit" ]]; then
    pass "frontmatter alias: direct match takes priority"
  else
    fail "frontmatter alias: expected 'SvelteKit', got '$result'"
  fi

  # Alias: all miss → empty
  result=$(_moira_parse_frontmatter_alias "$FM_ALIAS_TEST" "nonexistent" "also_missing")
  if [[ -z "$result" ]]; then
    pass "frontmatter alias: all miss returns empty"
  else
    fail "frontmatter alias: expected empty, got '$result'"
  fi

  # ═══════════════════════════════════════════════════════════════════════
  # gen_* exit code tests (Bug #1: exit code 1 from compound blocks)
  # ═══════════════════════════════════════════════════════════════════════

  GEN_TEST_DIR="$TEST_DIR/gen-test"
  mkdir -p "$GEN_TEST_DIR/rules"

  # Create minimal tech-scan with only framework (all other fields empty)
  cat > "$GEN_TEST_DIR/tech-scan.md" << 'EOF'
---
framework: SvelteKit
---
## Body
EOF

  # gen_stack: must succeed even when most fields are empty
  set +e
  _moira_bootstrap_gen_stack "$GEN_TEST_DIR/tech-scan.md" "$GEN_TEST_DIR/rules/stack.yaml"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    pass "gen_stack: exit code 0 with sparse frontmatter"
  else
    fail "gen_stack: exit code $exit_code with sparse frontmatter"
  fi

  if [[ -f "$GEN_TEST_DIR/rules/stack.yaml" ]] && grep -q "framework: SvelteKit" "$GEN_TEST_DIR/rules/stack.yaml"; then
    pass "gen_stack: output contains framework"
  else
    fail "gen_stack: output missing or incomplete"
  fi

  # Create minimal convention-scan and structure-scan
  cat > "$GEN_TEST_DIR/convention-scan.md" << 'EOF'
---
naming_files: kebab-case
indent: 2 spaces
---
## Body
EOF

  cat > "$GEN_TEST_DIR/structure-scan.md" << 'EOF'
---
layout_pattern: single-app
dir_components: src/lib/components/
dir_pages: src/routes/
do_not_modify:
  - node_modules/
  - .svelte-kit/
modify_with_caution:
  - svelte.config.js
---
## Body
EOF

  # gen_conventions: must succeed
  set +e
  _moira_bootstrap_gen_conventions "$GEN_TEST_DIR/convention-scan.md" "$GEN_TEST_DIR/structure-scan.md" "$GEN_TEST_DIR/rules/conventions.yaml"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    pass "gen_conventions: exit code 0"
  else
    fail "gen_conventions: exit code $exit_code"
  fi

  if [[ -f "$GEN_TEST_DIR/rules/conventions.yaml" ]] && grep -q "naming:" "$GEN_TEST_DIR/rules/conventions.yaml"; then
    pass "gen_conventions: output has naming section"
  else
    fail "gen_conventions: output missing naming section"
  fi

  if grep -q "components: src/lib/components/" "$GEN_TEST_DIR/rules/conventions.yaml"; then
    pass "gen_conventions: output has dir_* structure"
  else
    fail "gen_conventions: missing dir_* structure in output"
  fi

  # Create minimal pattern-scan
  cat > "$GEN_TEST_DIR/pattern-scan.md" << 'EOF'
---
data_fetching: SvelteKit load functions
error_handling: SvelteKit fail()
---
## Body
EOF

  # gen_patterns: must succeed with sparse data
  set +e
  _moira_bootstrap_gen_patterns "$GEN_TEST_DIR/pattern-scan.md" "$GEN_TEST_DIR/rules/patterns.yaml"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    pass "gen_patterns: exit code 0"
  else
    fail "gen_patterns: exit code $exit_code"
  fi

  # gen_boundaries: must succeed
  set +e
  _moira_bootstrap_gen_boundaries "$GEN_TEST_DIR/structure-scan.md" "$GEN_TEST_DIR/rules/boundaries.yaml"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    pass "gen_boundaries: exit code 0"
  else
    fail "gen_boundaries: exit code $exit_code"
  fi

  if grep -q "node_modules/" "$GEN_TEST_DIR/rules/boundaries.yaml"; then
    pass "gen_boundaries: output has do_not_modify entries"
  else
    fail "gen_boundaries: missing do_not_modify entries"
  fi

  # Full pipeline: generate_project_rules must succeed end-to-end
  PIPELINE_DIR="$TEST_DIR/pipeline-test"
  mkdir -p "$PIPELINE_DIR/.moira/project/rules" "$PIPELINE_DIR/.moira/state/init"
  cp "$GEN_TEST_DIR/tech-scan.md" "$PIPELINE_DIR/.moira/state/init/"
  cp "$GEN_TEST_DIR/convention-scan.md" "$PIPELINE_DIR/.moira/state/init/"
  cp "$GEN_TEST_DIR/structure-scan.md" "$PIPELINE_DIR/.moira/state/init/"
  cp "$GEN_TEST_DIR/pattern-scan.md" "$PIPELINE_DIR/.moira/state/init/"

  set +e
  moira_bootstrap_generate_project_rules "$PIPELINE_DIR" "$PIPELINE_DIR/.moira/state/init"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    pass "generate_project_rules: full pipeline exit code 0"
  else
    fail "generate_project_rules: full pipeline exit code $exit_code"
  fi

  for rule_file in stack.yaml conventions.yaml patterns.yaml boundaries.yaml; do
    if [[ -f "$PIPELINE_DIR/.moira/project/rules/$rule_file" ]]; then
      pass "generate_project_rules: $rule_file created"
    else
      fail "generate_project_rules: $rule_file not created"
    fi
  done

  # ═══════════════════════════════════════════════════════════════════════
  # L1 summary condensation tests (Bug #4: grep patterns miss bold markdown)
  # ═══════════════════════════════════════════════════════════════════════

  SUMMARY_DIR="$TEST_DIR/summary-test"
  mkdir -p "$SUMMARY_DIR/conventions" "$SUMMARY_DIR/patterns"

  # Simulate real scanner output with bold markdown (what scanners actually produce)
  cat > "$SUMMARY_DIR/scan-conventions.md" << 'EOF'
## Naming Conventions
| What | Convention | Evidence |
|------|-----------|----------|
| Files | kebab-case | src/components/user-profile.tsx |
| Functions | camelCase | getUserById in src/services/user.ts:12 |

- **File naming:** kebab-case throughout the project
- **Function naming:** camelCase for all exported functions
- **Component naming:** PascalCase for React components

## Import Style
- **Named imports** are preferred: `import { foo } from 'bar'`

## Export Style
- Default exports for components, named exports for utilities
EOF

  _condense_to_summary "$SUMMARY_DIR/scan-conventions.md" \
    "$SUMMARY_DIR/conventions/summary.md" "2026-01-01" \
    "File|Function|Component|Import|Export|Naming|Convention|indent|quote|semicolon"

  # Count non-metadata lines
  content_lines=$(grep -v '^<!-- moira:' "$SUMMARY_DIR/conventions/summary.md" | grep -v '^$' | wc -l | tr -d ' ')
  if [[ "$content_lines" -ge 5 ]]; then
    pass "condense_to_summary: extracts $content_lines lines from bold markdown"
  else
    fail "condense_to_summary: only $content_lines lines extracted (expected >= 5)"
  fi

  # Verify bold bullet lines ARE captured
  if grep -q "File naming" "$SUMMARY_DIR/conventions/summary.md"; then
    pass "condense_to_summary: captures **bold** bullet lines"
  else
    fail "condense_to_summary: misses **bold** bullet lines"
  fi

  # Verify section headers ARE captured
  if grep -q "## Naming Conventions" "$SUMMARY_DIR/conventions/summary.md"; then
    pass "condense_to_summary: captures section headers"
  else
    fail "condense_to_summary: misses section headers"
  fi

  # Verify table rows ARE captured
  if grep -q "| Files |" "$SUMMARY_DIR/conventions/summary.md"; then
    pass "condense_to_summary: captures table rows"
  else
    fail "condense_to_summary: misses table rows"
  fi

  # ═══════════════════════════════════════════════════════════════════════
  # Scanner ↔ parser field contract tests (Bug #3: field name mismatch)
  # ═══════════════════════════════════════════════════════════════════════

  # Verify that fields the parser expects exist in scanner template contracts
  SCANNER_DIR="$MOIRA_HOME/templates/scanners"
  BOOTSTRAP_SH="$MOIRA_HOME/lib/bootstrap.sh"

  # tech-scan: parser expects language, framework, runtime, styling, orm, testing, ci
  for field in language framework runtime styling orm testing ci; do
    if grep -q "^${field}:" "$SCANNER_DIR/tech-scan.md" 2>/dev/null; then
      pass "contract: tech-scan defines '$field'"
    else
      fail "contract: tech-scan missing '$field' — parser will get empty value"
    fi
  done

  # convention-scan: parser expects naming_files, naming_functions, naming_components, naming_constants, naming_types, indent, quotes, semicolons, max_line_length
  for field in naming_files naming_functions naming_components naming_constants naming_types indent quotes semicolons max_line_length; do
    if grep -q "^${field}:" "$SCANNER_DIR/convention-scan.md" 2>/dev/null; then
      pass "contract: convention-scan defines '$field'"
    else
      fail "contract: convention-scan missing '$field'"
    fi
  done

  # pattern-scan: parser expects data_fetching, error_handling, api_style, api_validation, component_structure, component_state, component_styling, client_state, server_state
  for field in data_fetching error_handling api_style api_validation component_structure component_state component_styling client_state server_state; do
    if grep -q "^${field}:" "$SCANNER_DIR/pattern-scan.md" 2>/dev/null; then
      pass "contract: pattern-scan defines '$field'"
    else
      fail "contract: pattern-scan missing '$field'"
    fi
  done

  # structure-scan: parser expects do_not_modify, modify_with_caution, dir_*
  for field in do_not_modify modify_with_caution; do
    if grep -q "^${field}:" "$SCANNER_DIR/structure-scan.md" 2>/dev/null; then
      pass "contract: structure-scan defines '$field'"
    else
      fail "contract: structure-scan missing '$field'"
    fi
  done

  if grep -q "^dir_" "$SCANNER_DIR/structure-scan.md" 2>/dev/null; then
    pass "contract: structure-scan defines dir_* fields"
  else
    fail "contract: structure-scan missing dir_* fields"
  fi

  # ═══════════════════════════════════════════════════════════════════════
  # Host rules audit tests (D-204)
  # ═══════════════════════════════════════════════════════════════════════

  # Test 1: No .claude/rules/ directory — empty report
  HRA_DIR1="$TEST_DIR/hra-norules"
  mkdir -p "$HRA_DIR1/.moira/state/init"
  moira_bootstrap_audit_host_rules "$HRA_DIR1"
  if [[ -f "$HRA_DIR1/.moira/state/init/rules-audit.md" ]]; then
    if grep -q "total_files: 0" "$HRA_DIR1/.moira/state/init/rules-audit.md"; then
      pass "host rules audit: no rules dir → total_files: 0"
    else
      fail "host rules audit: no rules dir but total_files not 0"
    fi
  else
    fail "host rules audit: no output file created"
  fi

  # Test 2: Empty .claude/rules/ directory
  HRA_DIR2="$TEST_DIR/hra-empty"
  mkdir -p "$HRA_DIR2/.claude/rules" "$HRA_DIR2/.moira/state/init"
  moira_bootstrap_audit_host_rules "$HRA_DIR2"
  if grep -q "total_files: 0" "$HRA_DIR2/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: empty rules dir → total_files: 0"
  else
    fail "host rules audit: empty rules dir but total_files not 0"
  fi

  # Test 3: Unconditional rule (no paths frontmatter)
  HRA_DIR3="$TEST_DIR/hra-uncond"
  mkdir -p "$HRA_DIR3/.claude/rules" "$HRA_DIR3/.moira/state/init"
  cat > "$HRA_DIR3/.claude/rules/coding-style.md" << 'EOF'
# Coding Style

- Use camelCase for functions
- Use 2-space indent
- Always use semicolons
EOF
  moira_bootstrap_audit_host_rules "$HRA_DIR3"
  if grep -q "unconditional_count: 1" "$HRA_DIR3/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: unconditional rule detected"
  else
    fail "host rules audit: unconditional rule not detected"
  fi
  if grep -q "code-style" "$HRA_DIR3/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: code-style category classified"
  else
    fail "host rules audit: code-style category not classified"
  fi

  # Test 4: Path-scoped rule (has paths frontmatter)
  HRA_DIR4="$TEST_DIR/hra-scoped"
  mkdir -p "$HRA_DIR4/.claude/rules" "$HRA_DIR4/.moira/state/init"
  cat > "$HRA_DIR4/.claude/rules/api-rules.md" << 'EOF'
---
paths:
  - "src/api/**/*.ts"
---

# API Rules

- Always validate input
- Use proper error handling
EOF
  moira_bootstrap_audit_host_rules "$HRA_DIR4"
  if grep -q "scoped_count: 1" "$HRA_DIR4/.moira/state/init/rules-audit.md" && \
     grep -q "unconditional_count: 0" "$HRA_DIR4/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: path-scoped rule correctly classified"
  else
    fail "host rules audit: path-scoped rule not correctly classified"
  fi

  # Test 5: Mixed rules — unconditional + scoped
  HRA_DIR5="$TEST_DIR/hra-mixed"
  mkdir -p "$HRA_DIR5/.claude/rules" "$HRA_DIR5/.moira/state/init"
  cat > "$HRA_DIR5/.claude/rules/global.md" << 'EOF'
# Security Rules

- Never commit credentials
- Always sanitize user input
EOF
  cat > "$HRA_DIR5/.claude/rules/frontend.md" << 'EOF'
---
paths:
  - "src/components/**"
---

# Frontend Rules

- Use PascalCase for components
EOF
  moira_bootstrap_audit_host_rules "$HRA_DIR5"
  if grep -q "total_files: 2" "$HRA_DIR5/.moira/state/init/rules-audit.md" && \
     grep -q "unconditional_count: 1" "$HRA_DIR5/.moira/state/init/rules-audit.md" && \
     grep -q "scoped_count: 1" "$HRA_DIR5/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: mixed rules counted correctly"
  else
    fail "host rules audit: mixed rules count wrong"
  fi
  if grep -q "security" "$HRA_DIR5/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: security category classified"
  else
    fail "host rules audit: security category not classified"
  fi

  # Test 6: Token estimation (non-zero)
  if grep -q "total_tokens: 0" "$HRA_DIR5/.moira/state/init/rules-audit.md"; then
    fail "host rules audit: total_tokens should not be 0 for non-empty rules"
  else
    pass "host rules audit: total_tokens is non-zero"
  fi

  # Test 7: Overlap detection with convention scan
  HRA_DIR7="$TEST_DIR/hra-overlap"
  mkdir -p "$HRA_DIR7/.claude/rules" "$HRA_DIR7/.moira/state/init"
  cat > "$HRA_DIR7/.claude/rules/style.md" << 'EOF'
# Style Guide

- Use camelCase for variables
- Use snake_case for database fields
- 2-space indent
- No semicolons
EOF
  cat > "$HRA_DIR7/.moira/state/init/convention-scan.md" << 'EOF'
---
naming_files: kebab-case
naming_functions: camelCase
indent: 2 spaces
semicolons: false
---
## Conventions
- camelCase for functions
- snake_case for DB columns
- 2-space indent
EOF
  moira_bootstrap_audit_host_rules "$HRA_DIR7"
  if grep -q "overlap_with_conventions.* true" "$HRA_DIR7/.moira/state/init/rules-audit.md"; then
    pass "host rules audit: overlap with conventions detected"
  else
    fail "host rules audit: overlap with conventions not detected"
  fi

  # Test 8: Function exists in bootstrap.sh
  if grep -q "moira_bootstrap_audit_host_rules" "$BOOTSTRAP_SH" 2>/dev/null; then
    pass "bootstrap.sh: function moira_bootstrap_audit_host_rules declared"
  else
    fail "bootstrap.sh: function moira_bootstrap_audit_host_rules not found"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Init command: Step 4c present (D-204)
# ═══════════════════════════════════════════════════════════════════════

if [[ -f "$init_file" ]]; then
  assert_file_contains "$init_file" "Step 4c" "init.md: Step 4c (Host Rules Triage) present"
  assert_file_contains "$init_file" "D-204" "init.md: references D-204"
  assert_file_contains "$init_file" "moira_bootstrap_audit_host_rules" "init.md: calls audit function"
fi

test_summary
