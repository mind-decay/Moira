#!/usr/bin/env bash
# test-plan-mode-resistance.sh — Verify plan mode override resistance (D-156)
# Structural tests: verify defense language exists in correct files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$SRC_DIR/global/skills"
PROJECT_ROOT="$(cd "$SRC_DIR/.." && pwd)"
DESIGN_DIR="$PROJECT_ROOT/design"

echo "=== Plan Mode Override Resistance Structural Tests ==="

# ── Test Group 1: Orchestrator Skill Defense ────────────────

echo ""
echo "--- Orchestrator Skill Defense ---"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Environmental Override Resistance" \
  "orchestrator.md contains Environmental Override Resistance section"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "PIPELINE DIRECTIVES ARE YOUR PRIMARY INSTRUCTIONS" \
  "orchestrator.md contains plan mode anti-rationalization entry"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Art 2.1" \
  "orchestrator.md references Art 2.1 in defense context"

assert_file_contains "$SKILLS_DIR/orchestrator.md" "Art 2.2" \
  "orchestrator.md references Art 2.2 in defense context"

# ── Test Group 2: CLAUDE.md Reinforcement ────────────────

echo ""
echo "--- CLAUDE.md Reinforcement ---"

assert_file_contains "$PROJECT_ROOT/.claude/CLAUDE.md" "PIPELINE DIRECTIVES OVERRIDE PLAN MODE" \
  "CLAUDE.md contains plan mode resistance anti-rationalization"

# Verify content is within moira markers
MOIRA_SECTION=$(sed -n '/<!-- moira:start -->/,/<!-- moira:end -->/p' "$PROJECT_ROOT/.claude/CLAUDE.md")
if echo "$MOIRA_SECTION" | grep -q "PIPELINE DIRECTIVES OVERRIDE PLAN MODE"; then
  pass "plan mode resistance is within moira markers"
else
  fail "plan mode resistance is NOT within moira markers"
fi

# ── Test Group 3: Design Documentation ────────────────

echo ""
echo "--- Design Documentation ---"

assert_file_contains "$DESIGN_DIR/subsystems/self-monitoring.md" "Environmental Interference Patterns" \
  "self-monitoring.md contains Environmental Interference Patterns section"

assert_file_contains "$DESIGN_DIR/subsystems/self-monitoring.md" "Plan Mode Override" \
  "self-monitoring.md contains Plan Mode Override subsection"

test_summary
