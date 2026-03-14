#!/usr/bin/env bash
# test-hooks-system.sh — Verify Phase 8 hooks system artifacts
# Tests guard hook, budget tracking hook, settings merge, integration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ═══════════════════════════════════════════════════════════════════════
# Guard hook tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/hooks/guard.sh" "guard.sh exists"

if [[ -f "$MOIRA_HOME/hooks/guard.sh" ]]; then
  if bash -n "$MOIRA_HOME/hooks/guard.sh" 2>/dev/null; then
    pass "guard.sh syntax valid"
  else
    fail "guard.sh has syntax errors"
  fi

  assert_file_contains "$MOIRA_HOME/hooks/guard.sh" "hookSpecificOutput" "guard.sh: contains hookSpecificOutput"
  assert_file_contains "$MOIRA_HOME/hooks/guard.sh" "CONSTITUTIONAL VIOLATION" "guard.sh: contains CONSTITUTIONAL VIOLATION"
  assert_file_contains "$MOIRA_HOME/hooks/guard.sh" "violations.log" "guard.sh: references violations.log"
  assert_file_contains "$MOIRA_HOME/hooks/guard.sh" "tool-usage.log" "guard.sh: references tool-usage.log"
  assert_file_contains "$MOIRA_HOME/hooks/guard.sh" "current.yaml" "guard.sh: checks current.yaml for session"
fi

# ═══════════════════════════════════════════════════════════════════════
# Budget tracking hook tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/hooks/budget-track.sh" "budget-track.sh exists"

if [[ -f "$MOIRA_HOME/hooks/budget-track.sh" ]]; then
  if bash -n "$MOIRA_HOME/hooks/budget-track.sh" 2>/dev/null; then
    pass "budget-track.sh syntax valid"
  else
    fail "budget-track.sh has syntax errors"
  fi

  assert_file_contains "$MOIRA_HOME/hooks/budget-track.sh" "budget-tool-usage.log" "budget-track.sh: references budget-tool-usage.log"
  assert_file_contains "$MOIRA_HOME/hooks/budget-track.sh" "current.yaml" "budget-track.sh: checks current.yaml for session"
fi

# ═══════════════════════════════════════════════════════════════════════
# Settings merge tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/lib/settings-merge.sh" "settings-merge.sh exists"

if [[ -f "$MOIRA_HOME/lib/settings-merge.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/settings-merge.sh" 2>/dev/null; then
    pass "settings-merge.sh syntax valid"
  else
    fail "settings-merge.sh has syntax errors"
  fi

  # Source and check functions exist
  source "$MOIRA_HOME/lib/settings-merge.sh"
  if declare -f moira_settings_merge_hooks &>/dev/null; then
    pass "settings-merge.sh: moira_settings_merge_hooks function exists"
  else
    fail "settings-merge.sh: moira_settings_merge_hooks function not found"
  fi

  if declare -f moira_settings_remove_hooks &>/dev/null; then
    pass "settings-merge.sh: moira_settings_remove_hooks function exists"
  else
    fail "settings-merge.sh: moira_settings_remove_hooks function not found"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Integration tests
# ═══════════════════════════════════════════════════════════════════════

# orchestrator.md references guard/violations
if [[ -f "$MOIRA_HOME/skills/orchestrator.md" ]]; then
  if grep -qE "guard|violations.log" "$MOIRA_HOME/skills/orchestrator.md" 2>/dev/null; then
    pass "orchestrator.md: references guard hook or violations.log"
  else
    fail "orchestrator.md: no reference to guard hook or violations"
  fi
fi

# errors.md E7-DRIFT is not a stub
if [[ -f "$MOIRA_HOME/skills/errors.md" ]]; then
  if grep -q "stub" "$MOIRA_HOME/skills/errors.md" 2>/dev/null; then
    fail "errors.md: E7-DRIFT still contains 'stub'"
  else
    pass "errors.md: E7-DRIFT is not a stub"
  fi
fi

# project-claude-md.tmpl has enforcement rules
if [[ -f "$MOIRA_HOME/templates/project-claude-md.tmpl" ]]; then
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "ORCHESTRATOR" "template: contains ORCHESTRATOR"
  assert_file_contains "$MOIRA_HOME/templates/project-claude-md.tmpl" "NEVER" "template: contains NEVER"
  if grep -qi "rationalization" "$MOIRA_HOME/templates/project-claude-md.tmpl" 2>/dev/null; then
    pass "template: contains anti-rationalization rules"
  else
    fail "template: missing anti-rationalization rules"
  fi
fi

# config.schema.yaml has hook config fields
if [[ -f "$MOIRA_HOME/schemas/config.schema.yaml" ]]; then
  assert_file_contains "$MOIRA_HOME/schemas/config.schema.yaml" "guard_enabled" "config schema: has guard_enabled"
  assert_file_contains "$MOIRA_HOME/schemas/config.schema.yaml" "budget_tracking_enabled" "config schema: has budget_tracking_enabled"
fi

# ═══════════════════════════════════════════════════════════════════════
# Hook functional tests (basic)
# ═══════════════════════════════════════════════════════════════════════

# guard.sh exits 0 when no state directory exists (non-Moira session)
if [[ -f "$MOIRA_HOME/hooks/guard.sh" ]]; then
  if echo "" | bash "$MOIRA_HOME/hooks/guard.sh" 2>/dev/null; then
    pass "guard.sh: exits 0 with empty input (non-Moira session)"
  else
    fail "guard.sh: non-zero exit with empty input"
  fi
fi

# budget-track.sh exits 0 when no state directory exists
if [[ -f "$MOIRA_HOME/hooks/budget-track.sh" ]]; then
  if echo "" | bash "$MOIRA_HOME/hooks/budget-track.sh" 2>/dev/null; then
    pass "budget-track.sh: exits 0 with empty input (non-Moira session)"
  else
    fail "budget-track.sh: non-zero exit with empty input"
  fi
fi

test_summary
