#!/usr/bin/env bash
# retry.sh — Markov-based retry optimization for Moira (D8)
# Consults lookup table + telemetry history to recommend retry vs escalation.
# Uses EMA-smoothed success probabilities per (error_type, agent_type) pair.
# Integer arithmetic only (percentages as whole numbers 0-100).
# Compatible with bash 3.2+ (no associative arrays).
#
# Responsibilities: retry decision-making ONLY
# Does NOT handle state transitions (that's state.sh)
# Does NOT handle actual retries (that's the orchestrator skill)

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_RETRY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_RETRY_LIB_DIR}/yaml-utils.sh"

# ── Default lookup table ─────────────────────────────────────────────
# Format: error_type:agent_type:max_retries:p1:p2
# p1 = probability of success on attempt 1 retry (percent)
# p2 = probability of success on attempt 2 retry (percent), 0 if max_retries=1
# Hard limits from fault-tolerance.md are upper bounds.
_MOIRA_RETRY_DEFAULTS="E5_QUALITY:implementer:2:70:30
E5_QUALITY:architect:1:50:0
E6_AGENT:any:1:60:0
E9_SEMANTIC:implementer:2:50:30"

# ── EMA smoothing factor (alpha) ─────────────────────────────────────
# α = 0.8, represented as integer percentage for integer arithmetic
_MOIRA_RETRY_EMA_ALPHA=80

# ── Hard limits from fault-tolerance.md ──────────────────────────────
# These are absolute upper bounds. The optimizer can recommend fewer
# retries, never more.
_MOIRA_RETRY_HARD_LIMIT_E5=2
_MOIRA_RETRY_HARD_LIMIT_E6=1

# ── Cost model constants ─────────────────────────────────────────────
# Abstract cost units for expected cost comparison.
# Ratio matters more than absolute values: escalation = 2× retry cost.
_MOIRA_RETRY_COST_RETRY=100       # cost of one agent re-dispatch
_MOIRA_RETRY_COST_ESCALATE=200    # cost of user interruption + context switch

# ── Private: get default entry ────────────────────────────────────────
# Returns: max_retries:p1:p2 for the given error_type and agent_type
# Falls back to "any" agent_type if specific not found.
_moira_retry_get_default() {
  local error_type="$1"
  local agent_type="$2"

  local line=""
  local any_line=""
  local IFS_OLD="$IFS"

  # Search for exact match first, then "any" match
  IFS=$'\n'
  for entry in $_MOIRA_RETRY_DEFAULTS; do
    local e_type e_agent
    e_type=$(echo "$entry" | cut -d: -f1)
    e_agent=$(echo "$entry" | cut -d: -f2)
    if [[ "$e_type" == "$error_type" && "$e_agent" == "$agent_type" ]]; then
      line="$entry"
      break
    fi
    if [[ "$e_type" == "$error_type" && "$e_agent" == "any" ]]; then
      any_line="$entry"
    fi
  done
  IFS="$IFS_OLD"

  if [[ -n "$line" ]]; then
    echo "$line" | cut -d: -f3-5
  elif [[ -n "$any_line" ]]; then
    echo "$any_line" | cut -d: -f3-5
  else
    # Unknown error_type: conservative default — 1 retry, 40% probability
    echo "1:40:0"
  fi
}

# ── Private: get hard limit for error type ────────────────────────────
_moira_retry_hard_limit() {
  local error_type="$1"
  case "$error_type" in
    E5_QUALITY|E9_SEMANTIC) echo "$_MOIRA_RETRY_HARD_LIMIT_E5" ;;
    E6_AGENT)               echo "$_MOIRA_RETRY_HARD_LIMIT_E6" ;;
    *)                      echo "1" ;;
  esac
}

# ── Private: read telemetry probability ───────────────────────────────
# Reads EMA-smoothed probability from retry-stats.yaml.
# Returns empty string if no telemetry data exists.
_moira_retry_read_telemetry() {
  local error_type="$1"
  local agent_type="$2"
  local state_dir="$3"
  local stats_file="${state_dir}/retry-stats.yaml"

  if [[ ! -f "$stats_file" ]]; then
    echo ""
    return 0
  fi

  local key="${error_type}.${agent_type}"
  local prob
  prob=$(moira_yaml_get "$stats_file" "${key}.probability" 2>/dev/null) || true

  echo "${prob:-}"
}

# ── Private: read telemetry observation count ─────────────────────────
_moira_retry_read_count() {
  local error_type="$1"
  local agent_type="$2"
  local state_dir="$3"
  local stats_file="${state_dir}/retry-stats.yaml"

  if [[ ! -f "$stats_file" ]]; then
    echo "0"
    return 0
  fi

  local key="${error_type}.${agent_type}"
  local count
  count=$(moira_yaml_get "$stats_file" "${key}.observations" 2>/dev/null) || true

  echo "${count:-0}"
}

