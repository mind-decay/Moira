#!/usr/bin/env bash
# test-ariadne-phase6-7.sh — Verify Ariadne Phase 6/7 integration artifacts
# Tests MCP registry, agent roles, design docs, commands, and decision log
# for Phase 6 (annotations/bookmarks) and Phase 7 (temporal analysis) tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MCP_SH="$SRC_DIR/global/lib/mcp.sh"
ROLES_DIR="$SRC_DIR/global/core/rules/roles"
GRAPH_CMD="$SRC_DIR/commands/moira/graph.md"
STATUS_CMD="$SRC_DIR/commands/moira/status.md"
HEALTH_CMD="$SRC_DIR/commands/moira/health.md"
GRAPH_DESIGN="$REPO_ROOT/design/subsystems/project-graph.md"
DECISION_LOG="$REPO_ROOT/design/decisions/log.md"
GRAPH_SH="$SRC_DIR/global/lib/graph.sh"

echo "=== Ariadne Phase 6/7 Integration Tests ==="

# ═══════════════════════════════════════════════════════════════════════
# Test 1: MCP registry has Phase 6 tools (6 tools)
# ═══════════════════════════════════════════════════════════════════════

PHASE6_TOOLS=(annotate annotations remove-annotation bookmark bookmarks remove-bookmark)
missing_p6=0
for tool in "${PHASE6_TOOLS[@]}"; do
  if ! grep -q "${tool}" "$MCP_SH" 2>/dev/null; then
    ((missing_p6++)) || true
  fi
done

if [[ "$missing_p6" -eq 0 ]]; then
  pass "mcp.sh has all 6 Phase 6 tool references"
else
  fail "mcp.sh missing $missing_p6 Phase 6 tool references (expected 6)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 2: MCP registry has Phase 7 tools (5 tools)
# ═══════════════════════════════════════════════════════════════════════

PHASE7_TOOLS=(churn coupling hotspots ownership hidden-deps)
missing_p7=0
for tool in "${PHASE7_TOOLS[@]}"; do
  if ! grep -q "${tool}" "$MCP_SH" 2>/dev/null; then
    ((missing_p7++)) || true
  fi
done

if [[ "$missing_p7" -eq 0 ]]; then
  pass "mcp.sh has all 5 Phase 7 tool references"
else
  fail "mcp.sh missing $missing_p7 Phase 7 tool references (expected 5)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 3: Design doc — project-graph.md has Phase 6 section
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Phase 6 — MCP Protocol Expansion" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md has Phase 6 section"
else
  fail "project-graph.md missing Phase 6 section"
fi

if grep -q "ariadne_annotate" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents ariadne_annotate tool"
else
  fail "project-graph.md missing ariadne_annotate documentation"
fi

if grep -q "ariadne_bookmark" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents ariadne_bookmark tool"
else
  fail "project-graph.md missing ariadne_bookmark documentation"
fi

if grep -q "annotations.json" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents annotations.json storage"
else
  fail "project-graph.md missing annotations.json storage documentation"
fi

if grep -q "bookmarks.json" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents bookmarks.json storage"
else
  fail "project-graph.md missing bookmarks.json storage documentation"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 4: Design doc — project-graph.md has Phase 7 section
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Phase 7 — Git Temporal Analysis" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md has Phase 7 section"
else
  fail "project-graph.md missing Phase 7 section"
fi

if grep -q "ariadne_churn" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents ariadne_churn tool"
else
  fail "project-graph.md missing ariadne_churn documentation"
fi

if grep -q "ariadne_hidden_deps" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents ariadne_hidden_deps tool"
else
  fail "project-graph.md missing ariadne_hidden_deps documentation"
fi

if grep -q "temporal_available" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents temporal_available flag"
else
  fail "project-graph.md missing temporal_available documentation"
fi

if grep -q "Graceful Degradation" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents graceful degradation"
else
  fail "project-graph.md missing graceful degradation documentation"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 5: Design doc — tool count updated to 37
# ═══════════════════════════════════════════════════════════════════════

if grep -q "37 total" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md tool count updated to 37"
else
  fail "project-graph.md tool count not updated to 37"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 6: Decision log — D-157 through D-161
# ═══════════════════════════════════════════════════════════════════════

DECISIONS=(D-157 D-158 D-159 D-160 D-161)
for decision in "${DECISIONS[@]}"; do
  if grep -q "$decision" "$DECISION_LOG" 2>/dev/null; then
    pass "decision log has $decision"
  else
    fail "decision log missing $decision"
  fi
done

# Verify key content in decisions
if grep -q "Role-Level Write Restriction" "$DECISION_LOG" 2>/dev/null; then
  pass "D-157 has correct title (Role-Level Write Restriction)"
else
  fail "D-157 missing correct title"
fi

if grep -q "Bookmark Lifecycle" "$DECISION_LOG" 2>/dev/null; then
  pass "D-160 has correct title (Bookmark Lifecycle)"
