#!/usr/bin/env bash
# test-passive-audit.sh — Verify passive audit check artifacts in orchestrator, gates, and hooks (D-203)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"

orchestrator="$MOIRA_HOME/skills/orchestrator.md"
if [[ ! -f "$orchestrator" ]]; then
  orchestrator="$SRC_DIR/global/skills/orchestrator.md"
fi

gates="$MOIRA_HOME/skills/gates.md"
if [[ ! -f "$gates" ]]; then
  gates="$SRC_DIR/global/skills/gates.md"
fi

agent_done="$MOIRA_HOME/hooks/agent-done.sh"
if [[ ! -f "$agent_done" ]]; then
  agent_done="$SRC_DIR/global/hooks/agent-done.sh"
fi

guard_prevent="$MOIRA_HOME/hooks/guard-prevent.sh"
if [[ ! -f "$guard_prevent" ]]; then
  guard_prevent="$SRC_DIR/global/hooks/guard-prevent.sh"
fi

pipeline_stop="$MOIRA_HOME/hooks/pipeline-stop-guard.sh"
if [[ ! -f "$pipeline_stop" ]]; then
  pipeline_stop="$SRC_DIR/global/hooks/pipeline-stop-guard.sh"
fi

pipeline_dispatch="$MOIRA_HOME/hooks/pipeline-dispatch.sh"
if [[ ! -f "$pipeline_dispatch" ]]; then
  pipeline_dispatch="$SRC_DIR/global/hooks/pipeline-dispatch.sh"
fi

pipeline_tracker="$MOIRA_HOME/hooks/pipeline-tracker.sh"
if [[ ! -f "$pipeline_tracker" ]]; then
  pipeline_tracker="$SRC_DIR/global/hooks/pipeline-tracker.sh"
fi

# ── Orchestrator passive audit: stale locks ──────────────────────────
assert_file_exists "$orchestrator" "orchestrator.md exists"

if grep -qi "stale locks\|STALE LOCKS" "$orchestrator" 2>/dev/null; then
  pass "orchestrator.md contains stale locks check"
else
  fail "orchestrator.md missing stale locks check"
fi

# ── Orchestrator passive audit: knowledge drift ─────────────────────
if grep -qi "KNOWLEDGE DRIFT\|knowledge drift\|knowledge_drift" "$orchestrator" 2>/dev/null; then
  pass "orchestrator.md contains knowledge drift check"
else
  fail "orchestrator.md missing knowledge drift check"
fi

# ── Orchestrator passive audit: convention drift ────────────────────
if grep -qi "CONVENTION DRIFT\|convention drift\|convention_drift" "$orchestrator" 2>/dev/null; then
  pass "orchestrator.md contains convention drift check"
else
  fail "orchestrator.md missing convention drift check"
fi

# ── Gates passive audit warning format ──────────────────────────────
assert_file_exists "$gates" "gates.md exists"

if grep -qi "Passive Audit Warning\|Non-blocking" "$gates" 2>/dev/null; then
  pass "gates.md contains passive audit warning format"
else
  fail "gates.md missing passive audit warning format (Passive Audit Warning / Non-blocking)"
fi

# ═══════════════════════════════════════════════════════════════════════
# D-203: Structural enforcement hooks for passive audits
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "--- D-203: Structural Enforcement Hooks ---"

# ── agent-done.sh: knowledge drift check (e1b) ────────────────────
assert_file_exists "$agent_done" "agent-done.sh exists"

if grep -q 'knowledge_drift' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: contains knowledge drift check (e1b)"
else
  fail "agent-done.sh: missing knowledge drift check (e1b)"
fi

if grep -q 'role.*explorer' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: knowledge drift scoped to explorer role"
else
  fail "agent-done.sh: knowledge drift not scoped to explorer role"
fi

# ── agent-done.sh: convention drift check (e1c) ───────────────────
if grep -q 'convention_drift' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: contains convention drift check (e1c)"
else
  fail "agent-done.sh: missing convention drift check (e1c)"
fi

if grep -q 'role.*reviewer' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: convention drift scoped to reviewer role"
else
  fail "agent-done.sh: convention drift not scoped to reviewer role"
fi

# ── agent-done.sh: agent guard check (d1) ─────────────────────────
if grep -q 'AGENT_VIOLATION\|protected.*paths\|CONSTITUTION' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: contains agent guard check (d1)"
else
  fail "agent-done.sh: missing agent guard check (d1)"
fi

if grep -q 'role.*implementer' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: guard check scoped to implementer role"
else
  fail "agent-done.sh: guard check not scoped to implementer role"
fi

# ── agent-done.sh: git snapshot for workspace detection ────────────
if grep -q 'git-snapshot' "$agent_done" 2>/dev/null; then
  pass "agent-done.sh: saves git snapshot for workspace detection"
else
  fail "agent-done.sh: missing git snapshot for workspace detection"
fi

# ── guard-prevent.sh: Bash boundary (D-203) ───────────────────────
assert_file_exists "$guard_prevent" "guard-prevent.sh exists"

if grep -q 'Bash' "$guard_prevent" 2>/dev/null; then
  pass "guard-prevent.sh: handles Bash tool"
else
  fail "guard-prevent.sh: missing Bash tool handling"
fi

if grep -q '\.moira' "$guard_prevent" 2>/dev/null && grep -q 'permissionDecision.*deny' "$guard_prevent" 2>/dev/null; then
  pass "guard-prevent.sh: allows .moira/ Bash, denies others"
else
  fail "guard-prevent.sh: Bash boundary logic incomplete"
fi

# ── pipeline-stop-guard.sh: completion processor check (D-203) ────
assert_file_exists "$pipeline_stop" "pipeline-stop-guard.sh exists"

if grep -q 'completion_dispatched' "$pipeline_stop" 2>/dev/null; then
  pass "pipeline-stop-guard.sh: checks completion_dispatched"
else
  fail "pipeline-stop-guard.sh: missing completion_dispatched check"
fi

if grep -q 'D-133\|completion processor' "$pipeline_stop" 2>/dev/null; then
  pass "pipeline-stop-guard.sh: references D-133 completion requirement"
else
  fail "pipeline-stop-guard.sh: missing D-133 reference"
fi

# ── pipeline-tracker.sh: completion processor detection (D-203) ───
assert_file_exists "$pipeline_tracker" "pipeline-tracker.sh exists"

if grep -q 'completion_dispatched' "$pipeline_tracker" 2>/dev/null; then
  pass "pipeline-tracker.sh: sets completion_dispatched flag"
else
  fail "pipeline-tracker.sh: missing completion_dispatched flag"
fi

# ── pipeline-dispatch.sh: workspace change detection (D-203) ──────
assert_file_exists "$pipeline_dispatch" "pipeline-dispatch.sh exists"

if grep -q 'WORKSPACE CHECK\|git-snapshot\|workspace_warning' "$pipeline_dispatch" 2>/dev/null; then
  pass "pipeline-dispatch.sh: contains workspace change detection"
else
  fail "pipeline-dispatch.sh: missing workspace change detection"
fi

# ── Syntax validation for modified hooks ──────────────────────────
echo ""
echo "--- Syntax Validation ---"

for hook in "$agent_done" "$guard_prevent" "$pipeline_stop" "$pipeline_dispatch" "$pipeline_tracker"; do
  hook_name=$(basename "$hook")
  if bash -n "$hook" 2>/dev/null; then
    pass "$hook_name: syntax valid"
  else
    fail "$hook_name: syntax errors detected"
  fi
done

test_summary
