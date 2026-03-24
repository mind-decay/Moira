#!/usr/bin/env bash
# test-budget-system.sh — Tier 1 structural verification for Phase 7 budget system
# Tests: budget library, config template, integration points, orchestrator health thresholds.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Budget library existence and syntax ──────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/budget.sh" "lib/budget.sh exists"
if [[ -f "$MOIRA_HOME/lib/budget.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/budget.sh" 2>/dev/null; then
    pass "lib/budget.sh syntax valid"
  else
    fail "lib/budget.sh has syntax errors"
  fi
fi

# ── Budget library functions exist ───────────────────────────────────
if [[ -f "$MOIRA_HOME/lib/budget.sh" ]]; then
  # Source budget.sh and check that all 9 functions are defined
  budget_funcs=(
    moira_budget_estimate_tokens
    moira_budget_estimate_batch
    moira_budget_estimate_agent
    moira_budget_check_overflow
    moira_budget_record_agent
    moira_budget_orchestrator_check
    moira_budget_generate_report
    moira_budget_write_telemetry
    moira_budget_handle_overflow
  )

  for func in "${budget_funcs[@]}"; do
    if bash -c "source '$MOIRA_HOME/lib/budget.sh' && declare -f '$func' > /dev/null 2>&1"; then
      pass "function $func exists"
    else
      fail "function $func not found in budget.sh"
    fi
  done
fi

# ── Budget configuration template ───────────────────────────────────
assert_file_exists "$MOIRA_HOME/templates/budgets.yaml.tmpl" "templates/budgets.yaml.tmpl exists"

if [[ -f "$MOIRA_HOME/templates/budgets.yaml.tmpl" ]]; then
  assert_file_contains "$MOIRA_HOME/templates/budgets.yaml.tmpl" "agent_budgets:" "template has agent_budgets"
  assert_file_contains "$MOIRA_HOME/templates/budgets.yaml.tmpl" "max_load_percent:" "template has max_load_percent"
  assert_file_contains "$MOIRA_HOME/templates/budgets.yaml.tmpl" "orchestrator_capacity:" "template has orchestrator_capacity"
  assert_file_contains "$MOIRA_HOME/templates/budgets.yaml.tmpl" "mcp_estimates:" "template has mcp_estimates"

  # Check all 10 agent roles in template
  agents=(classifier explorer analyst architect planner implementer reviewer tester reflector auditor)
  for agent in "${agents[@]}"; do
    assert_file_contains "$MOIRA_HOME/templates/budgets.yaml.tmpl" "$agent:" "template has $agent budget"
  done
fi

# ── Integration: orchestrator skill references budget ────────────────
if [[ -f "$MOIRA_HOME/skills/orchestrator.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "Budget Monitoring" "orchestrator.md has Budget Monitoring section"
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "Budget Report" "orchestrator.md has Budget Report section"
fi

# ── Integration: gates skill contains budget report template ─────────
if [[ -f "$MOIRA_HOME/skills/gates.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/gates.md" "CONTEXT BUDGET REPORT" "gates.md has budget report template"
fi

# ── Integration: errors skill contains E4-BUDGET ─────────────────────
if [[ -f "$MOIRA_HOME/skills/errors.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/errors.md" "E4-BUDGET" "errors.md has E4-BUDGET section"
fi

# ── Integration: dispatch skill contains budget context ──────────────
if [[ -f "$MOIRA_HOME/skills/dispatch.md" ]]; then
  assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "Context Budget" "dispatch.md has Context Budget section"
fi

# ── Integration: planner role mentions budget estimation ─────────────
if [[ -f "$MOIRA_HOME/core/rules/roles/daedalus.yaml" ]]; then
  assert_file_contains "$MOIRA_HOME/core/rules/roles/daedalus.yaml" "budget estimate" "daedalus.yaml mentions budget estimation"
fi

# ── Integration: response contract includes budget_exceeded ──────────
if [[ -f "$MOIRA_HOME/core/response-contract.yaml" ]]; then
  assert_file_contains "$MOIRA_HOME/core/response-contract.yaml" "budget_exceeded" "response contract has budget_exceeded status"
fi

# ── Orchestrator health thresholds ───────────────────────────────────
if [[ -f "$MOIRA_HOME/skills/orchestrator.md" ]]; then
  # Check all 4 health levels are defined (Healthy/<25%, Monitor/25-40%, Warning/40-60%, Critical/>60%)
  for level in Healthy Monitor Warning Critical; do
    assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "$level" "orchestrator.md defines $level level"
  done

  # Check threshold values match design: <25%, 25-40%, 40-60%, >60%
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "<25%" "orchestrator.md has <25% threshold"
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "25-40%" "orchestrator.md has 25-40% threshold"
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" "40-60%" "orchestrator.md has 40-60% threshold"
  assert_file_contains "$MOIRA_HOME/skills/orchestrator.md" ">60%" "orchestrator.md has >60% threshold"
fi

# ── Budget orchestrator formula correctness (D-146) ──────────────────
if [[ -f "$MOIRA_HOME/lib/budget.sh" ]]; then
  # Constant exists
  assert_file_contains "$MOIRA_HOME/lib/budget.sh" "_MOIRA_BUDGET_ORCH_PER_AGENT_RETURN=" "budget.sh has per-agent-return constant"

  # Formula uses per-agent-return estimate, not raw agent_tokens
  if grep -q '+ agent_tokens' "$MOIRA_HOME/lib/budget.sh" 2>/dev/null; then
    fail "budget.sh formula still uses raw agent_tokens (D-146 regression)"
  else
    pass "budget.sh formula does not use raw agent_tokens"
  fi

  assert_file_contains "$MOIRA_HOME/lib/budget.sh" "_MOIRA_BUDGET_ORCH_PER_AGENT_RETURN" "budget.sh formula references per-agent-return constant"
fi

test_summary
