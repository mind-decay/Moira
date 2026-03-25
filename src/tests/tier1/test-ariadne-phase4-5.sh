#!/usr/bin/env bash
# test-ariadne-phase4-5.sh — Verify Ariadne Phase 4/5 integration artifacts
# Tests MCP registry, knowledge matrix, agent roles, dispatch, graph baseline,
# analytical pipeline, and cross-reference manifest for Phase 4/5 tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MCP_SH="$SRC_DIR/global/lib/mcp.sh"
MATRIX_FILE="$SRC_DIR/global/core/knowledge-access-matrix.yaml"
ROLES_DIR="$SRC_DIR/global/core/rules/roles"
DISPATCH_FILE="$SRC_DIR/global/skills/dispatch.md"
GRAPH_SH="$SRC_DIR/global/lib/graph.sh"
ANALYTICAL_YAML="$SRC_DIR/global/core/pipelines/analytical.yaml"
XREF_MANIFEST="$SRC_DIR/global/core/xref-manifest.yaml"

echo "=== Ariadne Phase 4/5 Integration Tests ==="

# ═══════════════════════════════════════════════════════════════════════
# Test 1: MCP registry has all 15 Ariadne tools
# ═══════════════════════════════════════════════════════════════════════

ARIADNE_TOOLS=(blast-radius dependencies dependents cycles cluster smells symbols symbol-search callers callees symbol-blast-radius context tests-for reading-order plan-impact)
missing_tools=0
for tool in "${ARIADNE_TOOLS[@]}"; do
  if ! grep -q "^      ${tool}:" "$MCP_SH" 2>/dev/null; then
    ((missing_tools++)) || true
  fi
done

if [[ "$missing_tools" -eq 0 ]]; then
  pass "mcp.sh has all 15 Ariadne tool keys"
else
  fail "mcp.sh missing $missing_tools Ariadne tool keys (expected 15)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 2: New tools have required metadata fields
# ═══════════════════════════════════════════════════════════════════════

NEW_TOOLS=(symbols symbol-search callers callees symbol-blast-radius context tests-for reading-order plan-impact)
REQUIRED_FIELDS=(purpose cost reliability when_to_use when_NOT_to_use token_estimate)

all_metadata_ok=true
for tool in "${NEW_TOOLS[@]}"; do
  # Extract the block for this tool (from tool key to next tool key or heredoc end)
  tool_block=$(sed -n "/^      ${tool}:/,/^      [a-z]/p" "$MCP_SH" 2>/dev/null | head -20)
  for field in "${REQUIRED_FIELDS[@]}"; do
    if ! echo "$tool_block" | grep -q "$field:"; then
      fail "tool $tool missing field: $field"
      all_metadata_ok=false
    fi
  done
done

if $all_metadata_ok; then
  pass "all 9 new tools have required metadata (purpose, cost, reliability, when_to_use, when_NOT_to_use, token_estimate)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 3: Tool count is 15
# ═══════════════════════════════════════════════════════════════════════

if grep -q 'tool_count=\$((tool_count + 15))' "$MCP_SH" 2>/dev/null; then
  pass "mcp.sh has tool_count + 15 for Ariadne"
else
  fail "mcp.sh expected tool_count + 15 for Ariadne"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 4: Knowledge matrix has symbol extras
# ═══════════════════════════════════════════════════════════════════════

if grep -q "symbols" "$MATRIX_FILE" 2>/dev/null; then
  pass "knowledge-access-matrix.yaml has symbol references"
else
  fail "knowledge-access-matrix.yaml missing symbol references"
fi

if grep -q "symbol_search" "$MATRIX_FILE" 2>/dev/null; then
  pass "knowledge-access-matrix.yaml has symbol_search in extras"
else
  fail "knowledge-access-matrix.yaml missing symbol_search in extras"
fi

if grep -q "symbol_blast_radius" "$MATRIX_FILE" 2>/dev/null; then
  pass "knowledge-access-matrix.yaml has symbol_blast_radius in extras"
else
  fail "knowledge-access-matrix.yaml missing symbol_blast_radius in extras"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 5: Agent YAMLs reference new tools
# ═══════════════════════════════════════════════════════════════════════

