#!/usr/bin/env bash
# budget.sh — Context budget management for Moira
# Estimation, tracking, reporting, and overflow handling.
#
# Responsibilities: budget logic ONLY
# Does NOT handle state transitions (that's state.sh)
# Does NOT read project files (Art 1.1) — only .claude/moira/ state/config

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_BUDGET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_BUDGET_LIB_DIR}/yaml-utils.sh"

# ── Default budget values (fallback when config unavailable) ──────────
# These match config.schema.yaml defaults
_MOIRA_BUDGET_DEFAULTS_classifier=20000
_MOIRA_BUDGET_DEFAULTS_explorer=140000
_MOIRA_BUDGET_DEFAULTS_analyst=80000
_MOIRA_BUDGET_DEFAULTS_architect=100000
_MOIRA_BUDGET_DEFAULTS_planner=70000
_MOIRA_BUDGET_DEFAULTS_implementer=120000
_MOIRA_BUDGET_DEFAULTS_reviewer=100000
_MOIRA_BUDGET_DEFAULTS_tester=90000
_MOIRA_BUDGET_DEFAULTS_reflector=80000
_MOIRA_BUDGET_DEFAULTS_auditor=140000

_MOIRA_BUDGET_DEFAULT_MAX_LOAD=70
_MOIRA_BUDGET_ORCHESTRATOR_CAPACITY=1000000

# Orchestrator estimation constants (D-058)
_MOIRA_BUDGET_ORCH_BASE_OVERHEAD=15000
_MOIRA_BUDGET_ORCH_PER_STEP=500
_MOIRA_BUDGET_ORCH_PER_GATE=2000

# ── _moira_budget_get_agent_budget <role> [config_path] ───────────────
# Look up agent budget: budgets.yaml → config.yaml → role definition YAML → hardcoded defaults
_moira_budget_get_agent_budget() {
  local role="$1"
  local config_path="${2:-}"
  local budget=""

  # Try budgets.yaml first
  if [[ -n "$config_path" && -f "$config_path/budgets.yaml" ]]; then
    budget=$(moira_yaml_get "$config_path/budgets.yaml" "agent_budgets.${role}" 2>/dev/null) || true
  fi

  # Try config.yaml fallback
  if [[ -z "$budget" && -n "$config_path" && -f "$config_path/config.yaml" ]]; then
    budget=$(moira_yaml_get "$config_path/config.yaml" "budgets.per_agent.${role}" 2>/dev/null) || true
  fi

  # Try role definition YAML fallback
  if [[ -z "$budget" ]]; then
    local role_file="${HOME}/.claude/moira/core/rules/roles/${role}.yaml"
    if [[ -f "$role_file" ]]; then
      budget=$(moira_yaml_get "$role_file" "budget" 2>/dev/null) || true
    fi
  fi

  # Hardcoded defaults fallback
  if [[ -z "$budget" ]]; then
    local var_name="_MOIRA_BUDGET_DEFAULTS_${role}"
    budget="${!var_name:-0}"
  fi

  echo "$budget"
}

# ── _moira_budget_get_max_load [config_path] ──────────────────────────
# Look up max_load_percent from config chain
_moira_budget_get_max_load() {
  local config_path="${1:-}"
  local max_load=""

  if [[ -n "$config_path" && -f "$config_path/budgets.yaml" ]]; then
    max_load=$(moira_yaml_get "$config_path/budgets.yaml" "max_load_percent" 2>/dev/null) || true
  fi

  if [[ -z "$max_load" && -n "$config_path" && -f "$config_path/config.yaml" ]]; then
    max_load=$(moira_yaml_get "$config_path/config.yaml" "budgets.agent_max_load_percent" 2>/dev/null) || true
  fi

  echo "${max_load:-$_MOIRA_BUDGET_DEFAULT_MAX_LOAD}"
}

