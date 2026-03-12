#!/usr/bin/env bash
# state.sh — Higher-level state management for Moira
# Built on yaml-utils.sh. Provides pipeline state operations.
#
# Responsibilities: state transitions and recording ONLY
# Does NOT handle pipeline logic (that's the orchestrator skill)

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_LIB_DIR}/yaml-utils.sh"

# ── moira_state_current [state_dir] ───────────────────────────────────
# Read current pipeline state. Outputs key fields.
# If no active task, outputs "idle".
moira_state_current() {
  local state_dir="${1:-.claude/moira/state}"
  local current_file="${state_dir}/current.yaml"

  if [[ ! -f "$current_file" ]]; then
    echo "idle"
    return 0
  fi

  local task_id
  task_id=$(moira_yaml_get "$current_file" "task_id" 2>/dev/null) || true

  if [[ -z "$task_id" || "$task_id" == "null" ]]; then
    echo "idle"
    return 0
  fi

  local pipeline step step_status
  pipeline=$(moira_yaml_get "$current_file" "pipeline" 2>/dev/null) || true
  step=$(moira_yaml_get "$current_file" "step" 2>/dev/null) || true
  step_status=$(moira_yaml_get "$current_file" "step_status" 2>/dev/null) || true

  echo "task_id: ${task_id}"
  echo "pipeline: ${pipeline}"
  echo "step: ${step}"
  echo "step_status: ${step_status}"
}

# ── moira_state_transition <new_step> <new_status> [state_dir] ────────
# Update pipeline step and status in current.yaml.
# Validates new_step is a known pipeline step.
moira_state_transition() {
  local new_step="$1"
  local new_status="$2"
  local state_dir="${3:-.claude/moira/state}"
  local current_file="${state_dir}/current.yaml"

  if [[ ! -f "$current_file" ]]; then
    echo "Error: no active pipeline (current.yaml not found)" >&2
    return 1
  fi

  # Validate step name
  local valid_steps="classification exploration analysis architecture plan implementation review testing reflection decomposition integration completion"
  local step_valid=false
  for vs in $valid_steps; do
    if [[ "$new_step" == "$vs" ]]; then
      step_valid=true
      break
    fi
  done
  if ! $step_valid; then
    echo "Error: unknown pipeline step '$new_step'" >&2
    return 1
  fi

  # Validate status
  local valid_statuses="pending in_progress awaiting_gate completed failed"
  local status_valid=false
  for vst in $valid_statuses; do
    if [[ "$new_status" == "$vst" ]]; then
      status_valid=true
      break
    fi
  done
  if ! $status_valid; then
    echo "Error: unknown step status '$new_status'" >&2
    return 1
  fi

  moira_yaml_set "$current_file" "step" "$new_step"
  moira_yaml_set "$current_file" "step_status" "$new_status"
  moira_yaml_set "$current_file" "step_started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# ── moira_state_gate <gate_name> <decision> [note] [state_dir] ────────
# Record a gate decision. Appends to status.yaml gates block.
# Sets gate_pending=null in current.yaml.
# Decision must be: proceed, modify, abort
moira_state_gate() {
  local gate_name="$1"
  local decision="$2"
  local note="${3:-}"
  local state_dir="${4:-.claude/moira/state}"
  local current_file="${state_dir}/current.yaml"

  # Validate decision
  case "$decision" in
    proceed|modify|abort) ;;
    *)
      echo "Error: invalid gate decision '$decision' (must be proceed/modify/abort)" >&2
      return 1
      ;;
  esac

  # Get current task ID for status.yaml path
  local task_id
  task_id=$(moira_yaml_get "$current_file" "task_id" 2>/dev/null) || true
  if [[ -z "$task_id" ]]; then
    echo "Error: no active task" >&2
    return 1
  fi

  local status_file="${state_dir}/tasks/${task_id}/status.yaml"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Append gate record to status.yaml
  local gate_entry="  - gate: ${gate_name}
    decision: ${decision}
    at: \"${timestamp}\""
  if [[ -n "$note" ]]; then
    gate_entry="${gate_entry}
    note: \"${note}\""
  fi

  if [[ -f "$status_file" ]]; then
    moira_yaml_block_append "$status_file" "gates" "$gate_entry"
  fi

  # Clear gate_pending in current.yaml
  moira_yaml_set "$current_file" "gate_pending" "null"
}

# ── moira_state_agent_done <step> <status> <duration> <tokens> <summary> [state_dir]
# Record agent execution in current.yaml history block.
# Updates total_agent_tokens in context_budget.
moira_state_agent_done() {
  local step_name="$1"
  local status="$2"
  local duration_sec="$3"
  local tokens_used="$4"
  local result_summary="$5"
  local state_dir="${6:-.claude/moira/state}"
  local current_file="${state_dir}/current.yaml"

  if [[ ! -f "$current_file" ]]; then
    echo "Error: no active pipeline (current.yaml not found)" >&2
    return 1
  fi

  # Append history entry
  local history_entry="  - step: ${step_name}
    status: ${status}
    duration_sec: ${duration_sec}
    agent_tokens_used: ${tokens_used}
    result: \"${result_summary}\""

  moira_yaml_block_append "$current_file" "history" "$history_entry"

  # Update total agent tokens
  local current_tokens
  current_tokens=$(moira_yaml_get "$current_file" "context_budget.total_agent_tokens" 2>/dev/null) || true
  current_tokens=${current_tokens:-0}
  local new_total=$(( current_tokens + tokens_used ))
  moira_yaml_set "$current_file" "context_budget.total_agent_tokens" "$new_total"

  # Budget recording (Phase 7) — additive, guarded for partial installs
  if [[ -f "${_MOIRA_LIB_DIR}/budget.sh" ]]; then
    # shellcheck source=budget.sh
    source "${_MOIRA_LIB_DIR}/budget.sh" 2>/dev/null || true
    local task_id
    task_id=$(moira_yaml_get "$current_file" "task_id" 2>/dev/null) || true
    if [[ -n "$task_id" ]] && type moira_budget_record_agent &>/dev/null; then
      moira_budget_record_agent "$task_id" "$step_name" "$tokens_used" "$tokens_used" "$state_dir" || true
      moira_budget_orchestrator_check "$state_dir" > /dev/null 2>&1 || true
    fi
  fi
}