# ── Private: get effective probability for an attempt ─────────────────
# Uses telemetry if available, otherwise falls back to defaults.
# attempt_number is 1-based (1 = first retry, 2 = second retry).
_moira_retry_effective_probability() {
  local error_type="$1"
  local agent_type="$2"
  local attempt_number="$3"
  local state_dir="$4"

  # Get defaults
  local defaults
  defaults=$(_moira_retry_get_default "$error_type" "$agent_type")
  local default_p1 default_p2
  default_p1=$(echo "$defaults" | cut -d: -f2)
  default_p2=$(echo "$defaults" | cut -d: -f3)

  # Check telemetry
  local telem_prob
  telem_prob=$(_moira_retry_read_telemetry "$error_type" "$agent_type" "$state_dir")

  if [[ -n "$telem_prob" && "$telem_prob" != "0" ]]; then
    # Use telemetry probability — it's the EMA-smoothed value
    # For attempt 2, decay by 50% (second retry is less likely to succeed)
    if [[ "$attempt_number" -eq 1 ]]; then
      echo "$telem_prob"
    else
      echo $(( telem_prob / 2 ))
    fi
  else
    # Use defaults
    if [[ "$attempt_number" -eq 1 ]]; then
      echo "$default_p1"
    else
      echo "$default_p2"
    fi
  fi
}

# ── moira_retry_should_retry <error_type> <agent_type> [state_dir] ───
# Consult lookup table + telemetry history to recommend retry vs escalation.
# Output format (one field per line):
#   decision: yes|no
#   probability: N%
#   reason: text
moira_retry_should_retry() {
  local error_type="$1"
  local agent_type="$2"
  local state_dir="${3:-.claude/moira/state}"

  # Get hard limit
  local hard_limit
  hard_limit=$(_moira_retry_hard_limit "$error_type")

  if [[ "$hard_limit" -eq 0 ]]; then
    echo "decision: no"
    echo "probability: 0%"
    echo "reason: error type $error_type has no retry allowed"
    return 0
  fi

  # Get effective probability for attempt 1
  local prob
  prob=$(_moira_retry_effective_probability "$error_type" "$agent_type" 1 "$state_dir")

  # Get observation count for context
  local obs_count
  obs_count=$(_moira_retry_read_count "$error_type" "$agent_type" "$state_dir")

  # Decision threshold: retry if probability >= 30%
  local threshold=30
  local source_note=""
  if [[ "$obs_count" -gt 0 ]]; then
    source_note="based on $obs_count historical observations"
  else
    source_note="based on default estimates"
  fi

  if [[ "$prob" -ge "$threshold" ]]; then
    echo "decision: yes"
    echo "probability: ${prob}%"
    echo "reason: retry recommended (estimated ${prob}% success probability $source_note)"
  else
    echo "decision: no"
    echo "probability: ${prob}%"
    echo "reason: escalating to user (estimated ${prob}% success probability — retry unlikely to help, $source_note)"
  fi
}

# ── moira_retry_expected_cost <error_type> <agent_type> <attempt_number> [state_dir]
# Compute expected cost of retrying vs escalating.
# Uses formula: E[cost|N] = sum(c_retry * prod(1-pj)) + c_escalate * prod(1-pj)
# Cost units are abstract (1 = one agent dispatch).
# Output: retry_cost: N, escalate_cost: N, recommendation: retry|escalate
moira_retry_expected_cost() {
  local error_type="$1"
  local agent_type="$2"
  local attempt_number="$3"
  local state_dir="${4:-.claude/moira/state}"

  # Get max retries and hard limit
  local defaults
  defaults=$(_moira_retry_get_default "$error_type" "$agent_type")
  local max_retries
  max_retries=$(echo "$defaults" | cut -d: -f1)

  local hard_limit
  hard_limit=$(_moira_retry_hard_limit "$error_type")
  if [[ "$max_retries" -gt "$hard_limit" ]]; then
    max_retries="$hard_limit"
  fi

  # If we've exceeded max retries, always escalate
  if [[ "$attempt_number" -gt "$max_retries" ]]; then
    echo "retry_cost: 0"
    echo "escalate_cost: 0"
    echo "recommendation: escalate"
    return 0
  fi

  local c_retry=$_MOIRA_RETRY_COST_RETRY
  local c_escalate=$_MOIRA_RETRY_COST_ESCALATE

  # Calculate expected cost of retrying from current attempt onward
  # E[cost] = c_retry + (1-p_current) * [c_retry + (1-p_next) * c_escalate]
  # All probabilities in percentages (0-100), scale factor 100

  local p_current
  p_current=$(_moira_retry_effective_probability "$error_type" "$agent_type" "$attempt_number" "$state_dir")

  # Expected cost if we retry now
  # Success case: c_retry (with probability p_current/100)
  # Failure case: c_retry + further costs (with probability (100-p_current)/100)
  local retry_expected=0
  local fail_prob=$(( 100 - p_current ))

  if [[ "$attempt_number" -lt "$max_retries" ]]; then
    # More retries available after this one
    local p_next
    p_next=$(_moira_retry_effective_probability "$error_type" "$agent_type" $(( attempt_number + 1 )) "$state_dir")
    local fail_next=$(( 100 - p_next ))
    # E = c_retry + (fail_prob/100) * (c_retry + (fail_next/100) * c_escalate)
    # Using integer math scaled by 10000:
    local inner=$(( c_retry + (fail_next * c_escalate) / 100 ))
    retry_expected=$(( c_retry + (fail_prob * inner) / 100 ))
  else
    # This is the last retry
    # E = c_retry + (fail_prob/100) * c_escalate
    retry_expected=$(( c_retry + (fail_prob * c_escalate) / 100 ))
  fi

  # Expected cost if we escalate now
  local escalate_expected=$c_escalate

  # Recommendation
  local recommendation="retry"
  if [[ "$escalate_expected" -lt "$retry_expected" ]]; then
    recommendation="escalate"
  fi

  echo "retry_cost: $retry_expected"
  echo "escalate_cost: $escalate_expected"
  echo "recommendation: $recommendation"
}