# ── moira_budget_estimate_tokens <file_path> ──────────────────────────
# Estimate token count for a file using file_size / 4 ratio (D-056).
# Returns estimated token count. 0 if file doesn't exist.
moira_budget_estimate_tokens() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    echo "Warning: file not found for budget estimation: $file_path" >&2
    echo 0
    return 0
  fi

  local file_size
  file_size=$(wc -c < "$file_path" 2>/dev/null | tr -d ' ')
  echo $(( file_size / 4 ))
}

# ── moira_budget_estimate_batch <file_list> ───────────────────────────
# Estimate total tokens for a newline-separated list of files.
moira_budget_estimate_batch() {
  local file_list="$1"
  local total=0

  if [[ -z "$file_list" ]]; then
    echo 0
    return 0
  fi

  while IFS= read -r file_path; do
    [[ -z "$file_path" ]] && continue
    local tokens
    tokens=$(moira_budget_estimate_tokens "$file_path")
    total=$(( total + tokens ))
  done <<< "$file_list"

  echo "$total"
}

# ── moira_budget_estimate_agent <role> <file_list> <knowledge_tokens> <instruction_tokens> [mcp_tokens] ──
# Estimate total context usage for an agent invocation.
# Outputs structured key-value pairs.
moira_budget_estimate_agent() {
  local agent_role="$1"
  local file_list="$2"
  local knowledge_tokens="$3"
  local instruction_tokens="$4"
  local mcp_tokens="${5:-0}"

  local working_data
  working_data=$(moira_budget_estimate_batch "$file_list")

  local total=$(( working_data + knowledge_tokens + instruction_tokens + mcp_tokens ))

  # Look up agent budget from config
  local config_path=""
  if [[ -d ".claude/moira/config" ]]; then
    config_path=".claude/moira/config"
  fi
  local agent_budget
  agent_budget=$(_moira_budget_get_agent_budget "$agent_role" "$config_path")

  local percentage=0
  if [[ "$agent_budget" -gt 0 ]]; then
    percentage=$(( total * 100 / agent_budget ))
  fi

  # Determine status
  local status="ok"
  local max_load
  max_load=$(_moira_budget_get_max_load "$config_path")
  if [[ "$percentage" -gt "$max_load" ]]; then
    status="exceeded"
  # Fixed warning threshold at 50% of agent budget (distinct from configurable max_load)
  elif [[ "$percentage" -ge 50 ]]; then
    status="warning"
  fi

  echo "working_data: ${working_data}"
  echo "knowledge: ${knowledge_tokens}"
  echo "instructions: ${instruction_tokens}"
  echo "mcp: ${mcp_tokens}"
  echo "total: ${total}"
  echo "budget: ${agent_budget}"
  echo "percentage: ${percentage}"
  echo "status: ${status}"
}

# ── moira_budget_check_overflow <role> <estimated_tokens> [config_path] ──
# Check if estimated tokens exceed agent budget.
# Echoes "exceeded"/"warning"/"ok". Returns 1 on exceeded.
moira_budget_check_overflow() {
  local agent_role="$1"
  local estimated_tokens="$2"
  local config_path="${3:-}"

  local agent_budget
  agent_budget=$(_moira_budget_get_agent_budget "$agent_role" "$config_path")

  local max_load
  max_load=$(_moira_budget_get_max_load "$config_path")

  local max_allowed=$(( agent_budget * max_load / 100 ))
  local warn_threshold=$(( agent_budget * 50 / 100 ))

  if [[ "$estimated_tokens" -gt "$max_allowed" ]]; then
    echo "exceeded"
    return 1
  elif [[ "$estimated_tokens" -gt "$warn_threshold" ]]; then
    echo "warning"
    return 0
  else
    echo "ok"
    return 0
  fi
}

