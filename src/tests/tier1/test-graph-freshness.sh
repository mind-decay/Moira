#!/usr/bin/env bash
# test-graph-freshness.sh — Tier 1 tests for graduated graph freshness (D-224)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Graduated Graph Freshness (D-224)"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

source "$SRC_DIR/global/lib/task-init.sh"
set +e

# ── Setup: git repo with graph ──
PROJECT="$TEMP_DIR/project"
mkdir -p "$PROJECT/.moira/state/tasks" "$PROJECT/.moira/config" "$PROJECT/.ariadne/graph"

cd "$PROJECT"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create config and state files
cat > "$PROJECT/.moira/config.yaml" << 'EOF'
version: "1.0"
quality:
  mode: conform
graph:
  enabled: true
bootstrap:
  deep_scan_pending: false
EOF

cat > "$PROJECT/.moira/state/current.yaml" << 'EOF'
task_id: "T-001"
pipeline: null
step: "classification"
step_status: "pending"
graph_available: false
temporal_available: false
EOF

# Create graph files and commit
echo '{"nodes":[],"edges":[]}' > .ariadne/graph/graph.json
echo '{}' > .ariadne/graph/meta.json
git add -A && git commit -q -m "graph build"

# ── 1. Fresh graph (0 commits since) → info ──
output=$(moira_preflight_collect "$PROJECT/.moira/state" 2>/dev/null) || true
if echo "$output" | grep -q "graph_freshness=info"; then
  pass "freshness: 0 commits → info"
else
  fail "freshness: expected info for 0 commits, got: $(echo "$output" | grep graph_freshness)"
fi

# ── 2. 5 commits → still info ──
for i in $(seq 1 5); do
  echo "$i" > "file-$i.txt"
  git add -A && git commit -q -m "change $i"
done
output=$(moira_preflight_collect "$PROJECT/.moira/state" 2>/dev/null) || true
if echo "$output" | grep -q "graph_freshness=info"; then
  pass "freshness: 5 commits → info"
else
  fail "freshness: expected info for 5 commits"
fi

# ── 3. 15 total commits → warning ──
for i in $(seq 6 15); do
  echo "$i" > "file-$i.txt"
  git add -A && git commit -q -m "change $i"
done
output=$(moira_preflight_collect "$PROJECT/.moira/state" 2>/dev/null) || true
if echo "$output" | grep -q "graph_freshness=warning"; then
  pass "freshness: 15 commits → warning"
else
  fail "freshness: expected warning for 15 commits, got: $(echo "$output" | grep graph_freshness)"
fi

# ── 4. 35 total commits → high ──
for i in $(seq 16 35); do
  echo "$i" > "file-$i.txt"
  git add -A && git commit -q -m "change $i"
done
output=$(moira_preflight_collect "$PROJECT/.moira/state" 2>/dev/null) || true
if echo "$output" | grep -q "graph_freshness=high"; then
  pass "freshness: 35 commits → high"
else
  fail "freshness: expected high for 35 commits, got: $(echo "$output" | grep graph_freshness)"
fi

# ── 5. graph_stale backward compat ──
if echo "$output" | grep -q "graph_stale="; then
  pass "backward compat: graph_stale field still emitted"
else
  fail "backward compat: graph_stale should still be in output"
fi

# ── 6. graph_commits_since present ──
if echo "$output" | grep -q "graph_commits_since="; then
  pass "commits count: graph_commits_since field present"
else
  fail "commits count: graph_commits_since should be in output"
fi

test_summary
