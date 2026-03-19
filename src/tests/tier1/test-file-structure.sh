#!/usr/bin/env bash
# test-file-structure.sh — Verify installed Moira file structure
# Tests global layer directories, command stubs, version file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
COMMANDS_DIR="$HOME/.claude/commands/moira"

# Derive SRC_DIR: if MOIRA_HOME points to src/global, SRC_DIR is src/
# This handles both source-tree and installed layouts
if [[ -d "$MOIRA_HOME/lib" && ! -d "$MOIRA_HOME/schemas" && -d "$(dirname "$MOIRA_HOME")/schemas" ]]; then
  SRC_DIR="$(dirname "$MOIRA_HOME")"
else
  SRC_DIR="$MOIRA_HOME"
fi

# ── Version file ─────────────────────────────────────────────────────
assert_file_exists "$SRC_DIR/.version" ".version exists"

if [[ -f "$SRC_DIR/.version" ]]; then
  ver=$(cat "$SRC_DIR/.version")
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass ".version contains valid semver ($ver)"
  else
    fail ".version contains invalid semver: $ver"
  fi
fi

# ── Lib files ────────────────────────────────────────────────────────
for lib in state.sh yaml-utils.sh scaffold.sh task-id.sh; do
  assert_file_exists "$MOIRA_HOME/lib/$lib" "lib/$lib exists"
  if [[ -f "$MOIRA_HOME/lib/$lib" ]]; then
    if bash -n "$MOIRA_HOME/lib/$lib" 2>/dev/null; then
      pass "lib/$lib syntax valid"
    else
      fail "lib/$lib has syntax errors"
    fi
  fi
done

# ── Global directories ──────────────────────────────────────────────
assert_dir_exists "$MOIRA_HOME/core/rules/roles" "core/rules/roles/ exists"
assert_dir_exists "$MOIRA_HOME/core/rules/quality" "core/rules/quality/ exists"
assert_dir_exists "$MOIRA_HOME/skills" "skills/ exists"
assert_dir_exists "$MOIRA_HOME/hooks" "hooks/ exists"
assert_dir_exists "$MOIRA_HOME/lib" "lib/ exists"
assert_dir_exists "$SRC_DIR/schemas" "schemas/ exists"
assert_dir_exists "$MOIRA_HOME/core/pipelines" "core/pipelines/ exists"