# ── moira_budget_record_agent <task_id> <role> <estimated> <actual> [state_dir] ──
# Record budget data after agent completion. Updates status.yaml.
moira_budget_record_agent() {
  local task_id="$1"
  local agent_role="$2"
  local estimated_tokens="$3"
  local actual_tokens="$4"
  local state_dir="${5:-.claude/moira/state}"

  local status_file="${state_dir}/tasks/${task_id}/status.yaml"
  if [[ ! -f "$status_file" ]]; then
    echo "Warning: status file not found: $status_file" >&2
    return 0
  fi

  # Look up agent budget
  local config_path=""
  local config_dir
  config_dir="$(dirname "$state_dir")/config"
  if [[ -d "$config_dir" ]]; then
    config_path="$config_dir"
  fi
  local agent_budget
  agent_budget=$(_moira_budget_get_agent_budget "$agent_role" "$config_path")

  local percentage=0
  if [[ "$agent_budget" -gt 0 ]]; then
    percentage=$(( actual_tokens * 100 / agent_budget ))
  fi

  # Append to budget.by_agent block
  local budget_entry="  - role: ${agent_role}
    estimated: ${estimated_tokens}
    actual: ${actual_tokens}
    budget: ${agent_budget}
    percentage: ${percentage}"

  moira_yaml_block_append "$status_file" "budget.by_agent" "$budget_entry"

  # Update cumulative fields
  local current_estimated
  current_estimated=$(moira_yaml_get "$status_file" "budget.estimated_tokens" 2>/dev/null) || true
  current_estimated=${current_estimated:-0}

  local current_actual
  current_actual=$(moira_yaml_get "$status_file" "budget.actual_tokens" 2>/dev/null) || true
  current_actual=${current_actual:-0}

  moira_yaml_set "$status_file" "budget.estimated_tokens" "$(( current_estimated + estimated_tokens ))"
  moira_yaml_set "$status_file" "budget.actual_tokens" "$(( current_actual + actual_tokens ))"
}

# ── moira_budget_orchestrator_check [state_dir] ──────────────────────
# Check orchestrator context health using proxy estimation (D-058).
# Updates current.yaml and outputs key-value pairs.
moira_budget_orchestrator_check() {
  local state_dir="${1:-.claude/moira/state}"
  local current_file="${state_dir}/current.yaml"

  if [[ ! -f "$current_file" ]]; then
    echo "estimated_tokens: 0"
    echo "percentage: 0"
    echo "level: normal"
    return 0
  fi

  # Read agent tokens added to orchestrator context
  local agent_tokens
  agent_tokens=$(moira_yaml_get "$current_file" "context_budget.total_agent_tokens" 2>/dev/null) || true
  agent_tokens=${agent_tokens:-0}

  # Count history entries (steps completed)
  local history_count=0
  if grep -q "^history:" "$current_file" 2>/dev/null; then
    history_count=$(grep -c "^  - step:" "$current_file" 2>/dev/null) || true
  fi

  # Count gate interactions from status.yaml gate entries
  local gate_count=0
  local task_id
  task_id=$(moira_yaml_get "$current_file" "task_id" 2>/dev/null) || true
  if [[ -n "$task_id" && -f "${state_dir}/tasks/${task_id}/status.yaml" ]]; then
    gate_count=$(grep -c "^  - gate:" "${state_dir}/tasks/${task_id}/status.yaml" 2>/dev/null) || true
  fi

  # Calculate estimated orchestrator tokens
  # Agent return summaries accumulate in orchestrator context — include them
  local estimated_tokens=$(( _MOIRA_BUDGET_ORCH_BASE_OVERHEAD + (history_count * _MOIRA_BUDGET_ORCH_PER_STEP) + (gate_count * _MOIRA_BUDGET_ORCH_PER_GATE) + agent_tokens ))

  local percentage=$(( estimated_tokens * 100 / _MOIRA_BUDGET_ORCHESTRATOR_CAPACITY ))

  # Determine level (from context-budget.md / self-monitoring.md)
  # Values must match current.schema.yaml warning_level enum: [normal, monitor, warning, critical]
  local level="normal"
  if [[ "$percentage" -gt 60 ]]; then
    level="critical"
  elif [[ "$percentage" -gt 40 ]]; then
    level="warning"
  elif [[ "$percentage" -gt 25 ]]; then
    level="monitor"
  fi

  # Update current.yaml
  moira_yaml_set "$current_file" "context_budget.orchestrator_tokens_used" "$estimated_tokens"
  moira_yaml_set "$current_file" "context_budget.orchestrator_percent" "$percentage"
  moira_yaml_set "$current_file" "context_budget.warning_level" "$level"

  echo "estimated_tokens: ${estimated_tokens}"
  echo "percentage: ${percentage}"
  echo "level: ${level}"
}

