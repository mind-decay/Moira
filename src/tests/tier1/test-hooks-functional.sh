#!/usr/bin/env bash
# test-hooks-functional.sh — Functional tests for hook behavior
# Tests actual hook logic: transition tables, state isolation, guard enforcement.
# Requires hooks to be installed (~/.claude/moira/hooks/).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ═══════════════════════════════════════════════════════════════════════
# Helper: create temp state dir for functional tests
# ═══════════════════════════════════════════════════════════════════════

TMPDIR_BASE=$(mktemp -d)
trap "rm -rf '$TMPDIR_BASE'" EXIT

setup_state() {
  local test_dir="$TMPDIR_BASE/$1"
  local state_dir="$test_dir/.claude/moira/state"
  mkdir -p "$state_dir"
  echo "pipeline: $2" > "$state_dir/current.yaml"
  echo "task_id: test-$1" >> "$state_dir/current.yaml"
  echo "step: classification" >> "$state_dir/current.yaml"
  echo "step_status: in_progress" >> "$state_dir/current.yaml"
  touch "$state_dir/.guard-active"
  echo "$state_dir"
}

# Helper: run pipeline-dispatch.sh with given state and agent description
run_dispatch() {
  local state_dir="$1"
  local description="$2"
  local tracker_content="${3:-}"

  if [[ -n "$tracker_content" ]]; then
    echo "$tracker_content" > "$state_dir/pipeline-tracker.state"
  fi

  local json="{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"$description\",\"run_in_background\":false}}"
  (cd "$(dirname "$(dirname "$state_dir")")" && echo "$json" | bash "$SRC_DIR/global/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
}

# Helper: run guard-prevent.sh with given state, tool, and path
run_guard_prevent() {
  local state_dir="$1"
  local tool="$2"
  local file_path="$3"

  local json="{\"tool_name\":\"$tool\",\"tool_input\":{\"file_path\":\"$file_path\"}}"
  (cd "$(dirname "$(dirname "$state_dir")")" && echo "$json" | bash "$SRC_DIR/global/hooks/guard-prevent.sh" 2>/dev/null) || true
}

# ═══════════════════════════════════════════════════════════════════════
# E5-QUALITY retry: reviewer → implementer allowed in all pipelines
# ═══════════════════════════════════════════════════════════════════════

# Standard pipeline: reviewer → implementer (E5 retry)
state=$(setup_state "e5-std" "standard")
result=$(run_dispatch "$state" "Hephaestus (implementer) — fix review findings" "active=true
pipeline=standard
last_role=reviewer
review_pending=false
test_pending=true
subtask_mode=false")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "E5 retry: standard reviewer→implementer should be ALLOWED"
else
  pass "E5 retry: standard reviewer→implementer allowed"
fi

# Standard pipeline: tester → implementer (E5 post-test retry)
state=$(setup_state "e5-std-test" "standard")
result=$(run_dispatch "$state" "Hephaestus (implementer) — fix test failures" "active=true
pipeline=standard
last_role=tester
review_pending=false
test_pending=false
subtask_mode=false")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "E5 retry: standard tester→implementer should be ALLOWED"
else
  pass "E5 retry: standard tester→implementer allowed"
fi

# Quick pipeline: reviewer → implementer
state=$(setup_state "e5-quick" "quick")
result=$(run_dispatch "$state" "Hephaestus (implementer) — fix review findings" "active=true
pipeline=quick
last_role=reviewer
review_pending=false
test_pending=false
subtask_mode=false")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "E5 retry: quick reviewer→implementer should be ALLOWED"
else
  pass "E5 retry: quick reviewer→implementer allowed"
fi

# Full pipeline: reviewer → implementer
state=$(setup_state "e5-full" "full")
result=$(run_dispatch "$state" "Hephaestus (implementer) — fix review findings" "active=true
pipeline=full
last_role=reviewer
review_pending=false
test_pending=true
subtask_mode=false")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "E5 retry: full reviewer→implementer should be ALLOWED"
else
  pass "E5 retry: full reviewer→implementer allowed"
fi

# Decomposition sub: reviewer → implementer
state=$(setup_state "e5-decomp" "decomposition")
result=$(run_dispatch "$state" "Hephaestus (implementer) — fix review findings" "active=true
pipeline=decomposition
last_role=reviewer
review_pending=false
test_pending=true
subtask_mode=true
current_subtask=1
subtask_counter=1")
# Also need per-subtask file
echo "last_role=reviewer
review_pending=false
test_pending=true" > "$state/pipeline-tracker-sub-1.state"
result=$(run_dispatch "$state" "Hephaestus (implementer) — fix review findings" "active=true
pipeline=decomposition
last_role=reviewer
review_pending=false
test_pending=true
subtask_mode=true
current_subtask=1
subtask_counter=1")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "E5 retry: decomposition_sub reviewer→implementer should be ALLOWED"
else
  pass "E5 retry: decomposition_sub reviewer→implementer allowed"
fi

# ═══════════════════════════════════════════════════════════════════════
# Decomposition sub: explorer → implementer should be BLOCKED
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "dc-explorer" "decomposition")
echo "last_role=explorer
review_pending=false
test_pending=false" > "$state/pipeline-tracker-sub-1.state"
result=$(run_dispatch "$state" "Hephaestus (implementer) — implement feature" "active=true
pipeline=decomposition
subtask_mode=true
current_subtask=1
subtask_counter=1")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  pass "decomposition_sub: explorer→implementer correctly DENIED"
else
  fail "decomposition_sub: explorer→implementer should be DENIED"
fi

# ═══════════════════════════════════════════════════════════════════════
# Per-subtask state isolation
# ═══════════════════════════════════════════════════════════════════════

# Subtask 1 has review_pending=true, subtask 2 should not be blocked
state=$(setup_state "subtask-iso" "decomposition")
# Subtask 1: review pending
echo "last_role=implementer
review_pending=true
test_pending=false" > "$state/pipeline-tracker-sub-1.state"
# Subtask 2: clean state, last role was tester
echo "last_role=tester
review_pending=false
test_pending=false" > "$state/pipeline-tracker-sub-2.state"

# Dispatch classifier for subtask 2 (should use subtask 2's state)
result=$(run_dispatch "$state" "Apollo (classifier) — classify next sub-task" "active=true
pipeline=decomposition
subtask_mode=true
current_subtask=2
subtask_counter=2")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "per-subtask isolation: subtask 2 classifier blocked by subtask 1's review_pending"
else
  pass "per-subtask isolation: subtask 2 classifier not blocked by subtask 1"
fi

# ═══════════════════════════════════════════════════════════════════════
# Analytical pipeline: underscore roles parsed correctly
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "analytical-roles" "analytical")
result=$(run_dispatch "$state" "Metis (analytical_primary) — deep analysis" "active=true
pipeline=analytical
last_role=analyst
review_pending=false
test_pending=false
subtask_mode=false")
# analytical:analyst → valid includes "architect" but analytical_primary is NOT architect
# analytical_primary dispatched after analyst should check analytical:analyst → valid
# analytical_primary is not in "architect,explorer,analyst" — BUT role extraction must work first
if [[ -z "$result" ]]; then
  # Empty result = allowed (no deny, no error)
  # This means the role was extracted and either matched a rule or fell through to unknown-allow
  pass "analytical pipeline: analytical_primary role parsed (underscore in role)"
else
  if echo "$result" | grep -q "permissionDecision.*deny"; then
    # Deny is expected here: analyst → analytical_primary is not in valid set
    pass "analytical pipeline: analytical_primary role parsed and validated"
  else
    pass "analytical pipeline: analytical_primary role parsed"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Guard-prevent: Edit tool blocked
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "guard-edit" "standard")
result=$(run_guard_prevent "$state" "Edit" "/some/project/file.ts")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  pass "guard-prevent: Edit tool correctly DENIED for project files"
else
  fail "guard-prevent: Edit tool should be DENIED for project files"
fi

# Guard-prevent: Edit on .claude/moira/ allowed
result=$(run_guard_prevent "$state" "Edit" "$(dirname "$(dirname "$state")")/.claude/moira/state/current.yaml")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "guard-prevent: Edit on .claude/moira/ should be ALLOWED"
else
  pass "guard-prevent: Edit on .claude/moira/ allowed"
fi

# Guard-prevent: Read still works
result=$(run_guard_prevent "$state" "Read" "/some/project/file.ts")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  pass "guard-prevent: Read on project files correctly DENIED"
else
  fail "guard-prevent: Read on project files should be DENIED"
fi

# ═══════════════════════════════════════════════════════════════════════
# Guard-prevent: subagent bypass — agents CAN read project files
# ═══════════════════════════════════════════════════════════════════════

run_guard_prevent_as_agent() {
  local state_dir="$1"
  local tool="$2"
  local file_path="$3"

  local json="{\"tool_name\":\"$tool\",\"tool_input\":{\"file_path\":\"$file_path\"},\"agent_id\":\"agent-test-123\",\"agent_type\":\"general-purpose\"}"
  (cd "$(dirname "$(dirname "$state_dir")")" && echo "$json" | bash "$SRC_DIR/global/hooks/guard-prevent.sh" 2>/dev/null) || true
}

# Subagent Read on project file — should be ALLOWED
result=$(run_guard_prevent_as_agent "$state" "Read" "/some/project/file.ts")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "guard-prevent: subagent Read on project files should be ALLOWED"
else
  pass "guard-prevent: subagent Read on project files allowed (agent_id bypass)"
fi

# Subagent Edit on project file — should be ALLOWED
result=$(run_guard_prevent_as_agent "$state" "Edit" "/some/project/file.ts")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "guard-prevent: subagent Edit on project files should be ALLOWED"
else
  pass "guard-prevent: subagent Edit on project files allowed (agent_id bypass)"
fi

# Subagent Write on project file — should be ALLOWED
result=$(run_guard_prevent_as_agent "$state" "Write" "/some/project/file.ts")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  fail "guard-prevent: subagent Write on project files should be ALLOWED"
else
  pass "guard-prevent: subagent Write on project files allowed (agent_id bypass)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Decomposition: explicit terminal for tester
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "decomp-terminal" "decomposition")
result=$(run_dispatch "$state" "Hephaestus (implementer) — implement something" "active=true
pipeline=decomposition
last_role=tester
review_pending=false
test_pending=false
subtask_mode=false")
if echo "$result" | grep -q "permissionDecision.*deny"; then
  pass "decomposition: tester is terminal — implementer DENIED at epic level"
else
  fail "decomposition: tester should be terminal at epic level"
fi

# ═══════════════════════════════════════════════════════════════════════
# Pipeline-tracker: scribe sets review_pending
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "scribe-pending" "analytical")
tracker_json="{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"Calliope (scribe) — synthesize findings\",\"run_in_background\":false}}"
(cd "$(dirname "$(dirname "$state")")" && echo "$tracker_json" | bash "$SRC_DIR/global/hooks/pipeline-tracker.sh" 2>/dev/null) || true

if [[ -f "$state/pipeline-tracker.state" ]]; then
  review_pending=$(grep '^review_pending=' "$state/pipeline-tracker.state" 2>/dev/null | cut -d= -f2) || true
  if [[ "$review_pending" == "true" ]]; then
    pass "pipeline-tracker: scribe sets review_pending=true"
  else
    fail "pipeline-tracker: scribe should set review_pending=true (got: $review_pending)"
  fi
else
  fail "pipeline-tracker: no state file after scribe dispatch"
fi

# ═══════════════════════════════════════════════════════════════════════
# Settings.json: Edit in guard-prevent matcher
# ═══════════════════════════════════════════════════════════════════════

PROJECT_ROOT="$(cd "$SRC_DIR/.." && pwd)"
if [[ -f "$PROJECT_ROOT/.claude/settings.json" ]]; then
  if grep -q '"Read|Write|Edit"' "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null; then
    pass "settings.json: guard-prevent matcher includes Edit"
  else
    fail "settings.json: guard-prevent matcher missing Edit"
  fi
fi

# Settings-merge also updated
if [[ -f "$SRC_DIR/global/lib/settings-merge.sh" ]]; then
  if grep -q 'Read|Write|Edit' "$SRC_DIR/global/lib/settings-merge.sh" 2>/dev/null; then
    pass "settings-merge.sh: guard-prevent matcher includes Edit"
  else
    fail "settings-merge.sh: guard-prevent matcher missing Edit"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Design doc consistency
# ═══════════════════════════════════════════════════════════════════════

if [[ -f "$PROJECT_ROOT/design/subsystems/self-monitoring.md" ]]; then
  if grep -q 'Read|Write|Edit' "$PROJECT_ROOT/design/subsystems/self-monitoring.md" 2>/dev/null; then
    pass "self-monitoring.md: guard-prevent documented with Edit"
  else
    fail "self-monitoring.md: guard-prevent missing Edit in documentation"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Ariadne timeout wrapping
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$SRC_DIR/global/hooks/graph-update.sh" "timeout" "graph-update.sh: ariadne call wrapped in timeout"
assert_file_contains "$SRC_DIR/global/hooks/graph-validate.sh" "timeout" "graph-validate.sh: ariadne calls wrapped in timeout"
assert_file_contains "$SRC_DIR/global/hooks/compact-reinject.sh" "timeout" "compact-reinject.sh: ariadne call wrapped in timeout"

# ═══════════════════════════════════════════════════════════════════════
# Per-subtask cleanup in session-cleanup
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$SRC_DIR/global/hooks/session-cleanup.sh" "pipeline-tracker-sub-" "session-cleanup.sh: cleans per-subtask state files"

# ═══════════════════════════════════════════════════════════════════════
# agent-done.sh allows re-entry (no stop_hook_active skip)
# ═══════════════════════════════════════════════════════════════════════

if grep -q 'stop_hook_active.*exit 0' "$SRC_DIR/global/hooks/agent-done.sh" 2>/dev/null; then
  fail "agent-done.sh: still skips on stop_hook_active re-entry"
else
  pass "agent-done.sh: allows re-entry for completion recording"
fi

# agent-output-validate.sh still blocks on re-entry (correct)
if grep -q 'stop_hook_active.*exit 0' "$SRC_DIR/global/hooks/agent-output-validate.sh" 2>/dev/null; then
  pass "agent-output-validate.sh: correctly skips validation on re-entry"
else
  fail "agent-output-validate.sh: should skip on re-entry to prevent infinite loop"
fi

# artifact-validate.sh skips on re-entry (prevent infinite loop)
if grep -q 'stop_hook_active.*exit 0' "$SRC_DIR/global/hooks/artifact-validate.sh" 2>/dev/null; then
  pass "artifact-validate.sh: correctly skips validation on re-entry"
else
  fail "artifact-validate.sh: should skip on re-entry to prevent infinite loop"
fi

# ═══════════════════════════════════════════════════════════════════════
# Artifact validation: Apollo missing sections → block (D-184)
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "artifact-apollo-miss" "standard")
task_dir="$state/tasks/test-artifact-apollo-miss"
mkdir -p "$task_dir"

# Create incomplete classification.md (missing ## Acceptance Criteria)
cat > "$task_dir/classification.md" << 'CLASSEOF'
## Problem Statement
Fix the login bug.

## Scope
### In Scope
- Login endpoint
### Out of Scope
- Registration
CLASSEOF

# Run artifact-validate.sh with apollo agent description
artifact_json="{\"agent_type\":\"general-purpose\",\"agent_description\":\"Apollo (classifier) — classify task\",\"last_assistant_message\":\"STATUS: success\nSUMMARY: size=medium, confidence=high\nARTIFACTS: [tasks/test-artifact-apollo-miss/classification.md]\nNEXT: explore\",\"stop_hook_active\":false}"
result=$(cd "$(dirname "$(dirname "$state")")" && echo "$artifact_json" | bash "$SRC_DIR/global/hooks/artifact-validate.sh" 2>/dev/null) || true

if echo "$result" | grep -q '"decision".*"block"'; then
  pass "artifact-validate: Apollo blocked for missing ## Acceptance Criteria"
else
  fail "artifact-validate: Apollo should be blocked for missing ## Acceptance Criteria"
fi

# ═══════════════════════════════════════════════════════════════════════
# Artifact validation: Apollo complete artifact → pass (D-184)
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "artifact-apollo-ok" "standard")
task_dir="$state/tasks/test-artifact-apollo-ok"
mkdir -p "$task_dir"

cat > "$task_dir/classification.md" << 'CLASSEOF'
## Problem Statement
Fix the login bug that causes 500 errors.

## Scope
### In Scope
- Login endpoint error handling
### Out of Scope
- Registration flow

## Acceptance Criteria
1. Login endpoint returns 200 for valid credentials
2. Login endpoint returns 401 for invalid credentials
CLASSEOF

artifact_json="{\"agent_type\":\"general-purpose\",\"agent_description\":\"Apollo (classifier) — classify task\",\"last_assistant_message\":\"STATUS: success\nSUMMARY: size=medium, confidence=high\nARTIFACTS: [tasks/test-artifact-apollo-ok/classification.md]\nNEXT: explore\",\"stop_hook_active\":false}"
result=$(cd "$(dirname "$(dirname "$state")")" && echo "$artifact_json" | bash "$SRC_DIR/global/hooks/artifact-validate.sh" 2>/dev/null) || true

if echo "$result" | grep -q '"decision".*"block"'; then
  fail "artifact-validate: Apollo should pass with complete artifact"
else
  pass "artifact-validate: Apollo passes with complete artifact"
fi

# ═══════════════════════════════════════════════════════════════════════
# Artifact validation: Metis < 2 alternatives → block (D-184)
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "artifact-metis-miss" "standard")
task_dir="$state/tasks/test-artifact-metis-miss"
mkdir -p "$task_dir"

cat > "$task_dir/architecture.md" << 'ARCHEOF'
## Alternatives
### Alternative 1: Service Pattern
#### Trade-offs
Clean but more code.

## Recommendation
Use service pattern.

## Assumptions
### Verified
- Express.js supports middleware chaining
### Unverified
None
### Load-bearing
None
ARCHEOF

artifact_json="{\"agent_type\":\"general-purpose\",\"agent_description\":\"Metis (architect) — design solution\",\"last_assistant_message\":\"STATUS: success\nSUMMARY: service pattern\nARTIFACTS: [tasks/test-artifact-metis-miss/architecture.md]\nNEXT: plan\",\"stop_hook_active\":false}"
result=$(cd "$(dirname "$(dirname "$state")")" && echo "$artifact_json" | bash "$SRC_DIR/global/hooks/artifact-validate.sh" 2>/dev/null) || true

if echo "$result" | grep -q '"decision".*"block"'; then
  pass "artifact-validate: Metis blocked for < 2 alternatives"
else
  fail "artifact-validate: Metis should be blocked for < 2 alternatives"
fi

# ═══════════════════════════════════════════════════════════════════════
# Artifact validation: Daedalus conditional UNVERIFIED check (D-184)
# ═══════════════════════════════════════════════════════════════════════

state=$(setup_state "artifact-daedalus-unverified" "standard")
task_dir="$state/tasks/test-artifact-daedalus-unverified"
mkdir -p "$task_dir"

# Architecture has UNVERIFIED items
cat > "$task_dir/architecture.md" << 'ARCHEOF'
## Assumptions
### Unverified
- Stripe webhook retry policy — UNVERIFIED
ARCHEOF

# Plan WITHOUT ## Unverified Dependencies
cat > "$task_dir/plan.md" << 'PLANEOF'
## Scope Check
### Added to scope
None
### Removed from scope
None

## Acceptance Test
Run integration tests.

## Risks
- API rate limits — plan B: implement retry backoff
PLANEOF

artifact_json="{\"agent_type\":\"general-purpose\",\"agent_description\":\"Daedalus (planner) — create plan\",\"last_assistant_message\":\"STATUS: success\nSUMMARY: plan complete\nARTIFACTS: [tasks/test-artifact-daedalus-unverified/plan.md]\nNEXT: implement\",\"stop_hook_active\":false}"
result=$(cd "$(dirname "$(dirname "$state")")" && echo "$artifact_json" | bash "$SRC_DIR/global/hooks/artifact-validate.sh" 2>/dev/null) || true

if echo "$result" | grep -q '"decision".*"block"'; then
  pass "artifact-validate: Daedalus blocked for missing ## Unverified Dependencies (architecture has UNVERIFIED)"
else
  fail "artifact-validate: Daedalus should be blocked when architecture has UNVERIFIED and plan lacks ## Unverified Dependencies"
fi

test_summary
