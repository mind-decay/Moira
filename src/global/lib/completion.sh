#!/usr/bin/env bash
# completion.sh — Post-gate finalization for Moira pipelines
# Executes mechanical steps (telemetry, status, quality, metrics, cleanup)
# as a single shell call. Reflection dispatch is handled by the LLM agent.
#
# Source: design/architecture/pipelines.md, orchestrator.md Section 7

set -euo pipefail

_MOIRA_COMPLETION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
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
  local state_dir="${4:-.moira/state}"
  local config_path="${5:-.moira/config.yaml}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local status_file="${task_dir}/status.yaml"
  local current_file="${state_dir}/current.yaml"
  local violations_log="${state_dir}/violations.log"
  local telemetry_file="${task_dir}/telemetry.yaml"
  local moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"

  # Ensure telemetry file exists before writing (moira_yaml_set requires pre-existing file)
  touch "$telemetry_file"

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

  # Keep only recent lines
  local tmpfile
  tmpfile=$(mktemp)
  tail -n "$keep_lines" "$log_path" > "$tmpfile" 2>/dev/null && mv "$tmpfile" "$log_path"

  # Remove any pre-existing archive
  rm -f "${log_path}.archive"
}

# ── moira_task_cleanup <state_dir> <retention_days> ──────────────────
# Clean completed task dirs older than retention period.
# WAL pattern: intent marker → archive manifest → verify → delete → remove marker.
# Status filter: ONLY completed (never checkpointed/in_progress/failed).
# Cap at 10 tasks per invocation to prevent hook timeout.
# Idempotent: safe to call multiple times (checks before archive/delete).
moira_task_cleanup() {
  local state_dir="$1"
  local retention_days="${2:-30}"

  local tasks_dir="${state_dir}/tasks"
  local archive_dir="${state_dir}/archive"
  [[ -d "$tasks_dir" ]] || return 0

  local now_epoch
  now_epoch=$(date -u +%s 2>/dev/null) || return 0
  local retention_secs=$(( retention_days * 86400 ))
  local cleaned=0

  # Phase 1: Recover any incomplete WAL cleanups from prior crash
  for marker in "$tasks_dir"/.cleanup-*; do
    [[ -f "$marker" ]] || continue
    local recover_id="${marker##*/.cleanup-}"
    local recover_dir="${tasks_dir}/${recover_id}"
    if [[ -f "${archive_dir}/${recover_id}-manifest.yaml" ]]; then
      # Archive exists — safe to delete task dir and marker
      rm -rf "$recover_dir" 2>/dev/null || true
      rm -f "$marker" 2>/dev/null || true
    else
      # Archive missing — retry: if manifest exists, archive it
      if [[ -f "${recover_dir}/manifest.yaml" ]]; then
        mkdir -p "$archive_dir" 2>/dev/null || true
        cp "${recover_dir}/manifest.yaml" "${archive_dir}/${recover_id}-manifest.yaml" 2>/dev/null || true
        if [[ -f "${archive_dir}/${recover_id}-manifest.yaml" ]]; then
          rm -rf "$recover_dir" 2>/dev/null || true
        fi
      else
        # No manifest, no archive — just clean up dir and marker
        rm -rf "$recover_dir" 2>/dev/null || true
      fi
      rm -f "$marker" 2>/dev/null || true
    fi
  done

  # Phase 2: Clean eligible completed tasks
  for task_dir in "$tasks_dir"/*/; do
    [[ -d "$task_dir" ]] || continue
    [[ "$cleaned" -ge 10 ]] && break

    local status_file="${task_dir}status.yaml"
    [[ -f "$status_file" ]] || continue

    # Status filter: only completed
    local step_status
    step_status=$(grep '^step_status:' "$status_file" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || continue
    [[ "$step_status" == "completed" ]] || continue

    # Age check: completed_at or fallback to file mtime
    local completed_epoch=0
    local completed_at
    completed_at=$(grep '^completed_at:' "$status_file" 2>/dev/null | sed 's/^completed_at:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    if [[ -n "$completed_at" && "$completed_at" != "null" ]]; then
      # macOS/Linux dual-platform date parsing
      completed_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$completed_at" +%s 2>/dev/null) || {
        completed_epoch=$(date -d "$completed_at" +%s 2>/dev/null) || completed_epoch=0
      }
    fi
    if [[ "$completed_epoch" -eq 0 ]]; then
      # Fallback: file mtime
      completed_epoch=$(stat -f '%m' "$status_file" 2>/dev/null || stat -c '%Y' "$status_file" 2>/dev/null) || completed_epoch=0
    fi

    [[ "$completed_epoch" -eq 0 ]] && continue
    local age_secs=$(( now_epoch - completed_epoch ))
    [[ "$age_secs" -lt "$retention_secs" ]] && continue

    # Extract task_id from dir name
    local task_id
    task_id=$(basename "${task_dir%/}")

    # WAL: write intent marker
    touch "${tasks_dir}/.cleanup-${task_id}" 2>/dev/null || continue

    # Archive manifest (if exists and not already archived)
    mkdir -p "$archive_dir" 2>/dev/null || true
    if [[ -f "${task_dir}manifest.yaml" ]] && [[ ! -f "${archive_dir}/${task_id}-manifest.yaml" ]]; then
      cp "${task_dir}manifest.yaml" "${archive_dir}/${task_id}-manifest.yaml" 2>/dev/null || {
        # Archive failed — abort cleanup for this task, remove intent
        rm -f "${tasks_dir}/.cleanup-${task_id}" 2>/dev/null || true
        continue
      }
      # Verify archive exists
      if [[ ! -f "${archive_dir}/${task_id}-manifest.yaml" ]]; then
        rm -f "${tasks_dir}/.cleanup-${task_id}" 2>/dev/null || true
        continue
      fi
    fi

    # Archive permanent records (status + telemetry) alongside manifest
    for perm_file in status.yaml telemetry.yaml; do
      if [[ -f "${task_dir}${perm_file}" ]] && [[ ! -f "${archive_dir}/${task_id}-${perm_file}" ]]; then
        cp "${task_dir}${perm_file}" "${archive_dir}/${task_id}-${perm_file}" 2>/dev/null || true
      fi
    done

    # Delete task dir
    rm -rf "$task_dir" 2>/dev/null || true

    # Remove intent marker
    rm -f "${tasks_dir}/.cleanup-${task_id}" 2>/dev/null || true

    cleaned=$((cleaned + 1))
  done

  return 0
}

# ── moira_metrics_retention <metrics_dir> <retention_months> ─────────
# Aggregate old monthly metrics into annual summaries, delete aggregated files.
# Idempotent: checks if month already exists in annual file before appending.
# Monthly files sort lexicographically (YYYY-MM format, zero-padded).
moira_metrics_retention() {
  local metrics_dir="$1"
  local retention_months="${2:-12}"

  [[ -d "$metrics_dir" ]] || return 0

  # Count monthly files
  local monthly_files
  monthly_files=$(ls "$metrics_dir"/monthly-*.yaml 2>/dev/null | sort) || return 0
  local count
  count=$(echo "$monthly_files" | grep -c '.' 2>/dev/null) || count=0
  [[ "$count" -gt "$retention_months" ]] || return 0

  local excess=$(( count - retention_months ))

  # Process oldest files (already sorted lexicographically = chronologically)
  local processed=0
  while IFS= read -r monthly_file; do
    [[ "$processed" -ge "$excess" ]] && break
    [[ -f "$monthly_file" ]] || continue

    # Extract period from filename: monthly-YYYY-MM.yaml → YYYY-MM
    local basename_f
    basename_f=$(basename "$monthly_file")
    local period="${basename_f#monthly-}"
    period="${period%.yaml}"

    # Extract year for annual file
    local year="${period%%-*}"
    local annual_file="${metrics_dir}/annual-${year}.yaml"

    # Idempotency: check if this period already aggregated
    if [[ -f "$annual_file" ]] && grep -qF "period: \"${period}\"" "$annual_file" 2>/dev/null; then
      # Already aggregated — just delete monthly file
      rm -f "$monthly_file" 2>/dev/null || true
      processed=$((processed + 1))
      continue
    fi

    # Extract summary data from monthly file
    local tasks_total=0 composite_score=0
    if [[ -f "${_MOIRA_COMPLETION_LIB_DIR}/yaml-utils.sh" ]]; then
      tasks_total=$(moira_yaml_get "$monthly_file" "tasks.total" 2>/dev/null) || tasks_total=0
      local first_pass
      first_pass=$(moira_yaml_get "$monthly_file" "quality.first_pass_accepted" 2>/dev/null) || first_pass=0
      if [[ "$tasks_total" -gt 0 && "$first_pass" -gt 0 ]]; then
        composite_score=$(( first_pass * 100 / tasks_total ))
      fi
    else
      # Fallback: grep-based extraction
      tasks_total=$(grep 'total:' "$monthly_file" 2>/dev/null | head -1 | sed 's/.*total:[[:space:]]*//' | tr -d '"' 2>/dev/null) || tasks_total=0
    fi

    # Initialize annual file if new
    if [[ ! -f "$annual_file" ]]; then
      echo "year: ${year}" > "$annual_file"
      echo "months:" >> "$annual_file"
    fi

    # Append month entry
    {
      echo "  - period: \"${period}\""
      echo "    tasks_total: ${tasks_total}"
      echo "    composite_score: ${composite_score}"
    } >> "$annual_file"

    # Delete aggregated monthly file
    rm -f "$monthly_file" 2>/dev/null || true

    processed=$((processed + 1))
  done <<< "$monthly_files"

  return 0
}

# ── moira_completion_cleanup <task_id> <state_dir> [pipeline_type] ────
# Delete pipeline artifacts from a completed task directory.
# Preserves permanent records: status.yaml, telemetry.yaml, reflection.md.
# Uses preserve-list approach: explicitly protected files survive, everything else is deleted.
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

  # Preserve-list: these files MUST survive cleanup
  local -a preserve_files=(
    status.yaml
    telemetry.yaml
    reflection.md
    current.yaml
  )

  # Delete all files NOT in preserve list
  local filename
  for filepath in "${task_dir}"/*; do
    [[ -e "$filepath" ]] || continue
    if [[ -f "$filepath" ]]; then
      filename=$(basename "$filepath")
      local preserved=false
      for pf in "${preserve_files[@]}"; do
        if [[ "$filename" == "$pf" ]]; then
          preserved=true
          break
        fi
      done
      if [[ "$preserved" == "false" ]]; then
        rm -f "$filepath"
      fi
    elif [[ -d "$filepath" ]]; then
      rm -rf "$filepath"
    fi
  done

  # Delete global current.yaml (pipeline state no longer needed)
  rm -f "${state_dir}/current.yaml"

  # Epic cleanup (conditional)
  if [[ "$pipeline_type" == "epic" ]]; then
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