# ── moira_budget_generate_report <task_id> [state_dir] ────────────────
# Generate the full budget report table for pipeline completion.
# Returns formatted report string matching gates.md template.
moira_budget_generate_report() {
  local task_id="$1"
  local state_dir="${2:-.claude/moira/state}"

  local status_file="${state_dir}/tasks/${task_id}/status.yaml"
  local current_file="${state_dir}/current.yaml"

  # Read orchestrator data
  local orch_tokens orch_pct
  orch_tokens=$(moira_yaml_get "$current_file" "context_budget.orchestrator_tokens_used" 2>/dev/null) || true
  orch_tokens=${orch_tokens:-0}
  orch_pct=$(moira_yaml_get "$current_file" "context_budget.orchestrator_percent" 2>/dev/null) || true
  orch_pct=${orch_pct:-0}

  local orch_emoji="✅"
  if [[ "$orch_pct" -gt 60 ]]; then
    orch_emoji="🔴"
  elif [[ "$orch_pct" -gt 40 ]]; then
    orch_emoji="⚠"
  fi

  local orch_k=$(( (orch_tokens + 500) / 1000 ))

  # Build report header
  local report=""
  report+="╔══════════════════════════════════════════════╗"$'\n'
  report+="║           CONTEXT BUDGET REPORT              ║"$'\n'
  report+="╠══════════════════════════════════════════════╣"$'\n'
  report+="║ Agent         │ Budget │ Est.  │ % │ Status  ║"$'\n'
  report+="║───────────────┼────────┼───────┼───┼─────────║"$'\n'

  # Parse per-agent entries from status.yaml
  if [[ -f "$status_file" ]]; then
    local in_budget=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^budget: ]]; then
        in_budget=true
        continue
      fi
      if $in_budget && [[ "$line" =~ ^[a-z] ]]; then
        in_budget=false
        continue
      fi
      if $in_budget && [[ "$line" =~ "- role:" ]]; then
        local role="${line#*role: }"
        role="${role## }"
        local est act bgt pct
        IFS= read -r line
        est="${line#*estimated: }"
        est="${est## }"
        IFS= read -r line
        act="${line#*actual: }"
        act="${act## }"
        IFS= read -r line
        bgt="${line#*budget: }"
        bgt="${bgt## }"
        IFS= read -r line
        pct="${line#*percentage: }"
        pct="${pct## }"

        local emoji="✅"
        if [[ "${pct:-0}" -gt 70 ]]; then
          emoji="🔴"
        elif [[ "${pct:-0}" -ge 50 ]]; then
          emoji="⚠"
        fi

        local bgt_k=$(( (${bgt:-0} + 500) / 1000 ))
        local est_k=$(( (${act:-0} + 500) / 1000 ))

        # Pad fields for alignment
        printf -v agent_line "║ %-13s │ %4sk  │ %3sk  │%2s%%│ %s       ║" \
          "$role" "$bgt_k" "$est_k" "${pct:-0}" "$emoji"
        report+="${agent_line}"$'\n'
      fi
    done < "$status_file"
  fi

  # Orchestrator line
  printf -v orch_line "║ Orchestrator  │ 1000k  │ %3sk  │%2s%%│ %s       ║" \
    "$orch_k" "$orch_pct" "$orch_emoji"
  report+="${orch_line}"$'\n'

  report+="╠══════════════════════════════════════════════╣"$'\n'
  printf -v summary_line "║ Orchestrator context: %sk/1000k (%s%%)%*s║" \
    "$orch_k" "$orch_pct" "$(( 21 - ${#orch_k} - ${#orch_pct} ))" ""
  report+="${summary_line}"$'\n'
  report+="╚══════════════════════════════════════════════╝"

  echo "$report"
}

