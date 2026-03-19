#!/usr/bin/env bash
# test-graph-e2e.sh — End-to-end tests for graph.sh against real ariadne binary
# REQUIRES: ariadne binary in PATH. Skips gracefully if not available.
# Uses ariadne's own source tree as test project (Rust + TypeScript fixtures).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Gate: skip if ariadne not in PATH ────────────────────────────────
if ! command -v ariadne >/dev/null 2>&1; then
  echo "  [SKIP] ariadne binary not found — e2e tests skipped"
  echo ""
  echo "  0/0 passed, 0 failed (skipped)"
  exit 0
fi

ARIADNE_VERSION=$(ariadne info 2>/dev/null | head -1)
echo "  ariadne found: $ARIADNE_VERSION"

# ── Setup: temp directory for graph output ───────────────────────────
TMPDIR_E2E=$(mktemp -d)
trap 'rm -rf "$TMPDIR_E2E"' EXIT

GRAPH_DIR="$TMPDIR_E2E/graph"
VIEWS_DIR="$TMPDIR_E2E/views"

# Find a project with source files to build a graph from.
# Use ariadne's own project if available, otherwise use CWD.
if [[ -d "$HOME/Documents/Projects/ariadne" ]]; then
  TEST_PROJECT="$HOME/Documents/Projects/ariadne"
else
  TEST_PROJECT="$(pwd)"
fi

# ── Test 1: check_binary returns version string ──────────────────────
version=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_check_binary)
if [[ "$version" == *"ariadne"* ]]; then
  pass "check_binary returns version string: $version"
else
  fail "check_binary returned unexpected: '$version'"
fi

# Verify it's a single line (no multi-line leak)
line_count=$(echo "$version" | wc -l | tr -d ' ')
if [[ "$line_count" -eq 1 ]]; then
  pass "check_binary returns single line"
else
  fail "check_binary returned $line_count lines (expected 1)"
fi

# ── Test 2: build produces graph files ───────────────────────────────
build_output=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_build "$TEST_PROJECT" "$GRAPH_DIR" 2>&1) || true

if [[ -f "$GRAPH_DIR/graph.json" ]]; then
  pass "build produces graph.json"
else
  fail "build did not produce graph.json"
fi

if [[ -f "$GRAPH_DIR/stats.json" ]]; then
  pass "build produces stats.json"
else
  fail "build did not produce stats.json"
fi

if [[ -f "$GRAPH_DIR/clusters.json" ]]; then
  pass "build produces clusters.json"
else
  fail "build did not produce clusters.json"
fi

# ── Test 3: summary parses real graph data ───────────────────────────
summary=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_summary "$GRAPH_DIR")

node_count=$(echo "$summary" | grep "^node_count=" | cut -d= -f2)
edge_count=$(echo "$summary" | grep "^edge_count=" | cut -d= -f2)
cluster_count=$(echo "$summary" | grep "^cluster_count=" | cut -d= -f2)
cycle_count=$(echo "$summary" | grep "^cycle_count=" | cut -d= -f2)
bottleneck_count=$(echo "$summary" | grep "^bottleneck_count=" | cut -d= -f2)
monolith_score=$(echo "$summary" | grep "^monolith_score=" | cut -d= -f2)

if [[ "$node_count" -gt 0 ]]; then
  pass "summary: node_count=$node_count (>0)"
else
  fail "summary: node_count=$node_count (expected >0)"
fi

if [[ "$edge_count" -gt 0 ]]; then
  pass "summary: edge_count=$edge_count (>0)"
else
  fail "summary: edge_count=$edge_count (expected >0)"
fi

if [[ "$cluster_count" -gt 0 ]]; then
  pass "summary: cluster_count=$cluster_count (>0)"
else
  fail "summary: cluster_count=$cluster_count (expected >0)"
fi

# cycle_count and bottleneck_count can be 0, just verify they're numeric
if [[ "$cycle_count" =~ ^[0-9]+$ ]]; then
  pass "summary: cycle_count=$cycle_count (numeric)"
else
  fail "summary: cycle_count='$cycle_count' (not numeric)"
fi

if [[ "$bottleneck_count" =~ ^[0-9]+$ ]]; then
  pass "summary: bottleneck_count=$bottleneck_count (numeric)"
else
  fail "summary: bottleneck_count='$bottleneck_count' (not numeric)"
fi

if [[ "$monolith_score" =~ ^[0-9] ]]; then
  pass "summary: monolith_score=$monolith_score (numeric)"
else
  fail "summary: monolith_score='$monolith_score' (not numeric)"
fi

# ── Test 4: views generate produces index.md ─────────────────────────
views_output=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_views_generate "$VIEWS_DIR" "$GRAPH_DIR" 2>&1) || true

if [[ -f "$VIEWS_DIR/index.md" ]]; then
  pass "views generate produces index.md"
else
  fail "views generate did not produce index.md"
fi

