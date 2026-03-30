#!/usr/bin/env bash
# completion.sh — Post-gate finalization for Moira pipelines
# Executes mechanical steps (telemetry, status, quality, metrics, cleanup)
# as a single shell call. Reflection dispatch is handled by the LLM agent.
#
# Source: design/architecture/pipelines.md, orchestrator.md Section 7

set -euo pipefail

_MOIRA_COMPLETION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_COMPLETION_LIB_DIR}/yaml-utils.sh"
# shellcheck source=budget.sh
source "${_MOIRA_COMPLETION_LIB_DIR}/budget.sh"
# shellcheck source=quality.sh
source "${_MOIRA_COMPLETION_LIB_DIR}/quality.sh"
# shellcheck source=knowledge.sh
source "${_MOIRA_COMPLETION_LIB_DIR}/knowledge.sh"
# shellcheck source=metrics.sh
source "${_MOIRA_COMPLETION_LIB_DIR}/metrics.sh"
# shellcheck source=checkpoint.sh
source "${_MOIRA_COMPLETION_LIB_DIR}/checkpoint.sh"

# ── moira_completion_finalize <task_id> <pipeline_type> <completion_action> [state_dir] [config_path] ──
# Execute steps 1-17 of the completion flow (everything except reflection dispatch).
# Outputs: reflection level from pipeline YAML (for the caller to handle step 18).
# Returns 0 on success, 1 on failure.
moira_completion_finalize() {
  local task_id="$1"
  local pipeline_type="$2"
  local completion_action="$3"
  local state_dir="${4:-.claude/moira/state}"
  local config_path="${5:-.claude/moira/config.yaml}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local status_file="${task_dir}/status.yaml"
  local current_file="${state_dir}/current.yaml"
  local violations_log="${state_dir}/violations.log"
  local telemetry_file="${task_dir}/telemetry.yaml"
  local moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"

  # ── Step 1: Completion summary (output to stdout for display) ──
  echo "## Completion Summary"
  echo ""
  echo "Task: ${task_id}"
  echo "Pipeline: ${pipeline_type}"
  echo "Action: ${completion_action}"
  echo ""

  # ── Step 2: Budget report ──
  echo "## Budget Report"
  echo ""
  moira_budget_generate_report "$task_id" "$state_dir" 2>/dev/null || echo "(budget report unavailable)"
  echo ""

  # ── Step 3: Check violations log ──
  local orch_violations=0
  local agent_violations=0
  if [[ -f "$violations_log" ]]; then
    orch_violations=$(grep -c "^VIOLATION " "$violations_log" 2>/dev/null) || orch_violations=0
    agent_violations=$(grep -c "^AGENT_VIOLATION " "$violations_log" 2>/dev/null) || agent_violations=0
  fi
  if [[ "$orch_violations" -gt 0 ]]; then
    echo "⚠ ${orch_violations} orchestrator violations detected"
  fi
  if [[ "$agent_violations" -gt 0 ]]; then
    echo "⚠ ${agent_violations} agent guard violations detected"
  fi
  if [[ "$orch_violations" -eq 0 && "$agent_violations" -eq 0 ]]; then
    echo "Violations: none"
  fi
  echo ""

  # ── Step 4: Write compliance telemetry ──
  moira_yaml_set "$telemetry_file" "compliance.orchestrator_violation_count" "$orch_violations"
  moira_yaml_set "$telemetry_file" "compliance.agent_guard_violation_count" "$agent_violations"

  # ── Step 5: Write structural telemetry ──
  local constitutional_pass="true"
  if [[ "$orch_violations" -gt 0 ]]; then
    constitutional_pass="false"
  fi
  moira_yaml_set "$telemetry_file" "structural.constitutional_pass" "$constitutional_pass"
  # structural.violations — collect VIOLATION-prefixed lines
  if [[ "$orch_violations" -gt 0 && -f "$violations_log" ]]; then
    local violations_list
    violations_list=$(grep "^VIOLATION " "$violations_log" 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
    moira_yaml_set "$telemetry_file" "structural.violations" "[$violations_list]"
  else
    moira_yaml_set "$telemetry_file" "structural.violations" "[]"
  fi

  # ── Step 6: Write version telemetry ──
  local moira_version=""
  if [[ -f "${moira_home}/.version" ]]; then
    moira_version=$(cat "${moira_home}/.version" 2>/dev/null | tr -d '\n') || true
  fi
  moira_yaml_set "$telemetry_file" "moira_version" "${moira_version:-unknown}"

  # ── Step 7: Write budget telemetry ──
  local actual_tokens
  actual_tokens=$(moira_yaml_get "$status_file" "budget.actual_tokens" 2>/dev/null) || actual_tokens=0
  moira_yaml_set "$telemetry_file" "execution.budget_total_tokens" "${actual_tokens:-0}"

  # ── Step 8: Record agent execution data ──
  # Agent data is in current.yaml history[] — extract and write to telemetry
  # This is a complex YAML array operation; write a simplified version
  local agent_count=0
  if [[ -f "$current_file" ]]; then
    agent_count=$(grep -c "^  - step:" "$current_file" 2>/dev/null) || agent_count=0
  fi
  moira_yaml_set "$telemetry_file" "execution.agent_count" "$agent_count"

  # ── Step 9: Write completion fields to status.yaml ──
  # completion.action already written by orchestrator — skip
  local tweak_count redo_count
  tweak_count=$(moira_yaml_get "$status_file" "completion.tweak_count" 2>/dev/null) || tweak_count=0
  redo_count=$(moira_yaml_get "$status_file" "completion.redo_count" 2>/dev/null) || redo_count=0
  moira_yaml_set "$status_file" "completion.tweak_count" "${tweak_count:-0}"
  moira_yaml_set "$status_file" "completion.redo_count" "${redo_count:-0}"
  moira_yaml_set "$status_file" "completion.final_review_passed" "true"
  moira_yaml_set "$status_file" "status" "completed"
  moira_yaml_set "$status_file" "completed_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # ── Step 10: Write quality final result ──
  moira_yaml_set "$telemetry_file" "quality.final_result" "$completion_action"

  # ── Step 11: Aggregate quality data ──
  moira_quality_aggregate_task "$task_dir" 2>/dev/null || true

  # ── Step 12: Tick evolution cooldown ──
  moira_quality_tick_cooldown "$config_path" 2>/dev/null || true

  # ── Step 13: Handle evolve mode ──
  local quality_mode
  quality_mode=$(moira_yaml_get "$config_path" "quality.mode" 2>/dev/null) || quality_mode="conform"
  if [[ "$quality_mode" == "evolve" ]]; then
    moira_quality_complete_evolve "$config_path" 2>/dev/null || true
  fi

  # ── Step 14: Update quality map ──
  local quality_map_dir="${state_dir}/../knowledge/quality-map"
  if [[ -d "$quality_map_dir" ]]; then
    moira_knowledge_update_quality_map "$task_dir" "$quality_map_dir" 2>/dev/null || true
  fi

  # ── Step 15: Handle MCP telemetry ──
  # MCP telemetry is optional (required: false in schema). Write only if data exists.
  # For now, omit — no mechanical way to extract MCP call data from agent dispatches.

  # ── Step 16: Collect metrics ──
  moira_metrics_collect_task "$task_id" "$state_dir" 2>/dev/null || true

  # ── Step 17: Checkpoint cleanup ──
  moira_checkpoint_cleanup "$task_id" "$state_dir" 2>/dev/null || true

  # ── Step 17c: Log rotation ──
  # Rotate logs that grow unbounded. Keep last 500 lines, archive the rest.
  _moira_completion_rotate_log "${state_dir}/violations.log" 500
  _moira_completion_rotate_log "${state_dir}/tool-usage.log" 500
  _moira_completion_rotate_log "${state_dir}/budget-tool-usage.log" 500

  # ── Step 17b: Mark completion processor as completed (D-149 Layer 2) ──
  moira_yaml_set "$status_file" "completion_processor.status" "completed"

  # ── Output reflection level for the caller ──
  local pipeline_yaml="${moira_home}/core/pipelines/${pipeline_type}.yaml"
  local reflection_level="lightweight"
  if [[ -f "$pipeline_yaml" ]]; then
    reflection_level=$(moira_yaml_get "$pipeline_yaml" "post.reflection" 2>/dev/null) || reflection_level="lightweight"
  fi
  # Validate
  case "$reflection_level" in
    lightweight|background|deep|epic) ;;
    *) echo "Warning: invalid reflection level '$reflection_level', defaulting to lightweight" >&2
       reflection_level="lightweight" ;;
  esac

  echo ""
  echo "---"
  echo "REFLECTION_LEVEL=${reflection_level}"

  return 0
}

