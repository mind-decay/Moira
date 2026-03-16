#!/usr/bin/env bash
# test-tweak-redo.sh — Verify tweak/redo flow artifacts in orchestrator and gates
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

# ── Orchestrator tweak flow ──────────────────────────────────────────
assert_file_exists "$orchestrator" "orchestrator.md exists"

if grep -qi "Scope check\|tweak_files\|force-tweak" "$orchestrator" 2>/dev/null; then
  pass "orchestrator.md contains tweak flow logic"
else
  fail "orchestrator.md missing tweak flow logic (Scope check / tweak_files / force-tweak)"
fi

# ── Orchestrator redo flow ───────────────────────────────────────────
if grep -qi "Re-entry\|redo_count\|git revert" "$orchestrator" 2>/dev/null; then
  pass "orchestrator.md contains redo flow logic"
else
  fail "orchestrator.md missing redo flow logic (Re-entry / redo_count / git revert)"
fi

# ── Orchestrator knowledge/failures reference ────────────────────────
if grep -q "knowledge/failures" "$orchestrator" 2>/dev/null; then
  pass "orchestrator.md references knowledge/failures write"
else
  fail "orchestrator.md missing knowledge/failures reference"
fi

# ── Gates tweak scope gate ───────────────────────────────────────────
assert_file_exists "$gates" "gates.md exists"

if grep -qi "TWEAK: Scope Check\|force-tweak" "$gates" 2>/dev/null; then
  pass "gates.md contains tweak scope gate template"
else
  fail "gates.md missing tweak scope gate (TWEAK: Scope Check / force-tweak)"
fi

# ── Gates redo re-entry gate ─────────────────────────────────────────
if grep -qi "REDO\|Re-entry Point" "$gates" 2>/dev/null; then
  pass "gates.md contains redo re-entry gate template"
else
  fail "gates.md missing redo re-entry gate (REDO / Re-entry Point)"
fi

test_summary
