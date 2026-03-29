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
# Pipeline compliance hooks (D-175, D-176)
# ═══════════════════════════════════════════════════════════════════════

COMPLIANCE_HOOKS=(
  "pipeline-dispatch.sh"
  "pipeline-tracker.sh"
  "pipeline-stop-guard.sh"
  "guard-prevent.sh"
  "compact-reinject.sh"
  "agent-inject.sh"
  "agent-output-validate.sh"
  "agent-done.sh"
  "session-cleanup.sh"
  "task-submit.sh"
)

for hook in "${COMPLIANCE_HOOKS[@]}"; do
  assert_file_exists "$MOIRA_HOME/hooks/$hook" "$hook exists"
  if [[ -f "$MOIRA_HOME/hooks/$hook" ]]; then
    if bash -n "$MOIRA_HOME/hooks/$hook" 2>/dev/null; then
      pass "$hook syntax valid"
    else
      fail "$hook has syntax errors"
    fi
  fi
done

# Structural checks for key hooks
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "permissionDecision" "pipeline-dispatch.sh: can DENY dispatches"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "review_pending" "pipeline-dispatch.sh: enforces review"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "quick:classifier" "pipeline-dispatch.sh: has quick transition table"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "standard:classifier" "pipeline-dispatch.sh: has standard transition table"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "full:classifier" "pipeline-dispatch.sh: has full transition table"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "decomposition:classifier" "pipeline-dispatch.sh: has decomposition transition table"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "analytical:classifier" "pipeline-dispatch.sh: has analytical transition table"

assert_file_contains "$MOIRA_HOME/hooks/pipeline-tracker.sh" "pipeline-tracker.state" "pipeline-tracker.sh: writes tracker state"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-tracker.sh" "additionalContext" "pipeline-tracker.sh: injects guidance"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-tracker.sh" "subtask_mode" "pipeline-tracker.sh: tracks sub-task mode"

assert_file_contains "$MOIRA_HOME/hooks/guard-prevent.sh" "permissionDecision" "guard-prevent.sh: can DENY file access"
assert_file_contains "$MOIRA_HOME/hooks/guard-prevent.sh" "BOUNDARY VIOLATION" "guard-prevent.sh: reports boundary violations"

assert_file_contains "$MOIRA_HOME/hooks/agent-inject.sh" "RESPONSE CONTRACT" "agent-inject.sh: injects response contract"
assert_file_contains "$MOIRA_HOME/hooks/agent-inject.sh" "INVIOLABLE RULES" "agent-inject.sh: injects rules"

assert_file_contains "$MOIRA_HOME/hooks/agent-output-validate.sh" "STATUS:" "agent-output-validate.sh: validates STATUS line"

assert_file_contains "$MOIRA_HOME/hooks/compact-reinject.sh" "CONTEXT RECOVERY" "compact-reinject.sh: injects context recovery"

# State automation hooks (D-178)
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "moira_state_transition" "pipeline-dispatch.sh: writes step transition"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "dispatched_role" "pipeline-dispatch.sh: writes dispatched_role"
assert_file_contains "$MOIRA_HOME/hooks/agent-done.sh" "moira_state_agent_done" "agent-done.sh: records agent completion"
assert_file_contains "$MOIRA_HOME/hooks/agent-done.sh" "dispatched_role" "agent-done.sh: reads dispatched_role"
assert_file_contains "$MOIRA_HOME/hooks/session-cleanup.sh" "guard-active" "session-cleanup.sh: cleans guard marker"
assert_file_contains "$MOIRA_HOME/hooks/session-cleanup.sh" "session-lock" "session-cleanup.sh: cleans session lock"
assert_file_contains "$MOIRA_HOME/hooks/task-submit.sh" "moira_task_init" "task-submit.sh: scaffolds task"
assert_file_contains "$MOIRA_HOME/hooks/task-submit.sh" "MOIRA TASK INITIALIZED" "task-submit.sh: injects task_id"

# ═══════════════════════════════════════════════════════════════════════
# Hook functional tests (basic)
# ═══════════════════════════════════════════════════════════════════════

# All hooks exit 0 with empty input (non-Moira session)
ALL_HOOKS=(
  "guard.sh"
  "budget-track.sh"
  "pipeline-dispatch.sh"
  "pipeline-tracker.sh"
  "pipeline-stop-guard.sh"
  "guard-prevent.sh"
  "compact-reinject.sh"
  "agent-inject.sh"
  "agent-output-validate.sh"
  "agent-done.sh"
  "session-cleanup.sh"
  "task-submit.sh"
)

for hook in "${ALL_HOOKS[@]}"; do
  if [[ -f "$MOIRA_HOME/hooks/$hook" ]]; then
    if echo "" | bash "$MOIRA_HOME/hooks/$hook" 2>/dev/null; then
      pass "$hook: exits 0 with empty input (non-Moira session)"
    else
      fail "$hook: non-zero exit with empty input"
    fi
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# Settings merge — all hook types registered
# ═══════════════════════════════════════════════════════════════════════

if [[ -f "$SRC_DIR/global/lib/settings-merge.sh" ]]; then
  assert_file_contains "$SRC_DIR/global/lib/settings-merge.sh" "PreToolUse" "settings-merge.sh: registers PreToolUse hooks"
  assert_file_contains "$SRC_DIR/global/lib/settings-merge.sh" "PostToolUse" "settings-merge.sh: registers PostToolUse hooks"
  assert_file_contains "$SRC_DIR/global/lib/settings-merge.sh" "Stop" "settings-merge.sh: registers Stop hooks"
  assert_file_contains "$SRC_DIR/global/lib/settings-merge.sh" "SessionStart" "settings-merge.sh: registers SessionStart hooks"
  assert_file_contains "$SRC_DIR/global/lib/settings-merge.sh" "SubagentStart" "settings-merge.sh: registers SubagentStart hooks"
  assert_file_contains "$SRC_DIR/global/lib/settings-merge.sh" "SubagentStop" "settings-merge.sh: registers SubagentStop hooks"
fi

test_summary