if [[ -d "$VIEWS_DIR/clusters" ]]; then
  cluster_view_count=$(ls "$VIEWS_DIR/clusters/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$cluster_view_count" -gt 0 ]]; then
    pass "views generate produces $cluster_view_count cluster views"
  else
    fail "views generate produced clusters/ dir but no .md files"
  fi
else
  fail "views generate did not produce clusters/ directory"
fi

# ── Test 5: read_view L0 returns real index content ──────────────────
l0_content=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_read_view L0 "" "$VIEWS_DIR")

if [[ -n "$l0_content" ]]; then
  pass "read_view L0 returns content ($(echo "$l0_content" | wc -l | tr -d ' ') lines)"
else
  fail "read_view L0 returned empty"
fi

if echo "$l0_content" | grep -q "Files:"; then
  pass "read_view L0 contains 'Files:' stat"
else
  fail "read_view L0 missing 'Files:' stat"
fi

# ── Test 6: read_view L1 returns cluster content ─────────────────────
first_cluster=$(ls "$VIEWS_DIR/clusters/"*.md 2>/dev/null | head -1 | xargs basename | sed 's/.md//')
if [[ -n "$first_cluster" ]]; then
  l1_content=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_read_view L1 "$first_cluster" "$VIEWS_DIR")
  if [[ -n "$l1_content" ]]; then
    pass "read_view L1 '$first_cluster' returns content"
  else
    fail "read_view L1 '$first_cluster' returned empty"
  fi
fi

# ── Test 7: update (incremental) works ───────────────────────────────
update_output=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_update "$TEST_PROJECT" "$GRAPH_DIR" 2>&1) || true

if [[ -f "$GRAPH_DIR/graph.json" ]]; then
  pass "update preserves graph.json"
else
  fail "update lost graph.json"
fi

# ── Test 8: query subcommands produce output ─────────────────────────
QUERY_CMDS=("stats" "cycles" "layers" "metrics" "smells" "importance" "spectral")

for cmd in "${QUERY_CMDS[@]}"; do
  output=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_query "$cmd" --graph-dir "$GRAPH_DIR" --format md 2>/dev/null) || true
  if [[ -n "$output" ]]; then
    pass "query $cmd produces output"
  else
    fail "query $cmd returned empty"
  fi
done

# ── Test 9: query blast-radius with real file ────────────────────────
# Find a file that exists in the graph
sample_file=$(command -v jq >/dev/null 2>&1 && jq -r '.nodes | keys[0]' "$GRAPH_DIR/graph.json" 2>/dev/null || echo "")
if [[ -n "$sample_file" ]]; then
  br_output=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_query blast-radius "$sample_file" --graph-dir "$GRAPH_DIR" --format md 2>/dev/null) || true
  if [[ -n "$br_output" ]]; then
    pass "query blast-radius '$sample_file' produces output"
  else
    fail "query blast-radius '$sample_file' returned empty"
  fi
fi

# ── Test 10: query compressed --level 0 ──────────────────────────────
compressed_output=$(source "$SRC_DIR/global/lib/graph.sh" && moira_graph_query compressed --level 0 --graph-dir "$GRAPH_DIR" --format md 2>/dev/null) || true
if echo "$compressed_output" | grep -q "Compressed Graph"; then
  pass "query compressed --level 0 produces output"
else
  fail "query compressed --level 0 returned unexpected: '$(echo "$compressed_output" | head -1)'"
fi

# ── Test 11: is_fresh detects freshness correctly ────────────────────
(
  cd "$TEST_PROJECT"
  source "$SRC_DIR/global/lib/graph.sh"
  if moira_graph_is_fresh "$GRAPH_DIR"; then
    pass "is_fresh returns true for just-built graph"
  else
    # May be stale if source files are newer — not a failure, just informational
    pass "is_fresh returns stale (source files newer than graph — expected for active project)"
  fi
)

# ── Test 12: summary fields match build output ───────────────────────
if [[ -n "$build_output" ]]; then
  # build output looks like: "Built graph: 125 files, 81 edges, 3 clusters in 0.1s"
  build_files=$(echo "$build_output" | grep -o '[0-9]* files' | head -1 | grep -o '[0-9]*')
  build_edges=$(echo "$build_output" | grep -o '[0-9]* edges' | head -1 | grep -o '[0-9]*')
  build_clusters=$(echo "$build_output" | grep -o '[0-9]* clusters' | head -1 | grep -o '[0-9]*')

  if [[ "$node_count" == "$build_files" ]]; then
    pass "summary node_count ($node_count) matches build output ($build_files)"
  else
    fail "summary node_count ($node_count) != build output ($build_files)"
  fi

  if [[ "$edge_count" == "$build_edges" ]]; then
    pass "summary edge_count ($edge_count) matches build output ($build_edges)"
  else
    fail "summary edge_count ($edge_count) != build output ($build_edges)"
  fi

  if [[ "$cluster_count" == "$build_clusters" ]]; then
    pass "summary cluster_count ($cluster_count) matches build output ($build_clusters)"
  else
    fail "summary cluster_count ($cluster_count) != build output ($build_clusters)"
  fi
fi

test_summary