# ═══════════════════════════════════════════════════════════════════════
# Adaptive Budget Margins
# Per-agent adaptive safety margins computed from telemetry history.
# Replaces fixed 30% margin with data-driven margins (20%-50% range).
# ═══════════════════════════════════════════════════════════════════════

# ── moira_budget_adaptive_margin <agent_type> [state_dir]
# Compute adaptive safety margin for an agent type.
# Returns margin as integer percentage (20-50).
# Cold start: <5 obs → 30%, 5-20 obs → max(20, μ+3σ), 20+ → max(20, min(50, μ+2σ))
moira_budget_adaptive_margin() {
  local agent_type="$1"
  local state_dir="${2:-.claude/moira/state}"

  local stats_file="${state_dir}/budget-accuracy.yaml"

  # If no history file, return default
  if [[ ! -f "$stats_file" ]]; then
    echo "30"
    return 0
  fi

  # Read observation count
  local n_obs
  n_obs=$(moira_yaml_get "$stats_file" "agents.${agent_type}.n_observations" 2>/dev/null) || n_obs=""
  n_obs=${n_obs:-0}

  # Cold start: <5 observations → fixed 30%
  if [[ $n_obs -lt 5 ]]; then
    echo "30"
    return 0
  fi

  # Read mean error and stddev (stored as percentages × 100 for integer math)
  local mu sigma
  mu=$(moira_yaml_get "$stats_file" "agents.${agent_type}.mean_error" 2>/dev/null) || mu="3000"
  sigma=$(moira_yaml_get "$stats_file" "agents.${agent_type}.stddev_error" 2>/dev/null) || sigma="500"
  mu=${mu:-3000}
  sigma=${sigma:-500}

  local margin
  if [[ $n_obs -lt 20 ]]; then
    # 5-20 observations: wider confidence (μ + 3σ)
    margin=$(( (mu + 3 * sigma) / 100 ))
  else
    # 20+ observations: standard formula (μ + 2σ)
    margin=$(( (mu + 2 * sigma) / 100 ))
  fi

  # Apply bounds: floor 20%, ceiling 50%
  if [[ $margin -lt 20 ]]; then
    margin=20
  elif [[ $margin -gt 50 ]]; then
    margin=50
  fi

  echo "$margin"
}

