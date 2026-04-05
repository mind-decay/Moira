#!/usr/bin/env bash
# test-fn-integration-seams.sh — Functional tests for cross-component integration
# Tests the actual integration contracts between hooks and libraries.
# These tests would have caught D-229 bugs (role/agent name mismatch,
# stop guard blocking gates, silent failures).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: integration seams (functional)"

SRC_HOOKS_DIR="$SRC_DIR/src/global/hooks"

# ═══════════════════════════════════════════════════════════════════════
# SECTION 1: pipeline-stop-guard.sh + gate_pending
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "--- Stop Guard: gate_pending bypass ---"

# Setup: create state with active pipeline and gate_pending
stop_state="$TEMP_DIR/stop-gate"
mkdir -p "$stop_state/.moira/state"
touch "$stop_state/.moira/state/.guard-active"

# Test 1a: gate_pending set → stop allowed (no block)
cat > "$stop_state/.moira/state/current.yaml" << 'EOF'
task_id: test-001
pipeline: standard
step: classification
step_status: in_progress
gate_pending: classification
completion_dispatched: false
EOF

output=$(cd "$stop_state" && echo '{}' | bash "$SRC_HOOKS_DIR/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "block" 2>/dev/null; then
  fail "gate_pending=classification: should NOT block (gate is active, waiting for user)"
else
  pass "gate_pending=classification: allows stop (gate pause)"
fi

# Test 1b: gate_pending=null → normal enforcement applies
cat > "$stop_state/.moira/state/current.yaml" << 'EOF'
task_id: test-001
pipeline: standard
step: implementation
step_status: in_progress
gate_pending: null
review_pending: true
completion_dispatched: false
EOF

output=$(cd "$stop_state" && echo '{}' | bash "$SRC_HOOKS_DIR/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "review" 2>/dev/null; then
  pass "gate_pending=null: enforces review_pending block"
else
  fail "gate_pending=null: should block for review_pending"
fi

# Test 1c: gate_pending empty string → normal enforcement
cat > "$stop_state/.moira/state/current.yaml" << 'EOF'
task_id: test-001
pipeline: standard
step: implementation
step_status: in_progress
gate_pending: ""
review_pending: true
completion_dispatched: false
EOF

output=$(cd "$stop_state" && echo '{}' | bash "$SRC_HOOKS_DIR/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "review" 2>/dev/null; then
  pass "gate_pending='': enforces review_pending block"
else
  fail "gate_pending='': should block for review_pending"
fi

# Test 1d: no gate_pending field at all → normal enforcement
cat > "$stop_state/.moira/state/current.yaml" << 'EOF'
task_id: test-001
pipeline: standard
step: implementation
step_status: in_progress
review_pending: true
completion_dispatched: false
EOF

output=$(cd "$stop_state" && echo '{}' | bash "$SRC_HOOKS_DIR/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "review" 2>/dev/null; then
  pass "no gate_pending: enforces review_pending block"
else
  fail "no gate_pending: should block for review_pending"
fi

# Test 1e: gate_pending + completion not dispatched → gate takes priority
cat > "$stop_state/.moira/state/current.yaml" << 'EOF'
task_id: test-001
pipeline: full
step: review
step_status: in_progress
gate_pending: review
completion_dispatched: false
reflection_dispatched: false
EOF

output=$(cd "$stop_state" && echo '{}' | bash "$SRC_HOOKS_DIR/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "block" 2>/dev/null; then
  fail "gate_pending=review: should NOT block even without completion/reflection"
else
  pass "gate_pending=review: gate bypass takes priority over all blocks"
fi

# ═══════════════════════════════════════════════════════════════════════
# SECTION 2: pipeline-dispatch.sh role→agent name mapping
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "--- Dispatch Hook: role→agent name mapping ---"

# We can't easily test the full hook (needs Agent tool JSON input),
# but we can test the _role_to_agent function by sourcing just that part.
# Extract and test the mapping function.

# Create a minimal test that exercises the mapping via the hook.
dispatch_state="$TEMP_DIR/dispatch-map"
mkdir -p "$dispatch_state/.moira/state/tasks/test-001/instructions"
touch "$dispatch_state/.moira/state/.guard-active"
touch "$dispatch_state/.moira/state/tasks/test-001/input.md"

cat > "$dispatch_state/.moira/state/current.yaml" << 'EOF'
task_id: test-001
pipeline: standard
step: exploration
step_status: in_progress
dispatched_role: null
graph_available: true
last_role: classifier
EOF

# Setup MOIRA_HOME for dispatch hook to find preflight-assemble.sh
mkdir -p "$MOIRA_HOME/lib"
mkdir -p "$MOIRA_HOME/core/rules/roles"
# Copy all lib files — rules.sh sources knowledge.sh, mcp.sh, yaml-utils.sh
for lib_file in "$SRC_LIB_DIR"/*.sh; do
  cp "$lib_file" "$MOIRA_HOME/lib/" 2>/dev/null || true
done

cat > "$MOIRA_HOME/core/rules/base.yaml" << 'EOF'
version: "1.0"
EOF

cat > "$MOIRA_HOME/core/rules/knowledge-matrix.yaml" << 'EOF'
matrix:
  hermes: ["stack"]
EOF

cat > "$MOIRA_HOME/core/rules/roles/hermes.yaml" << 'EOF'
_meta:
  role: explorer
identity: |
  You are Hermes, the explorer.
never:
  - "Modify files"
budget: 140000
EOF

# Feed the hook a JSON payload simulating Agent dispatch for Hermes (explorer)
dispatch_json='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — Explore the codebase","prompt":"explore","model":"sonnet","subagent_type":"general-purpose"}}'

output=$(cd "$dispatch_state" && echo "$dispatch_json" | MOIRA_HOME="$MOIRA_HOME" bash "$SRC_HOOKS_DIR/pipeline-dispatch.sh" 2>/dev/null) || true

# Check that dispatched_role was written
dispatched_role=$(grep '^dispatched_role:' "$dispatch_state/.moira/state/current.yaml" 2>/dev/null | sed 's/^dispatched_role:[[:space:]]*//' | tr -d '"' | tr -d "'")
if [[ "$dispatched_role" == "explorer" ]]; then
  pass "dispatch: writes dispatched_role=explorer"
else
  fail "dispatch: expected dispatched_role=explorer, got '$dispatched_role'"
fi

# Check that instruction file was created with AGENT name (hermes), not role name (explorer)
if [[ -f "$dispatch_state/.moira/state/tasks/test-001/instructions/explorer.md" ]]; then
  fail "dispatch: created explorer.md (role name) instead of hermes.md — D-229 bug!"
else
  pass "dispatch: no explorer.md created (role name not used as filename)"
fi

if [[ -f "$dispatch_state/.moira/state/tasks/test-001/instructions/hermes.md" ]]; then
  pass "dispatch: hermes.md created (correct agent name mapping)"
else
  fail "dispatch: hermes.md not created — preflight assembly failed or wrong name used"
fi

# ═══════════════════════════════════════════════════════════════════════
# SECTION 3: budget.sh role→agent name for role file lookup
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "--- Budget: role file lookup with role names ---"

source "$SRC_LIB_DIR/budget.sh"
set +e

# Setup role files with budget values
for agent_file in hermes athena metis hephaestus themis; do
  cat > "$MOIRA_HOME/core/rules/roles/${agent_file}.yaml" << EOF
budget: 999999
EOF
done

# Test: look up budget using ROLE NAME — should resolve to agent file
run_fn _moira_budget_get_agent_budget "explorer" ""
if [[ "$FN_STDOUT" == "999999" ]]; then
  pass "budget: role name 'explorer' resolves to hermes.yaml budget"
else
  # Falls back to hardcoded default — role file not found
  if [[ "$FN_STDOUT" == "140000" ]]; then
    fail "budget: 'explorer' fell back to hardcoded default (role file lookup failed)"
  else
    fail "budget: 'explorer' returned unexpected value '$FN_STDOUT'"
  fi
fi

# Test: look up with agent name directly
run_fn _moira_budget_get_agent_budget "hermes" ""
# Agent name "hermes" has no hardcoded default, so it should find the role file
if [[ "$FN_STDOUT" == "999999" ]]; then
  pass "budget: agent name 'hermes' resolves to role file budget"
else
  fail "budget: 'hermes' returned '$FN_STDOUT', expected 999999"
fi

# Test: mapping function itself
run_fn _moira_budget_role_to_agent "explorer"
assert_output_equals "$FN_STDOUT" "hermes" "role_to_agent: explorer→hermes"

run_fn _moira_budget_role_to_agent "analyst"
assert_output_equals "$FN_STDOUT" "athena" "role_to_agent: analyst→athena"

run_fn _moira_budget_role_to_agent "implementer"
assert_output_equals "$FN_STDOUT" "hephaestus" "role_to_agent: implementer→hephaestus"

run_fn _moira_budget_role_to_agent "hermes"
assert_output_equals "$FN_STDOUT" "hermes" "role_to_agent: hermes passthrough (already agent name)"

run_fn _moira_budget_role_to_agent "unknown"
assert_output_equals "$FN_STDOUT" "unknown" "role_to_agent: unknown passthrough"

# ═══════════════════════════════════════════════════════════════════════
# SECTION 4: Error logging — silent failures now leave traces
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "--- Error logging: critical failures are recorded ---"

# Test task-submit.sh error logging: missing task-init.sh
error_state="$TEMP_DIR/error-log"
mkdir -p "$error_state/.moira/state"

# Simulate task-submit with missing lib
submit_json='{"prompt":"/moira:task test error logging"}'
MOIRA_HOME="$TEMP_DIR/nonexistent-moira" \
  bash -c "cd '$error_state' && echo '$submit_json' | bash '$SRC_HOOKS_DIR/task-submit.sh'" 2>/dev/null || true

if [[ -f "$error_state/.moira/state/errors.log" ]]; then
  if grep -q "task-init.sh not found" "$error_state/.moira/state/errors.log" 2>/dev/null; then
    pass "error-log: task-submit records missing task-init.sh"
  else
    fail "error-log: task-submit wrote to errors.log but wrong message"
  fi
else
  fail "error-log: task-submit did not create errors.log on failure"
fi

test_summary
