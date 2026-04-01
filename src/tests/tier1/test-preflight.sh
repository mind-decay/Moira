#!/usr/bin/env bash
# test-preflight.sh — Tier 1 tests for preflight context collection (D-199)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Preflight Context Collection (D-199)"

# ── Setup test environment ──
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# Create minimal Moira project structure
mkdir -p "$TEST_TMP/.claude/moira/state/tasks"
mkdir -p "$TEST_TMP/.claude/moira/config"
mkdir -p "$TEST_TMP/.claude/moira/knowledge"
mkdir -p "$TEST_TMP/.ariadne/graph"

# Create config.yaml
cat > "$TEST_TMP/.claude/moira/config.yaml" << 'EOF'
version: "1.0"
quality:
  mode: conform
  evolution:
    current_target: ""
graph:
  enabled: true
bootstrap:
  deep_scan_pending: false
mcp:
  enabled: true
EOF

# Create current.yaml
cat > "$TEST_TMP/.claude/moira/state/current.yaml" << 'EOF'
task_id: "T-001"
pipeline: null
step: "classification"
step_status: "pending"
graph_available: false
temporal_available: false
EOF

# Create graph.json (graph available)
echo '{"nodes":[],"edges":[]}' > "$TEST_TMP/.ariadne/graph/graph.json"

# Init git repo for staleness check
git -C "$TEST_TMP" init -q 2>/dev/null
git -C "$TEST_TMP" config user.email "test@test.com" 2>/dev/null
git -C "$TEST_TMP" config user.name "Test" 2>/dev/null
git -C "$TEST_TMP" add -A 2>/dev/null
git -C "$TEST_TMP" commit -m "init" -q 2>/dev/null

# Source task-init.sh
source "$SRC_DIR/global/lib/task-init.sh"

# ── Test 1: Basic preflight collection ──
output=$(moira_preflight_collect "$TEST_TMP/.claude/moira/state" 2>/dev/null) || true
if echo "$output" | grep -q "graph_available=true"; then
  pass "preflight detects graph_available=true"
else
  fail "preflight should detect graph_available=true, got: $output"
fi

if echo "$output" | grep -q "quality_mode=conform"; then
  pass "preflight reads quality_mode"
else
  fail "preflight should read quality_mode=conform"
fi

if echo "$output" | grep -q "bench_mode=false"; then
  pass "preflight reads bench_mode"
else
  fail "preflight should read bench_mode=false"
fi

if echo "$output" | grep -q "deep_scan_pending=false"; then
  pass "preflight reads deep_scan_pending"
else
  fail "preflight should read deep_scan_pending=false"
fi

if echo "$output" | grep -q "checkpointed=false"; then
  pass "preflight reads checkpointed state"
else
  fail "preflight should read checkpointed=false"
fi

if echo "$output" | grep -q "audit_pending=false"; then
  pass "preflight reads audit_pending"
else
  fail "preflight should read audit_pending=false"
fi

if echo "$output" | grep -q "orphaned_state=false"; then
  pass "preflight reads orphaned_state"
else
  fail "preflight should read orphaned_state=false"
fi

# ── Test 2: Graph disabled ──
sed -i.bak 's/enabled: true/enabled: false/' "$TEST_TMP/.claude/moira/config.yaml" 2>/dev/null
rm -f "$TEST_TMP/.claude/moira/config.yaml.bak"
output2=$(moira_preflight_collect "$TEST_TMP/.claude/moira/state" 2>/dev/null) || true
if echo "$output2" | grep -q "graph_available=false"; then
  pass "preflight respects graph.enabled=false"
else
  fail "preflight should respect graph.enabled=false"
fi
# Restore
sed -i.bak 's/enabled: false/enabled: true/' "$TEST_TMP/.claude/moira/config.yaml" 2>/dev/null
rm -f "$TEST_TMP/.claude/moira/config.yaml.bak"

# ── Test 3: Checkpointed task detection ──
sed -i.bak 's/step_status: "pending"/step_status: "checkpointed"/' "$TEST_TMP/.claude/moira/state/current.yaml" 2>/dev/null
rm -f "$TEST_TMP/.claude/moira/state/current.yaml.bak"
output3=$(moira_preflight_collect "$TEST_TMP/.claude/moira/state" 2>/dev/null) || true
if echo "$output3" | grep -q "checkpointed=true"; then
  pass "preflight detects checkpointed state"
else
  fail "preflight should detect checkpointed=true"
fi
if echo "$output3" | grep -q "checkpointed_task=T-001"; then
  pass "preflight reads checkpointed task_id"
else
  fail "preflight should read checkpointed_task=T-001"
fi
# Restore
sed -i.bak 's/step_status: "checkpointed"/step_status: "pending"/' "$TEST_TMP/.claude/moira/state/current.yaml" 2>/dev/null
rm -f "$TEST_TMP/.claude/moira/state/current.yaml.bak"

# ── Test 4: Audit pending detection ──
cat > "$TEST_TMP/.claude/moira/state/audit-pending.yaml" << 'EOF'
audit_pending: light
EOF
output4=$(moira_preflight_collect "$TEST_TMP/.claude/moira/state" 2>/dev/null) || true
if echo "$output4" | grep -q "audit_pending=true"; then
  pass "preflight detects audit_pending"
else
  fail "preflight should detect audit_pending=true"
fi
if echo "$output4" | grep -q "audit_depth=light"; then
  pass "preflight reads audit depth"
else
  fail "preflight should read audit_depth=light"
fi
rm -f "$TEST_TMP/.claude/moira/state/audit-pending.yaml"

# ── Test 5: graph_available written to current.yaml ──
# Re-run preflight to ensure it writes graph_available
moira_preflight_collect "$TEST_TMP/.claude/moira/state" >/dev/null 2>&1 || true
ga=$(grep '^graph_available:' "$TEST_TMP/.claude/moira/state/current.yaml" 2>/dev/null | sed 's/.*: //' | tr -d ' ')
if [[ "$ga" == "true" ]]; then
  pass "preflight writes graph_available to current.yaml"
else
  fail "preflight should write graph_available=true to current.yaml, got: $ga"
fi

# ── Test 6: Evolve quality mode ──
cat > "$TEST_TMP/.claude/moira/config.yaml" << 'EOF'
version: "1.0"
quality:
  mode: evolve
  evolution:
    current_target: "error-handling"
graph:
  enabled: true
bootstrap:
  deep_scan_pending: false
EOF
output6=$(moira_preflight_collect "$TEST_TMP/.claude/moira/state" 2>/dev/null) || true
if echo "$output6" | grep -q "quality_mode=evolve"; then
  pass "preflight reads evolve mode"
else
  fail "preflight should read quality_mode=evolve"
fi
if echo "$output6" | grep -q "evolution_target=error-handling"; then
  pass "preflight reads evolution target"
else
  fail "preflight should read evolution_target=error-handling"
fi

test_summary