# ── moira_retry_record_outcome <error_type> <agent_type> <attempt_number> <success|failure> [state_dir]
# Update EMA-smoothed success probability in retry-stats.yaml.
# EMA formula: new_p = alpha * outcome + (1 - alpha) * old_p
# alpha = 0.8 (heavily weight recent outcomes)
# outcome: success=100, failure=0
moira_retry_record_outcome() {
  local error_type="$1"
  local agent_type="$2"
  local attempt_number="$3"
  local outcome="$4"
  local state_dir="${5:-.claude/moira/state}"
  local stats_file="${state_dir}/retry-stats.yaml"

  # Ensure state directory and stats file exist
  mkdir -p "$state_dir"
  if [[ ! -f "$stats_file" ]]; then
    echo "# Moira retry statistics — EMA-smoothed success probabilities" > "$stats_file"
    echo "# Updated automatically by retry optimizer" >> "$stats_file"
  fi

  local key="${error_type}.${agent_type}"
  local outcome_value=0
  if [[ "$outcome" == "success" ]]; then
    outcome_value=100
  fi

  # Read current probability and observation count
  local old_prob
  old_prob=$(moira_yaml_get "$stats_file" "${key}.probability" 2>/dev/null) || true
  old_prob=${old_prob:-50}

  local old_count
  old_count=$(moira_yaml_get "$stats_file" "${key}.observations" 2>/dev/null) || true
  old_count=${old_count:-0}

  # EMA: new_p = alpha * outcome + (1 - alpha) * old_p
  # alpha = 80 (representing 0.8), all values in percentages
  local alpha=$_MOIRA_RETRY_EMA_ALPHA
  local new_prob=$(( (alpha * outcome_value + (100 - alpha) * old_prob) / 100 ))
  local new_count=$(( old_count + 1 ))

  # Clamp to 0-100
  if [[ "$new_prob" -lt 0 ]]; then new_prob=0; fi
  if [[ "$new_prob" -gt 100 ]]; then new_prob=100; fi

  # Write updated values
  moira_yaml_set "$stats_file" "${key}.probability" "$new_prob"
  moira_yaml_set "$stats_file" "${key}.observations" "$new_count"
  moira_yaml_set "$stats_file" "${key}.last_attempt" "$attempt_number"
  moira_yaml_set "$stats_file" "${key}.last_outcome" "$outcome"
  moira_yaml_set "$stats_file" "${key}.updated_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# ── moira_retry_lookup_table [state_dir] ──────────────────────────────
# Return current lookup table: defaults merged with telemetry-learned values.
# Output format (one entry per line):
#   error_type:agent_type:max_retries:p1:p2:source
# source = "default" or "telemetry"
moira_retry_lookup_table() {
  local state_dir="${1:-.claude/moira/state}"
  local stats_file="${state_dir}/retry-stats.yaml"

  local IFS_OLD="$IFS"
  IFS=$'\n'
  for entry in $_MOIRA_RETRY_DEFAULTS; do
    local e_type e_agent max_r p1 p2
    e_type=$(echo "$entry" | cut -d: -f1)
    e_agent=$(echo "$entry" | cut -d: -f2)
    max_r=$(echo "$entry" | cut -d: -f3)
    p1=$(echo "$entry" | cut -d: -f4)
    p2=$(echo "$entry" | cut -d: -f5)

    # Check hard limits
    local hard_limit
    hard_limit=$(_moira_retry_hard_limit "$e_type")
    if [[ "$max_r" -gt "$hard_limit" ]]; then
      max_r="$hard_limit"
    fi

    # Check for telemetry override
    local telem_prob=""
    if [[ -f "$stats_file" ]]; then
      local key="${e_type}.${e_agent}"
      telem_prob=$(moira_yaml_get "$stats_file" "${key}.probability" 2>/dev/null) || true
    fi

    if [[ -n "$telem_prob" && "$telem_prob" != "0" ]]; then
      local telem_p2=$(( telem_prob / 2 ))
      if [[ "$max_r" -le 1 ]]; then telem_p2=0; fi
      echo "${e_type}:${e_agent}:${max_r}:${telem_prob}:${telem_p2}:telemetry"
    else
      echo "${e_type}:${e_agent}:${max_r}:${p1}:${p2}:default"
    fi
  done
  IFS="$IFS_OLD"
}