# ── moira_budget_estimation_error <task_id> <agent_type> <estimated_pct> <actual_pct> [state_dir]
# Record estimation accuracy for one agent invocation.
# Updates running mean and stddev in budget-accuracy.yaml.
moira_budget_estimation_error() {
  local task_id="$1"
  local agent_type="$2"
  local estimated_pct="$3"
  local actual_pct="$4"
  local state_dir="${5:-.claude/moira/state}"

  local stats_file="${state_dir}/budget-accuracy.yaml"
  mkdir -p "$(dirname "$stats_file")"

  # Compute error ratio as percentage × 100
  # error = (actual - estimated) / estimated × 10000
  local error=0
  if [[ $estimated_pct -gt 0 ]]; then
    error=$(( (actual_pct - estimated_pct) * 10000 / estimated_pct ))
  fi

  # Read current stats
  local n_obs current_mean current_var
  n_obs=$(moira_yaml_get "$stats_file" "agents.${agent_type}.n_observations" 2>/dev/null) || n_obs=""
  current_mean=$(moira_yaml_get "$stats_file" "agents.${agent_type}.mean_error" 2>/dev/null) || current_mean=""
  current_var=$(moira_yaml_get "$stats_file" "agents.${agent_type}.stddev_error" 2>/dev/null) || current_var=""

  if [[ -z "$n_obs" || "$n_obs" == "null" ]]; then
    # First observation
    moira_yaml_set "$stats_file" "agents.${agent_type}.n_observations" "1"
    moira_yaml_set "$stats_file" "agents.${agent_type}.mean_error" "$error"
    moira_yaml_set "$stats_file" "agents.${agent_type}.stddev_error" "0"
  else
    # Incremental update (Welford's algorithm, integer version)
    local n=$((n_obs + 1))
    local diff=$(( error - current_mean ))
    local new_mean=$(( current_mean + diff / n ))
    # Variance update: new_var = ((n-1) * old_var² + diff * (error - new_mean)) / n
    # We store stddev but compute with variance internally
    local old_var_sq=$(( current_var * current_var ))
    local new_var_sq=$(( ((n - 1) * old_var_sq + diff * (error - new_mean)) / n ))
    if [[ $new_var_sq -lt 0 ]]; then new_var_sq=0; fi
    # Integer square root approximation
    local new_stddev=0
    if [[ $new_var_sq -gt 0 ]]; then
      # Newton's method for isqrt
      new_stddev=$new_var_sq
      local prev=0
      while [[ $new_stddev -ne $prev ]]; do
        prev=$new_stddev
        new_stddev=$(( (new_stddev + new_var_sq / new_stddev) / 2 ))
      done
    fi

    moira_yaml_set "$stats_file" "agents.${agent_type}.n_observations" "$n"
    moira_yaml_set "$stats_file" "agents.${agent_type}.mean_error" "$new_mean"
    moira_yaml_set "$stats_file" "agents.${agent_type}.stddev_error" "$new_stddev"
  fi
}

# ── moira_budget_write_telemetry <task_id> [state_dir] ────────────────
# Write budget data to telemetry.yaml for the task.
moira_budget_write_telemetry() {
  local task_id="$1"
  local state_dir="${2:-.claude/moira/state}"

  local status_file="${state_dir}/tasks/${task_id}/status.yaml"
  local telemetry_file="${state_dir}/tasks/${task_id}/telemetry.yaml"

  if [[ ! -f "$status_file" ]]; then
    return 0
  fi

  # Read total budget tokens
  local total_tokens
  total_tokens=$(moira_yaml_get "$status_file" "budget.actual_tokens" 2>/dev/null) || true
  total_tokens=${total_tokens:-0}

  # Write to telemetry if file exists
  if [[ -f "$telemetry_file" ]]; then
    moira_yaml_set "$telemetry_file" "execution.budget_total_tokens" "$total_tokens"
  fi
}

# ── moira_budget_handle_overflow <task_id> <role> <completed> <remaining> [state_dir] ──
# Handle budget_exceeded agent response. Returns continuation or escalation data.
# Returns 1 on escalation (double overflow).
moira_budget_handle_overflow() {
  local task_id="$1"
  local agent_role="$2"
  local completed="$3"
  local remaining="$4"
  local state_dir="${5:-.claude/moira/state}"

  local status_file="${state_dir}/tasks/${task_id}/status.yaml"

  # Check current budget_splits count
  local splits=0
  if [[ -f "$status_file" ]]; then
    splits=$(moira_yaml_get "$status_file" "retries.budget_splits" 2>/dev/null) || true
    splits=${splits:-0}
  fi

  # Increment splits
  local new_splits=$(( splits + 1 ))
  if [[ -f "$status_file" ]]; then
    moira_yaml_set "$status_file" "retries.budget_splits" "$new_splits"
  fi

  # Double overflow → escalate
  if [[ "$new_splits" -ge 2 ]]; then
    echo "action: escalate"
    echo "agent: ${agent_role}"
    echo "completed: ${completed}"
    echo "remaining: ${remaining}"
    echo "splits: ${new_splits}"
    return 1
  fi

  # First overflow → spawn continuation
  echo "action: spawn_continuation"
  echo "agent: ${agent_role}"
  echo "completed: ${completed}"
  echo "remaining: ${remaining}"
  echo "partial_result_path: state/tasks/${task_id}/"
  echo "splits: ${new_splits}"
  return 0
}
