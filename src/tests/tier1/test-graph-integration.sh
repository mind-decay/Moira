#!/usr/bin/env bash
# test-graph-integration.sh — Verify Phase 13 graph integration
# Tests graph.sh functions, access matrix, commands, and cross-references.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Test 1: moira_graph_check_binary returns without crash ────────────
# Source graph.sh and call check_binary — must not crash regardless of ariadne presence
(
  source "$SRC_DIR/global/lib/graph.sh"
  moira_graph_check_binary >/dev/null 2>&1
) && pass "moira_graph_check_binary returns without crash" \
  || fail "moira_graph_check_binary crashed"

# ── Test 2: moira_graph_summary with mock data ───────────────────────
TMPDIR_GRAPH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_GRAPH"' EXIT

mkdir -p "$TMPDIR_GRAPH/graph"

# Create mock graph.json with 3 nodes and 2 edges
cat > "$TMPDIR_GRAPH/graph/graph.json" << 'MOCK_GRAPH'
{
  "nodes": {
    "src/a.ts": { "file_type": "typescript" },
    "src/b.ts": { "file_type": "typescript" },
    "src/c.ts": { "file_type": "typescript" }
  },
  "edges": [
    { "from": "src/a.ts", "to": "src/b.ts" },
    { "from": "src/b.ts", "to": "src/c.ts" }
  ]
}
MOCK_GRAPH

# Create mock stats.json
cat > "$TMPDIR_GRAPH/graph/stats.json" << 'MOCK_STATS'
{
  "monolith_score": 0.23,
  "sccs": [["src/a.ts", "src/b.ts"]]
}
MOCK_STATS

# Create mock clusters.json
cat > "$TMPDIR_GRAPH/graph/clusters.json" << 'MOCK_CLUSTERS'
{
  "clusters": {
    "core": { "internal_edges": 5 },
    "utils": { "internal_edges": 2 }
  }
}
MOCK_CLUSTERS

summary_output=$(
  source "$SRC_DIR/global/lib/graph.sh"
  moira_graph_summary "$TMPDIR_GRAPH/graph" 2>/dev/null
) || true

if echo "$summary_output" | grep -q "node_count="; then
  pass "moira_graph_summary returns node_count with mock data"
else
  fail "moira_graph_summary missing node_count with mock data"
fi

if echo "$summary_output" | grep -q "edge_count="; then
  pass "moira_graph_summary returns edge_count with mock data"
else
  fail "moira_graph_summary missing edge_count with mock data"
fi

if echo "$summary_output" | grep -q "cluster_count="; then
  pass "moira_graph_summary returns cluster_count with mock data"
else
  fail "moira_graph_summary missing cluster_count with mock data"
fi

# ── Test 3: moira_graph_summary with no graph.json ───────────────────
empty_summary=$(
  source "$SRC_DIR/global/lib/graph.sh"
  moira_graph_summary "/nonexistent/path" 2>/dev/null
) || true

if echo "$empty_summary" | grep -q "node_count=0"; then
  pass "moira_graph_summary returns node_count=0 without graph.json"
else
  fail "moira_graph_summary should return node_count=0 without graph.json"
fi

# ── Test 4: Access matrix has graph column for all agents ─────────────
MATRIX_FILE="$SRC_DIR/global/core/knowledge-access-matrix.yaml"

AGENTS=(apollo hermes athena metis daedalus hephaestus themis aletheia mnemosyne argus)
EXPECTED_LEVELS=(L0 L0 L1 L1 L1 L2 L1 L1 L2 L2)

for i in "${!AGENTS[@]}"; do
  agent="${AGENTS[$i]}"
  expected="${EXPECTED_LEVELS[$i]}"
  if grep "^  ${agent}:" "$MATRIX_FILE" 2>/dev/null | grep -q "graph: *${expected}"; then
    pass "matrix: ${agent} has graph: ${expected}"
  else
    fail "matrix: ${agent} expected graph: ${expected}"
  fi
done

