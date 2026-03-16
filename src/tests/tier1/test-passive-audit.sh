#!/usr/bin/env bash
# test-passive-audit.sh — Verify passive audit check artifacts in orchestrator and gates
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

test_summary