else
  fail "D-160 missing correct title"
fi

if grep -q "Temporal Tools" "$DECISION_LOG" 2>/dev/null; then
  pass "D-161 has correct title (Temporal Tools)"
else
  fail "D-161 missing correct title"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 7: graph.md command — temporal subcommands
# ═══════════════════════════════════════════════════════════════════════

TEMPORAL_SUBCMDS=(churn coupling hotspots ownership hidden-deps)
missing_subcmds=0
for subcmd in "${TEMPORAL_SUBCMDS[@]}"; do
  if ! grep -q "\`${subcmd}\`" "$GRAPH_CMD" 2>/dev/null; then
    ((missing_subcmds++)) || true
  fi
done

if [[ "$missing_subcmds" -eq 0 ]]; then
  pass "graph.md has all 5 temporal subcommands"
else
  fail "graph.md missing $missing_subcmds temporal subcommands"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 8: graph.md command — annotation/bookmark subcommands
# ═══════════════════════════════════════════════════════════════════════

ANNOT_SUBCMDS=(annotate annotations bookmark bookmarks)
missing_annot=0
for subcmd in "${ANNOT_SUBCMDS[@]}"; do
  if ! grep -q "\`${subcmd}\`" "$GRAPH_CMD" 2>/dev/null; then
    ((missing_annot++)) || true
  fi
done

if [[ "$missing_annot" -eq 0 ]]; then
  pass "graph.md has all 4 annotation/bookmark subcommands"
else
  fail "graph.md missing $missing_annot annotation/bookmark subcommands"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 9: graph.md — temporal_available gate
# ═══════════════════════════════════════════════════════════════════════

if grep -q "temporal_available" "$GRAPH_CMD" 2>/dev/null; then
  pass "graph.md gates temporal subcommands on temporal_available"
else
  fail "graph.md missing temporal_available gate"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 10: status.md — temporal summary line
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Temporal:" "$STATUS_CMD" 2>/dev/null; then
  pass "status.md has Temporal summary line"
else
  fail "status.md missing Temporal summary line"
fi

if grep -q "Annotations:" "$STATUS_CMD" 2>/dev/null; then
  pass "status.md has Annotations count"
else
  fail "status.md missing Annotations count"
fi

if grep -q "Bookmarks:" "$STATUS_CMD" 2>/dev/null; then
  pass "status.md has Bookmarks count"
else
  fail "status.md missing Bookmarks count"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 11: health.md — temporal health checks
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Temporal Health" "$HEALTH_CMD" 2>/dev/null; then
  pass "health.md has Temporal Health section"
else
  fail "health.md missing Temporal Health section"
fi

if grep -q "hotspot" "$HEALTH_CMD" 2>/dev/null; then
  pass "health.md has hotspot threshold check"
else
  fail "health.md missing hotspot threshold check"
fi

if grep -q "hidden.dep" "$HEALTH_CMD" 2>/dev/null; then
  pass "health.md has hidden deps threshold check"
else
  fail "health.md missing hidden deps threshold check"
fi

if grep -q "churn" "$HEALTH_CMD" 2>/dev/null; then
  pass "health.md has churn bottleneck check"
else
  fail "health.md missing churn bottleneck check"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 12: Phase 6/7 tool tables in project-graph.md
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Phase 6 Tools" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md has Phase 6 Tools table in MCP section"
else
  fail "project-graph.md missing Phase 6 Tools table in MCP section"
fi

if grep -q "Phase 7 Tools" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md has Phase 7 Tools table in MCP section"
else
  fail "project-graph.md missing Phase 7 Tools table in MCP section"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 13: MCP Resources and Prompts integrated (D-162, D-163)
# ═══════════════════════════════════════════════════════════════════════

if grep -q "ariadne://overview" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents MCP resources"
else
  fail "project-graph.md missing MCP resources documentation"
fi

if grep -q "D-162" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md references D-162 for MCP resources"
else
  fail "project-graph.md missing D-162 reference for MCP resources"
fi

if grep -q "explore-area" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md documents MCP prompts"
else
  fail "project-graph.md missing MCP prompts documentation"
fi

if grep -q "D-163" "$GRAPH_DESIGN" 2>/dev/null; then
  pass "project-graph.md references D-163 for MCP prompts"
else
  fail "project-graph.md missing D-163 reference for MCP prompts"
fi

# Verify old "not integrated" language is gone
if grep -q "documented, not integrated" "$GRAPH_DESIGN" 2>/dev/null; then
  fail "project-graph.md still contains stale 'documented, not integrated' text"
else
  pass "project-graph.md no longer contains 'documented, not integrated'"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 14: graph.sh has Phase 6/7 notice
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Phase 6" "$GRAPH_SH" 2>/dev/null && grep -q "Phase 7" "$GRAPH_SH" 2>/dev/null; then
  pass "graph.sh mentions Phase 6 and Phase 7 MCP tools"
else
  fail "graph.sh missing Phase 6/7 MCP tools notice"
fi

test_summary