# ── Test 5: No write access for graph ────────────────────────────────
# Check that no write_access agent row contains "graph: true"
if grep -A 50 "^write_access:" "$MATRIX_FILE" 2>/dev/null | grep -v '#' | grep -q "graph:"; then
  fail "graph should NOT appear in write_access agent rows"
else
  pass "no agent has write access to graph"
fi

# ── Test 6: moira_graph_read_view L0 with mock data ──────────────────
mkdir -p "$TMPDIR_GRAPH/views"
echo "# Project Graph Overview" > "$TMPDIR_GRAPH/views/index.md"

view_output=$(
  source "$SRC_DIR/global/lib/graph.sh"
  moira_graph_read_view L0 "" "$TMPDIR_GRAPH/views" 2>/dev/null
) || true

if [[ -n "$view_output" ]]; then
  pass "moira_graph_read_view L0 returns content when views exist"
else
  fail "moira_graph_read_view L0 should return content when views exist"
fi

# ── Test 7: moira_graph_read_view L0 without views ───────────────────
empty_view=$(
  source "$SRC_DIR/global/lib/graph.sh"
  moira_graph_read_view L0 "" "/nonexistent/views" 2>/dev/null
) || true

if [[ -z "$empty_view" ]]; then
  pass "moira_graph_read_view L0 returns empty when views don't exist"
else
  fail "moira_graph_read_view L0 should return empty when views don't exist"
fi

# ── Test 8: Daedalus references Project Graph ────────────────────────
DAEDALUS_FILE="$SRC_DIR/global/core/rules/roles/daedalus.yaml"
if grep -q "Project Graph" "$DAEDALUS_FILE" 2>/dev/null; then
  pass "daedalus.yaml references Project Graph"
else
  fail "daedalus.yaml should reference Project Graph"
fi

# ── Test 9: Graph command file exists with correct tools ─────────────
GRAPH_CMD="$SRC_DIR/commands/moira/graph.md"
assert_file_exists "$GRAPH_CMD" "graph.md command file exists"

if grep -q "allowed-tools:" "$GRAPH_CMD" 2>/dev/null; then
  pass "graph.md has allowed-tools frontmatter"
else
  fail "graph.md missing allowed-tools frontmatter"
fi

# ── Test 10: Health command references graph health checks ───────────
HEALTH_CMD="$SRC_DIR/commands/moira/health.md"
if grep -qi "graph" "$HEALTH_CMD" 2>/dev/null; then
  pass "health.md contains graph health references"
else
  fail "health.md missing graph health references"
fi

# ── Test 11: Install script includes graph.sh and graph command ──────
INSTALL_FILE="$SRC_DIR/install.sh"
if grep -q "graph.sh" "$INSTALL_FILE" 2>/dev/null; then
  pass "install.sh includes graph.sh in lib verification"
else
  fail "install.sh missing graph.sh in lib verification"
fi

if grep -q '"graph"' "$INSTALL_FILE" 2>/dev/null || grep -q ' graph)' "$INSTALL_FILE" 2>/dev/null || grep -q ' graph ' "$INSTALL_FILE" 2>/dev/null; then
  pass "install.sh includes graph in command verification"
else
  fail "install.sh missing graph in command verification"
fi

# ── Test 12: Refresh command references graph update ─────────────────
REFRESH_CMD="$SRC_DIR/commands/moira/refresh.md"
if grep -qi "graph" "$REFRESH_CMD" 2>/dev/null; then
  pass "refresh.md contains graph update references"
else
  fail "refresh.md missing graph update references"
fi

# ── Test 13: Graph command has all 12 subcommands ────────────────────
SUBCOMMANDS=(blast-radius cluster file cycles layers metrics smells importance spectral diff compressed stats)
missing_subs=0
for sub in "${SUBCOMMANDS[@]}"; do
  if ! grep -q "$sub" "$GRAPH_CMD" 2>/dev/null; then
    ((missing_subs++)) || true
  fi
done

if [[ "$missing_subs" -eq 0 ]]; then
  pass "graph.md contains all 12 subcommand patterns"
else
  fail "graph.md missing $missing_subs subcommand patterns"
fi

test_summary
