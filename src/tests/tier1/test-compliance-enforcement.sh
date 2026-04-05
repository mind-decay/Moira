#!/usr/bin/env bash
# test-compliance-enforcement.sh — Phase 19 compliance enforcement tests
# Tests: checklist.sh, subagent whitelist (D-212), model enforcement (D-214),
#        stop guard reflection (D-211), SIGPIPE fix (D-213), entry point fixes (D-215/D-216)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ═══════════════════════════════════════════════════════════════════════
# checklist.sh (D-211 Layer 1)
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/lib/checklist.sh" "checklist.sh installed"

if [[ -f "$MOIRA_HOME/lib/checklist.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/checklist.sh" 2>/dev/null; then
    pass "checklist.sh syntax valid"
  else
    fail "checklist.sh has syntax errors"
  fi

  # Graceful degradation: no .moira/ directory
  output=$(cd /tmp && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline 2>/dev/null) || true
  if echo "$output" | grep -qi "skipped\|no moira" 2>/dev/null; then
    pass "checklist.sh: graceful skip without .moira/"
  else
    fail "checklist.sh: no graceful degradation without .moira/"
  fi

  # Graceful degradation: .moira/ exists but no config.yaml
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.moira/state"
  output=$(cd "$tmpdir" && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline 2>/dev/null) || true
  if echo "$output" | grep -qi "skipped\|no.*config" 2>/dev/null; then
    pass "checklist.sh: graceful skip without config.yaml"
  else
    fail "checklist.sh: no graceful degradation without config.yaml"
  fi
  rm -rf "$tmpdir"

  # Graceful degradation: config exists but no current.yaml
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.moira/state"
  echo "project_name: test" > "$tmpdir/.moira/config.yaml"
  output=$(cd "$tmpdir" && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline 2>/dev/null) || true
  if echo "$output" | grep -qi "skipped\|no.*task" 2>/dev/null; then
    pass "checklist.sh: graceful skip without current.yaml"
  else
    fail "checklist.sh: no graceful degradation without current.yaml"
  fi
  rm -rf "$tmpdir"

  # All checks passed scenario
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.moira/state"
  echo "project_name: test" > "$tmpdir/.moira/config.yaml"
  printf 'task_id: test-001\ndeep_scan_pending: false\ngraph_available: true\ntemporal_available: true\n' > "$tmpdir/.moira/state/current.yaml"
  output=$(cd "$tmpdir" && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline 2>/dev/null) || true
  if echo "$output" | grep -qi "passed\|proceed" 2>/dev/null; then
    pass "checklist.sh: all-passed output correct"
  else
    fail "checklist.sh: missing all-passed message"
  fi
  rm -rf "$tmpdir"

  # Deep scan pending generates dispatch instructions
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.moira/state"
  echo "project_name: test" > "$tmpdir/.moira/config.yaml"
  printf 'deep_scan_pending: true\n' >> "$tmpdir/.moira/config.yaml"
  printf 'task_id: test-001\ngraph_available: true\ntemporal_available: true\n' > "$tmpdir/.moira/state/current.yaml"
  output=$(cd "$tmpdir" && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline 2>/dev/null) || true
  if echo "$output" | grep -qi "deep scan\|PENDING" 2>/dev/null; then
    pass "checklist.sh: deep scan pending output"
  else
    fail "checklist.sh: no deep scan section when pending"
  fi
  rm -rf "$tmpdir"

  # Mechanical graph check: writes graph_available to current.yaml
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.moira/state" "$tmpdir/.ariadne/graph"
  echo '{}' > "$tmpdir/.ariadne/graph/graph.json"
  echo "project_name: test" > "$tmpdir/.moira/config.yaml"
  printf 'task_id: test-001\n' > "$tmpdir/.moira/state/current.yaml"
  cd "$tmpdir" && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline >/dev/null 2>&1 || true
  if grep -q "graph_available: true" "$tmpdir/.moira/state/current.yaml" 2>/dev/null; then
    pass "checklist.sh: mechanically sets graph_available=true"
  else
    fail "checklist.sh: did not write graph_available to current.yaml"
  fi
  rm -rf "$tmpdir"

  # Mechanical graph check: no graph → sets false
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.moira/state"
  echo "project_name: test" > "$tmpdir/.moira/config.yaml"
  printf 'task_id: test-001\n' > "$tmpdir/.moira/state/current.yaml"
  cd "$tmpdir" && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline >/dev/null 2>&1 || true
  if grep -q "graph_available: false" "$tmpdir/.moira/state/current.yaml" 2>/dev/null; then
    pass "checklist.sh: mechanically sets graph_available=false when no graph"
  else
    fail "checklist.sh: did not write graph_available=false"
  fi
  rm -rf "$tmpdir"

  # Exit code is always 0
  cd /tmp && bash "$MOIRA_HOME/lib/checklist.sh" pre-pipeline >/dev/null 2>&1
  assert_exit_code 0 $? "checklist.sh: always exits 0 (no args)"
  cd /tmp && bash "$MOIRA_HOME/lib/checklist.sh" unknown-arg >/dev/null 2>&1
  assert_exit_code 0 $? "checklist.sh: always exits 0 (bad args)"
fi

# task.md references checklist
assert_file_contains "$SRC_DIR/commands/moira/task.md" "checklist.sh" "task.md: references checklist.sh"
assert_file_contains "$SRC_DIR/commands/moira/task.md" "Step 3" "task.md: has Step 3 pre-pipeline check"
assert_file_contains "$SRC_DIR/commands/moira/task.md" "MANDATORY\|auto-injected\|pre-pipeline" "task.md: marks pre-pipeline as important"

# ═══════════════════════════════════════════════════════════════════════
# Subagent type whitelist (D-212)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "subagent_type" "pipeline-dispatch.sh: checks subagent_type (D-212)"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "general-purpose" "pipeline-dispatch.sh: allows general-purpose"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "D-212" "pipeline-dispatch.sh: references D-212"

# Functional: deny non-general-purpose subagent_type
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: exploration\nlast_role: classifier\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — test","subagent_type":"feature-dev:code-explorer","model":"sonnet"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "deny" 2>/dev/null; then
  pass "D-212: blocks non-general-purpose subagent_type"
else
  fail "D-212: did not block non-general-purpose subagent_type"
fi
rm -rf "$tmpdir"

# Functional: allow general-purpose
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: exploration\nlast_role: classifier\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — test","subagent_type":"general-purpose","model":"sonnet"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q '"deny"' 2>/dev/null; then
  fail "D-212: incorrectly blocked general-purpose"
else
  pass "D-212: allows general-purpose"
fi
rm -rf "$tmpdir"

# Functional: allow empty subagent_type
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: exploration\nlast_role: classifier\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — test","model":"sonnet"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q '"deny"' 2>/dev/null; then
  fail "D-212: incorrectly blocked empty subagent_type"
else
  pass "D-212: allows empty subagent_type"
fi
rm -rf "$tmpdir"

# Whitelist inactive without .guard-active
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
printf 'task_id: test-001\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"test","subagent_type":"feature-dev:code-explorer"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q '"deny"' 2>/dev/null; then
  fail "D-212: should not fire without .guard-active"
else
  pass "D-212: inactive without .guard-active"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# Model enforcement (D-214)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "D-214" "pipeline-dispatch.sh: references D-214"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "expected_model" "pipeline-dispatch.sh: has model lookup table"

# Functional: deny dispatch without model
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: exploration\nlast_role: classifier\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — test","subagent_type":"general-purpose"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "D-214" 2>/dev/null; then
  pass "D-214: blocks dispatch without model"
else
  fail "D-214: did not block dispatch without model"
fi
rm -rf "$tmpdir"

# Functional: allow dispatch with correct model
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: exploration\nlast_role: classifier\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — test","subagent_type":"general-purpose","model":"sonnet"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "D-214" 2>/dev/null; then
  fail "D-214: incorrectly blocked dispatch with correct model"
else
  pass "D-214: allows dispatch with model"
fi
rm -rf "$tmpdir"

# Functional: model table correctness — haiku for classifier
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Apollo (classifier) — test","subagent_type":"general-purpose"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "haiku" 2>/dev/null; then
  pass "D-214: suggests haiku for classifier"
else
  fail "D-214: wrong model suggestion for classifier"
fi
rm -rf "$tmpdir"

# Functional: model table correctness — opus for implementer
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: implementation\nlast_role: planner\ngraph_available: true\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Hephaestus (implementer) — test","subagent_type":"general-purpose"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "opus" 2>/dev/null; then
  pass "D-214: suggests opus for implementer"
else
  fail "D-214: wrong model suggestion for implementer"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# Pre-pipeline prerequisite check (D-211 Layer 2)
# ═══════════════════════════════════════════════════════════════════════

# Functional: deny first dispatch without graph_available
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Apollo (classifier) — test","subagent_type":"general-purpose","model":"haiku"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "D-211" 2>/dev/null; then
  pass "D-211 L2: blocks first dispatch without graph_available"
else
  fail "D-211 L2: did not block first dispatch without graph_available"
fi
rm -rf "$tmpdir"

# Functional: allow first dispatch with graph_available
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\ngraph_available: false\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Apollo (classifier) — test","subagent_type":"general-purpose","model":"haiku"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "D-211" 2>/dev/null; then
  fail "D-211 L2: incorrectly blocked with graph_available=false"
else
  pass "D-211 L2: allows first dispatch with graph_available set"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# Stop guard reflection enforcement (D-211 Layer 2)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" "reflection_dispatched" "stop-guard: checks reflection (D-211)"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" "D-211" "stop-guard: references D-211"

# Functional: block stop when reflection not dispatched (standard pipeline)
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: implementation\nstep_status: in_progress\ncompletion_dispatched: true\n' > "$tmpdir/.moira/state/current.yaml"
output=$(cd "$tmpdir" && echo '{}' | bash "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "reflection" 2>/dev/null; then
  pass "D-211: blocks stop without reflection (standard)"
else
  fail "D-211: did not block stop without reflection (standard)"
fi
rm -rf "$tmpdir"

# Functional: allow stop when reflection dispatched
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: implementation\nstep_status: in_progress\ncompletion_dispatched: true\nreflection_dispatched: true\n' > "$tmpdir/.moira/state/current.yaml"
output=$(cd "$tmpdir" && echo '{}' | bash "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "reflection" 2>/dev/null; then
  fail "D-211: incorrectly blocked stop with reflection dispatched"
else
  pass "D-211: allows stop with reflection dispatched"
fi
rm -rf "$tmpdir"

# Functional: no reflection enforcement for quick pipeline
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: quick\nstep: review\nstep_status: in_progress\ncompletion_dispatched: true\n' > "$tmpdir/.moira/state/current.yaml"
output=$(cd "$tmpdir" && echo '{}' | bash "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "reflection" 2>/dev/null; then
  fail "D-211: should not enforce reflection for quick pipeline"
else
  pass "D-211: no reflection enforcement for quick pipeline"
fi
rm -rf "$tmpdir"

# Functional: allow stop when checkpointed
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: implementation\nstep_status: checkpointed\ncompletion_dispatched: true\n' > "$tmpdir/.moira/state/current.yaml"
output=$(cd "$tmpdir" && echo '{}' | bash "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "reflection" 2>/dev/null; then
  fail "D-211: should not enforce reflection on checkpointed"
else
  pass "D-211: allows stop when checkpointed"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# Gate pending bypass (D-228/D-229)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" "gate_pending" "stop-guard: checks gate_pending (D-229)"

# Functional: gate_pending allows stop (normal gate pause, not premature exit)
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: classification\nstep_status: in_progress\ngate_pending: classification\n' > "$tmpdir/.moira/state/current.yaml"
output=$(cd "$tmpdir" && echo '{}' | bash "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "block" 2>/dev/null; then
  fail "D-229: gate_pending should bypass stop guard"
else
  pass "D-229: gate_pending bypasses stop guard"
fi
rm -rf "$tmpdir"

# Functional: gate_pending=null does NOT bypass
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: implementation\nstep_status: in_progress\ngate_pending: null\nreview_pending: true\n' > "$tmpdir/.moira/state/current.yaml"
output=$(cd "$tmpdir" && echo '{}' | bash "$MOIRA_HOME/hooks/pipeline-stop-guard.sh" 2>/dev/null) || true
if echo "$output" | grep -q "review" 2>/dev/null; then
  pass "D-229: gate_pending=null enforces normally"
else
  fail "D-229: gate_pending=null should still enforce blocks"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# Role→agent name mapping (D-228)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "_role_to_agent" "pipeline-dispatch.sh: has role→agent mapping (D-228)"
assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "agent_name.*_role_to_agent" "pipeline-dispatch.sh: uses mapping for preflight assembly"
assert_file_contains "$MOIRA_HOME/lib/budget.sh" "_moira_budget_role_to_agent" "budget.sh: has role→agent mapping (D-228)"

# ═══════════════════════════════════════════════════════════════════════
# Error logging (D-228)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/task-submit.sh" "errors.log" "task-submit.sh: logs errors (D-228)"
assert_file_contains "$MOIRA_HOME/hooks/agent-done.sh" "errors.log" "agent-done.sh: logs errors (D-228)"
assert_file_contains "$MOIRA_HOME/lib/completion.sh" "errors.log" "completion.sh: logs errors (D-228)"

# ═══════════════════════════════════════════════════════════════════════
# Reflector dispatch tracking
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$MOIRA_HOME/hooks/pipeline-dispatch.sh" "reflection_dispatched" "pipeline-dispatch.sh: tracks reflection dispatch"

# Functional: reflector dispatch writes marker
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
touch "$tmpdir/.moira/state/.guard-active"
printf 'task_id: test-001\npipeline: standard\nstep: review\n' > "$tmpdir/.moira/state/current.yaml"
input='{"tool_name":"Agent","tool_input":{"description":"Mnemosyne (reflector) — test","subagent_type":"general-purpose","run_in_background":true}}'
# Note: reflector is background but we test the foreground path for marker writing
input_fg='{"tool_name":"Agent","tool_input":{"description":"Mnemosyne (reflector) — test","subagent_type":"general-purpose"}}'
cd "$tmpdir" && echo "$input_fg" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" >/dev/null 2>&1 || true
if grep -q "reflection_dispatched: true" "$tmpdir/.moira/state/current.yaml" 2>/dev/null; then
  pass "reflector dispatch: writes reflection_dispatched marker"
else
  fail "reflector dispatch: did not write reflection_dispatched marker"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# SIGPIPE fix (D-213)
# ═══════════════════════════════════════════════════════════════════════

if [[ -f "$MOIRA_HOME/lib/graph.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/graph.sh" 2>/dev/null; then
    pass "graph.sh: syntax valid after SIGPIPE fix"
  else
    fail "graph.sh: syntax errors after SIGPIPE fix"
  fi

  # No jq|while antipattern (all should use process substitution)
  if grep -qE 'jq.*\| while' "$MOIRA_HOME/lib/graph.sh" 2>/dev/null; then
    fail "D-213: graph.sh still contains jq|while pipe pattern"
  else
    pass "D-213: no jq|while pipe patterns in graph.sh"
  fi

  # No grep|head|cut ordering (should be grep|cut|head)
  if grep -qE 'grep.*\| head.*\| cut' "$MOIRA_HOME/lib/graph.sh" 2>/dev/null; then
    fail "D-213: graph.sh still contains grep|head|cut ordering"
  else
    pass "D-213: grep|cut|head ordering correct in graph.sh"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Entry point fixes
# ═══════════════════════════════════════════════════════════════════════

# bypass.md redirects to /moira:task (D-215)
assert_file_contains "$SRC_DIR/commands/moira/bypass.md" "moira:task" "bypass.md: redirects to /moira:task (D-215)"
assert_file_contains "$SRC_DIR/commands/moira/bypass.md" "Skill" "bypass.md: Skill in allowed-tools (D-215)"
# Verify no inline orchestrator read in Step 3a
if grep -A5 "Step 3a" "$SRC_DIR/commands/moira/bypass.md" 2>/dev/null | grep -q "Read the orchestrator skill" 2>/dev/null; then
  fail "D-215: bypass.md Step 3a still has inline orchestrator read"
else
  pass "D-215: bypass.md Step 3a uses redirect, no inline read"
fi

# resume.md references .guard-active (D-216)
assert_file_contains "$SRC_DIR/commands/moira/resume.md" "guard-active" "resume.md: mentions .guard-active (D-216)"
assert_file_contains "$SRC_DIR/commands/moira/resume.md" "session-lock" "resume.md: mentions .session-lock (D-216)"

# task-submit.sh handles /moira:resume (D-216)
assert_file_contains "$MOIRA_HOME/hooks/task-submit.sh" "moira.*resume" "task-submit.sh: detects /moira:resume (D-216)"
assert_file_contains "$MOIRA_HOME/hooks/task-submit.sh" "guard-active" "task-submit.sh: creates .guard-active for resume"

# Functional: task-submit.sh creates guard-active on resume
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
printf 'task_id: test-001\nstep_status: checkpointed\npipeline: standard\nstep: implementation\n' > "$tmpdir/.moira/state/current.yaml"
input='{"prompt":"/moira:resume"}'
cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/task-submit.sh" >/dev/null 2>&1 || true
if [[ -f "$tmpdir/.moira/state/.guard-active" ]]; then
  pass "D-216: task-submit.sh creates .guard-active on resume"
else
  fail "D-216: task-submit.sh did not create .guard-active on resume"
fi
if [[ -f "$tmpdir/.moira/state/.session-lock" ]]; then
  pass "D-216: task-submit.sh creates .session-lock on resume"
else
  fail "D-216: task-submit.sh did not create .session-lock on resume"
fi
rm -rf "$tmpdir"

# ═══════════════════════════════════════════════════════════════════════
# Model-per-role in dispatch.md (D-214)
# ═══════════════════════════════════════════════════════════════════════

if [[ -f "$MOIRA_HOME/skills/dispatch.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "Model Selection Per Role" "dispatch.md: has model table (D-214)"
  assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "haiku" "dispatch.md: uses haiku"
  assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "opus" "dispatch.md: uses opus"
  assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "D-214" "dispatch.md: references D-214"

  # Dispatch templates include model parameter
  model_count=$(grep -c 'model:' "$MOIRA_HOME/skills/dispatch.md" 2>/dev/null) || model_count=0
  if [[ "$model_count" -ge 3 ]]; then
    pass "dispatch.md: model parameter in dispatch templates ($model_count occurrences)"
  else
    fail "dispatch.md: insufficient model parameter usage ($model_count, expected >= 3)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Anti-rationalization rules
# ═══════════════════════════════════════════════════════════════════════

if [[ -f "$MOIRA_HOME/skills/orchestrator.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "general-purpose.*D-212\|D-212.*general-purpose\|subagent_type.*general-purpose\|general-purpose.*subagent" "orchestrator.md: anti-rationalization for subagent_type (D-212)"
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "model.*D-214\|D-214.*model\|model parameter" "orchestrator.md: anti-rationalization for model (D-214)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Unguarded dispatch advisory
# ═══════════════════════════════════════════════════════════════════════

# Functional: advisory when Moira dispatch pattern without guard
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/.moira/state"
printf 'task_id: test-001\n' > "$tmpdir/.moira/state/current.yaml"
# NO .guard-active
input='{"tool_name":"Agent","tool_input":{"description":"Hermes (explorer) — test","subagent_type":"general-purpose"}}'
output=$(cd "$tmpdir" && echo "$input" | bash "$MOIRA_HOME/hooks/pipeline-dispatch.sh" 2>/dev/null) || true
if echo "$output" | grep -q "WARNING\|no active pipeline" 2>/dev/null; then
  pass "unguarded advisory: warns on Moira dispatch without guard"
else
  fail "unguarded advisory: no warning on Moira dispatch without guard"
fi
rm -rf "$tmpdir"

test_summary