# ── _moira_completion_rotate_log <log_path> <keep_lines> ─────────────
# Rotate a log file: if it exceeds keep_lines × 2, archive older lines
# to {log_path}.archive and keep only the tail.
_moira_completion_rotate_log() {
  local log_path="$1"
  local keep_lines="$2"

  [[ -f "$log_path" ]] || return 0

  local line_count
  line_count=$(wc -l < "$log_path" 2>/dev/null) || return 0
  line_count=${line_count##* }

  # Only rotate when file exceeds 2× threshold
  local threshold=$(( keep_lines * 2 ))
  if [[ "$line_count" -le "$threshold" ]]; then
    return 0
  fi

  local archive_path="${log_path}.archive"
  local lines_to_archive=$(( line_count - keep_lines ))

  # Discard older lines (no archive — stale data wastes context)
  head -n "$lines_to_archive" "$log_path" > /dev/null 2>/dev/null || true

  # Keep only recent lines
  local tmpfile
  tmpfile=$(mktemp)
  tail -n "$keep_lines" "$log_path" > "$tmpfile" 2>/dev/null && mv "$tmpfile" "$log_path"

  # Remove any pre-existing archive
  rm -f "${log_path}.archive"
}

# ── moira_completion_cleanup <task_id> <state_dir> [pipeline_type] ────
# Delete pipeline artifacts from a completed task directory.
# Preserves status.yaml and telemetry.yaml (permanent records).
# Returns 0 on success (warnings go to stderr).
# Returns 1 only for path traversal violations.
moira_completion_cleanup() {
  local task_id="$1"
  local state_dir="$2"
  local pipeline_type="${3:-}"

  # Path traversal validation
  if [[ "$task_id" == *..* ]] || [[ "$task_id" == */* ]]; then
    echo "ERROR: Invalid task_id: $task_id" >&2
    return 1
  fi

  # Construct and validate task directory
  local task_dir="${state_dir}/tasks/${task_id}"
  if [[ ! -d "$task_dir" ]]; then
    echo "WARN: Task directory not found: $task_dir" >&2
    return 0
  fi

  # Delete allowlisted files (explicit list)
  local -a cleanup_files=(
    classification.md
    exploration.md
    architecture.md
    plan.md
    implementation.md
    review.md
    testing.md
    reflection.md
    requirements.md
    test-results.md
    input.md
    manifest.yaml
  )
  for f in "${cleanup_files[@]}"; do
    rm -f "${task_dir}/${f}"
  done

  # Delete variant files (glob patterns)
  local -a cleanup_globs=(
    "review-tweak-*.md"
    "tweak-*.md"
    "implementation-batch*.md"
    "batch-*-report.md"
    "alternatives.md"
    "context.md"
    "tweak-xref.md"
  )
  for pattern in "${cleanup_globs[@]}"; do
    # shellcheck disable=SC2086
    rm -f ${task_dir}/${pattern} 2>/dev/null
  done

  # Delete allowlisted directories
  local -a cleanup_dirs=(instructions findings phases)
  for d in "${cleanup_dirs[@]}"; do
    if [[ -d "${task_dir}/${d}" ]]; then
      rm -rf "${task_dir}/${d}"
    fi
  done

  # Delete current.yaml (pipeline state no longer needed)
  rm -f "${state_dir}/current.yaml"

  # Epic cleanup (conditional)
  if [[ "$pipeline_type" == "epic" ]]; then
    rm -f "${task_dir}/queue.yaml"
    # Delete subtask directories
    local subtask_dir
    for subtask_dir in "${task_dir}"/subtask-*; do
      if [[ -d "$subtask_dir" ]]; then
        rm -rf "$subtask_dir"
      fi
    done
    # Delete global queue pointer if it matches this epic
    if [[ -f "${state_dir}/queue.yaml" ]]; then
      local queue_epic_id
      queue_epic_id=$(grep -o 'epic_id: *[^ ]*' "${state_dir}/queue.yaml" 2>/dev/null | head -1 | sed 's/epic_id: *//')
      if [[ "$queue_epic_id" == "$task_id" ]]; then
        rm -f "${state_dir}/queue.yaml"
      fi
    fi
  fi

  return 0
}