AGENT_TOOL_PAIRS="hermes:ariadne_symbol_search athena:ariadne_plan_impact daedalus:ariadne_context hephaestus:ariadne_symbols themis:ariadne_callers aletheia:ariadne_tests_for"

for pair in $AGENT_TOOL_PAIRS; do
  agent="${pair%%:*}"
  expected_ref="${pair#*:}"
  if grep -q "$expected_ref" "$ROLES_DIR/${agent}.yaml" 2>/dev/null; then
    pass "${agent}.yaml references $expected_ref"
  else
    fail "${agent}.yaml missing reference to $expected_ref"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# Test 6: Agent NEVER constraints intact (regression)
# ═══════════════════════════════════════════════════════════════════════

AGENTS=(apollo hermes athena metis daedalus hephaestus themis aletheia mnemosyne argus calliope)
all_never_ok=true
for agent in "${AGENTS[@]}"; do
  role_file="$ROLES_DIR/${agent}.yaml"
  [[ -f "$role_file" ]] || continue

  never_count=$(grep -c '"Never ' "$role_file" 2>/dev/null || echo "0")
  if [[ "$never_count" -ge 3 ]]; then
    pass "${agent}: NEVER constraints intact ($never_count)"
  else
    fail "${agent}: NEVER constraints degraded ($never_count, need >= 3)"
    all_never_ok=false
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# Test 7: Dispatch references ariadne_context in step 4b
# ═══════════════════════════════════════════════════════════════════════

if grep -q "ariadne_context" "$DISPATCH_FILE" 2>/dev/null; then
  pass "dispatch.md references ariadne_context"
else
  fail "dispatch.md missing ariadne_context reference"
fi

if grep -q "budget_tokens" "$DISPATCH_FILE" 2>/dev/null; then
  pass "dispatch.md references budget_tokens parameter"
else
  fail "dispatch.md missing budget_tokens parameter reference"
fi

if grep -q "D-155" "$DISPATCH_FILE" 2>/dev/null; then
  pass "dispatch.md references D-155 decision"
else
  fail "dispatch.md missing D-155 decision reference"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 8: Graph baseline mentions Phase 4/5
# ═══════════════════════════════════════════════════════════════════════

if grep -q "Phase 4/5" "$GRAPH_SH" 2>/dev/null; then
  pass "graph.sh mentions Phase 4/5 MCP tools"
else
  fail "graph.sh missing Phase 4/5 MCP tools notice"
fi

if grep -q "ariadne_context" "$GRAPH_SH" 2>/dev/null; then
  pass "graph.sh lists ariadne_context in Phase 4/5 notice"
else
  fail "graph.sh missing ariadne_context in Phase 4/5 notice"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 9: Analytical YAML ariadne_focus updated
# ═══════════════════════════════════════════════════════════════════════

FOCUS_TOOLS=(ariadne_context ariadne_reading_order ariadne_plan_impact ariadne_symbol_blast_radius ariadne_tests_for ariadne_callers)
missing_focus=0
for tool in "${FOCUS_TOOLS[@]}"; do
  if ! grep -q "$tool" "$ANALYTICAL_YAML" 2>/dev/null; then
    ((missing_focus++)) || true
  fi
done

if [[ "$missing_focus" -eq 0 ]]; then
  pass "analytical.yaml ariadne_focus references all Phase 4/5 tools"
else
  fail "analytical.yaml ariadne_focus missing $missing_focus Phase 4/5 tool references"
fi

# ═══════════════════════════════════════════════════════════════════════
# Test 10: xref-017 exists
# ═══════════════════════════════════════════════════════════════════════

if grep -q "xref-017" "$XREF_MANIFEST" 2>/dev/null; then
  pass "xref-manifest.yaml has xref-017 entry"
else
  fail "xref-manifest.yaml missing xref-017 entry"
fi

if grep -q 'xref-017' "$XREF_MANIFEST" 2>/dev/null && grep -q 'mcp.sh' "$XREF_MANIFEST" 2>/dev/null; then
  pass "xref-017 references mcp.sh as canonical source"
else
  fail "xref-017 missing mcp.sh canonical source reference"
fi

test_summary