# ── Phase 4: knowledge + rules libs ────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/knowledge.sh" "lib/knowledge.sh exists"
if [[ -f "$MOIRA_HOME/lib/knowledge.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/knowledge.sh" 2>/dev/null; then
    pass "lib/knowledge.sh syntax valid"
  else
    fail "lib/knowledge.sh has syntax errors"
  fi
fi
assert_file_exists "$MOIRA_HOME/lib/rules.sh" "lib/rules.sh exists"
if [[ -f "$MOIRA_HOME/lib/rules.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/rules.sh" 2>/dev/null; then
    pass "lib/rules.sh syntax valid"
  else
    fail "lib/rules.sh has syntax errors"
  fi
fi

# ── Phase 4: knowledge templates ───────────────────────────────────
assert_dir_exists "$MOIRA_HOME/templates/knowledge" "templates/knowledge/ exists"
for ktype in project-model conventions decisions patterns failures quality-map libraries; do
  assert_dir_exists "$MOIRA_HOME/templates/knowledge/$ktype" "templates/knowledge/$ktype/ exists"
done

# Quality-map must NOT have index.md (L0 not applicable per AD-6)
if [[ ! -f "$MOIRA_HOME/templates/knowledge/quality-map/index.md" ]]; then
  pass "quality-map has no index.md (AD-6)"
else
  fail "quality-map should NOT have index.md"
fi

# ── Phase 5: bootstrap artifacts ──────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/bootstrap.sh" "lib/bootstrap.sh exists"
if [[ -f "$MOIRA_HOME/lib/bootstrap.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
    pass "lib/bootstrap.sh syntax valid"
  else
    fail "lib/bootstrap.sh has syntax errors"
  fi
fi

assert_file_exists "$MOIRA_HOME/lib/mcp.sh" "lib/mcp.sh exists"
if [[ -f "$MOIRA_HOME/lib/mcp.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/mcp.sh" 2>/dev/null; then
    pass "lib/mcp.sh syntax valid"
  else
    fail "lib/mcp.sh has syntax errors"
  fi
fi

# ── Phase 10: reflection + judge libs ─────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/reflection.sh" "lib/reflection.sh exists"
if [[ -f "$MOIRA_HOME/lib/reflection.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/reflection.sh" 2>/dev/null; then
    pass "lib/reflection.sh syntax valid"
  else
    fail "lib/reflection.sh has syntax errors"
  fi
fi

assert_file_exists "$MOIRA_HOME/lib/judge.sh" "lib/judge.sh exists"
if [[ -f "$MOIRA_HOME/lib/judge.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/judge.sh" 2>/dev/null; then
    pass "lib/judge.sh syntax valid"
  else
    fail "lib/judge.sh has syntax errors"
  fi
fi

assert_dir_exists "$MOIRA_HOME/templates/scanners" "templates/scanners/ exists"
scanner_count=$(ls "$MOIRA_HOME/templates/scanners/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$scanner_count" -ge 5 ]]; then
  pass "scanner templates: $scanner_count files (>=5)"
else
  fail "scanner templates: expected >=5, found $scanner_count"
fi

assert_file_exists "$MOIRA_HOME/templates/project-claude-md.tmpl" "project-claude-md.tmpl exists"

# ── Phase 6: quality system artifacts ─────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/quality.sh" "lib/quality.sh exists"
if [[ -f "$MOIRA_HOME/lib/quality.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/quality.sh" 2>/dev/null; then
    pass "lib/quality.sh syntax valid"
  else
    fail "lib/quality.sh has syntax errors"
  fi
fi

assert_file_exists "$MOIRA_HOME/lib/bench.sh" "lib/bench.sh exists"
if [[ -f "$MOIRA_HOME/lib/bench.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/bench.sh" 2>/dev/null; then
    pass "lib/bench.sh syntax valid"
  else
    fail "lib/bench.sh has syntax errors"
  fi
fi

assert_file_exists "$SRC_DIR/schemas/findings.schema.yaml" "schemas/findings.schema.yaml exists"

assert_dir_exists "$MOIRA_HOME/templates/scanners/deep" "templates/scanners/deep/ exists"
deep_count=$(ls "$MOIRA_HOME/templates/scanners/deep/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$deep_count" -ge 4 ]]; then
  pass "deep scan templates: $deep_count files (>=4)"
else
  fail "deep scan templates: expected >=4, found $deep_count"
fi

assert_dir_exists "$SRC_DIR/tests/bench/fixtures" "tests/bench/fixtures/ exists"
assert_dir_exists "$SRC_DIR/tests/bench/cases" "tests/bench/cases/ exists"
assert_dir_exists "$SRC_DIR/tests/bench/rubrics" "tests/bench/rubrics/ exists"

# ── Phase 10: reflection + judge templates ────────────────────────
assert_dir_exists "$MOIRA_HOME/templates/reflection" "templates/reflection/ exists"
assert_dir_exists "$MOIRA_HOME/templates/judge" "templates/judge/ exists"

# ── Phase 8: hooks system artifacts ──────────────────────────────────
assert_file_exists "$MOIRA_HOME/hooks/guard.sh" "hooks/guard.sh exists"
assert_file_exists "$MOIRA_HOME/hooks/budget-track.sh" "hooks/budget-track.sh exists"
assert_file_exists "$MOIRA_HOME/lib/settings-merge.sh" "lib/settings-merge.sh exists"

# ── Phase 7: budget system artifacts ─────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/budget.sh" "lib/budget.sh exists"
if [[ -f "$MOIRA_HOME/lib/budget.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/budget.sh" 2>/dev/null; then
    pass "lib/budget.sh syntax valid"
  else
    fail "lib/budget.sh has syntax errors"
  fi
fi
assert_file_exists "$MOIRA_HOME/templates/budgets.yaml.tmpl" "templates/budgets.yaml.tmpl exists"

# ── Pipeline definitions ────────────────────────────────────────────
for pipeline in quick standard full decomposition; do
  assert_file_exists "$MOIRA_HOME/core/pipelines/${pipeline}.yaml" "pipeline ${pipeline}.yaml exists"
done

# ── Skill files ─────────────────────────────────────────────────────
for skill in orchestrator gates dispatch errors reflection; do
  assert_file_exists "$MOIRA_HOME/skills/${skill}.md" "skill ${skill}.md exists"
done

# ── Phase 11: metrics + audit system artifacts ───────────────────────
assert_file_exists "$MOIRA_HOME/lib/metrics.sh" "lib/metrics.sh exists"
if [[ -f "$MOIRA_HOME/lib/metrics.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/metrics.sh" 2>/dev/null; then
    pass "lib/metrics.sh syntax valid"
  else
    fail "lib/metrics.sh has syntax errors"
  fi
fi

assert_file_exists "$MOIRA_HOME/lib/audit.sh" "lib/audit.sh exists"
if [[ -f "$MOIRA_HOME/lib/audit.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/audit.sh" 2>/dev/null; then
    pass "lib/audit.sh syntax valid"
  else
    fail "lib/audit.sh has syntax errors"
  fi
fi

# ── Retry optimizer lib ──────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/retry.sh" "lib/retry.sh exists"
if [[ -f "$MOIRA_HOME/lib/retry.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/retry.sh" 2>/dev/null; then
    pass "lib/retry.sh syntax valid"
  else
    fail "lib/retry.sh has syntax errors"
  fi
fi

assert_dir_exists "$MOIRA_HOME/templates/audit" "templates/audit/ exists"
audit_template_count=$(ls "$MOIRA_HOME/templates/audit/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$audit_template_count" -ge 12 ]]; then
  pass "audit templates: $audit_template_count files (>=12)"
else
  fail "audit templates: expected >=12, found $audit_template_count"
fi

assert_file_exists "$MOIRA_HOME/core/xref-manifest.yaml" "core/xref-manifest.yaml exists"
assert_file_exists "$SRC_DIR/schemas/metrics.schema.yaml" "schemas/metrics.schema.yaml exists"
assert_file_exists "$SRC_DIR/schemas/audit.schema.yaml" "schemas/audit.schema.yaml exists"

# ── Phase 12: checkpoint + epic + upgrade libs ──────────────────────
for lib in checkpoint.sh epic.sh upgrade.sh; do
  assert_file_exists "$MOIRA_HOME/lib/$lib" "lib/$lib exists"
  if [[ -f "$MOIRA_HOME/lib/$lib" ]]; then
    if bash -n "$MOIRA_HOME/lib/$lib" 2>/dev/null; then
      pass "lib/$lib syntax valid"
    else
      fail "lib/$lib has syntax errors"
    fi
  fi
done

# .version-snapshot/ is created by install.sh — only test if it exists
if [[ -d "$SRC_DIR/.version-snapshot" ]]; then
  assert_dir_exists "$SRC_DIR/.version-snapshot" ".version-snapshot/ exists"
else
  pass ".version-snapshot/ skipped (source-tree layout, created by install.sh)"
fi

# ── Command stubs ────────────────────────────────────────────────────
commands=(task init status resume knowledge metrics audit bypass refresh help bench health upgrade)
for cmd in "${commands[@]}"; do
  assert_file_exists "$COMMANDS_DIR/${cmd}.md" "command ${cmd}.md exists"
done

# ── Command frontmatter ──────────────────────────────────────────────
for cmd in "${commands[@]}"; do
  cmd_file="$COMMANDS_DIR/${cmd}.md"
  if [[ -f "$cmd_file" ]]; then
    assert_file_contains "$cmd_file" "^name: moira:" "${cmd}.md has name: moira:* in frontmatter"
    assert_file_contains "$cmd_file" "allowed-tools:" "${cmd}.md has allowed-tools in frontmatter"
  fi
done

test_summary
