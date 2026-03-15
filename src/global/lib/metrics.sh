#!/usr/bin/env bash
# metrics.sh — Metrics collection, aggregation, and dashboard for Moira
# Collects per-task data from telemetry.yaml + status.yaml, aggregates monthly,
# generates dashboard, drill-down, comparison, and export views.
#
# Source: design/subsystems/metrics.md, design/specs/2026-03-15-phase11-metrics-audit.md D1

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_METRICS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_METRICS_LIB_DIR}/yaml-utils.sh"

# Trend threshold: minimum absolute difference to register as up/down (D-093a)
_MOIRA_METRICS_TREND_THRESHOLD=5

# ── moira_metrics_collect_task <task_id> [state_dir] ──────────────────
# Extract metrics from a completed task's telemetry.yaml and status.yaml.
# Appends per-task record to current month's aggregate file.
# Called at pipeline completion (after telemetry write, before reflection).
moira_metrics_collect_task() {
  local task_id="$1"
  local state_dir="${2:-.claude/moira/state}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local telemetry_file="${task_dir}/telemetry.yaml"
  local status_file="${task_dir}/status.yaml"

  if [[ ! -f "$status_file" ]]; then
    echo "Warning: status file not found: $status_file" >&2
    return 0
  fi

  # Read fields from status.yaml
  local size pipeline
  size=$(moira_yaml_get "$status_file" "size" 2>/dev/null) || true
  size=${size:-medium}
  pipeline=$(moira_yaml_get "$status_file" "pipeline" 2>/dev/null) || true
  pipeline=${pipeline:-standard}

  local completion_action tweak_count redo_count
  completion_action=$(moira_yaml_get "$status_file" "completion.action" 2>/dev/null) || true
  completion_action=${completion_action:-done}
  tweak_count=$(moira_yaml_get "$status_file" "completion.tweak_count" 2>/dev/null) || true
  tweak_count=${tweak_count:-0}
  redo_count=$(moira_yaml_get "$status_file" "completion.redo_count" 2>/dev/null) || true
  redo_count=${redo_count:-0}

  local overridden
  overridden=$(moira_yaml_get "$status_file" "classification.overridden" 2>/dev/null) || true
  overridden=${overridden:-false}

  local retries_total
  retries_total=$(moira_yaml_get "$status_file" "retries.total" 2>/dev/null) || true
  retries_total=${retries_total:-0}

  local actual_tokens
  actual_tokens=$(moira_yaml_get "$status_file" "budget.actual_tokens" 2>/dev/null) || true
  actual_tokens=${actual_tokens:-0}

  # Read fields from telemetry.yaml (if exists)
  local first_pass_accepted="false"
  local reviewer_criticals=0
  local orchestrator_pct=0

  if [[ -f "$telemetry_file" ]]; then
    local fp
    fp=$(moira_yaml_get "$telemetry_file" "quality.first_pass_accepted" 2>/dev/null) || true
    first_pass_accepted=${fp:-false}

    local rc
    rc=$(moira_yaml_get "$telemetry_file" "quality.reviewer_findings.critical" 2>/dev/null) || true
    reviewer_criticals=${rc:-0}

    # Classification correctness from telemetry
    local classification_correct
    classification_correct=$(moira_yaml_get "$telemetry_file" "pipeline.classification_correct" 2>/dev/null) || true
  fi

  # Determine monthly file
  local month
  month=$(date +%Y-%m)
  local metrics_dir="${state_dir}/metrics"
  mkdir -p "$metrics_dir"
  local monthly_file="${metrics_dir}/monthly-${month}.yaml"

  # Initialize monthly file if it doesn't exist
  if [[ ! -f "$monthly_file" ]]; then
    _moira_metrics_init_monthly "$monthly_file" "$month"
  fi

  # Append task record
  local tweaked="false"
  local redone="false"
  [[ "$tweak_count" -gt 0 ]] && tweaked="true"
  [[ "$redo_count" -gt 0 ]] && redone="true"

  local task_record="  - task_id: ${task_id}
    pipeline: ${pipeline}
    size: ${size}
    first_pass: ${first_pass_accepted}
    tweaked: ${tweaked}
    redone: ${redone}
    retries: ${retries_total}
    orchestrator_pct: ${orchestrator_pct}
    reviewer_criticals: ${reviewer_criticals}"

  moira_yaml_block_append "$monthly_file" "task_records" "$task_record"

  # Update running totals
  _moira_metrics_increment "$monthly_file" "tasks.total" 1

  # Increment by_size
  local current_by_size
  current_by_size=$(moira_yaml_get "$monthly_file" "tasks.by_size.${size}" 2>/dev/null) || true
  current_by_size=${current_by_size:-0}
  moira_yaml_set "$monthly_file" "tasks.by_size.${size}" "$(( current_by_size + 1 ))"

  # Check if bypassed or aborted
  if [[ "$completion_action" == "abort" ]]; then
    _moira_metrics_increment "$monthly_file" "tasks.aborted" 1
  fi

  # Quality metrics
  if [[ "$first_pass_accepted" == "true" ]]; then
    _moira_metrics_increment "$monthly_file" "quality.first_pass_accepted" 1
  fi
  if [[ "$tweak_count" -gt 0 ]]; then
    _moira_metrics_increment "$monthly_file" "quality.tweaks" 1
  fi
  if [[ "$redo_count" -gt 0 ]]; then
    _moira_metrics_increment "$monthly_file" "quality.redos" 1
  fi
  _moira_metrics_increment "$monthly_file" "quality.retry_loops_total" "$retries_total"
  _moira_metrics_increment "$monthly_file" "quality.reviewer_criticals" "$reviewer_criticals"

  # Accuracy: classification correctness
  if [[ "$overridden" == "false" ]]; then
    _moira_metrics_increment "$monthly_file" "accuracy.classification_correct" 1
  fi

  # Call audit trigger check (cross-lib sourcing with existence guard)
  if [[ -f "${_MOIRA_METRICS_LIB_DIR}/audit.sh" ]]; then
    # shellcheck source=audit.sh
    source "${_MOIRA_METRICS_LIB_DIR}/audit.sh"
    moira_audit_check_trigger "$state_dir" || true
  fi

  echo "metrics_collected: ${task_id}"
}

# ── moira_metrics_aggregate_monthly [state_dir] ──────────────────────
# Full recalculation of monthly aggregate from task_records.
# Used for consistency check or monthly rollover.
moira_metrics_aggregate_monthly() {
  local state_dir="${1:-.claude/moira/state}"

  local month
  month=$(date +%Y-%m)
  local monthly_file="${state_dir}/metrics/monthly-${month}.yaml"

  if [[ ! -f "$monthly_file" ]]; then
    echo "No monthly file for ${month}"
    return 0
  fi

  # Reset counters
  moira_yaml_set "$monthly_file" "tasks.total" "0"
  moira_yaml_set "$monthly_file" "tasks.by_size.small" "0"
  moira_yaml_set "$monthly_file" "tasks.by_size.medium" "0"
  moira_yaml_set "$monthly_file" "tasks.by_size.large" "0"
  moira_yaml_set "$monthly_file" "tasks.by_size.epic" "0"
  moira_yaml_set "$monthly_file" "tasks.bypassed" "0"
  moira_yaml_set "$monthly_file" "tasks.aborted" "0"
  moira_yaml_set "$monthly_file" "quality.first_pass_accepted" "0"
  moira_yaml_set "$monthly_file" "quality.tweaks" "0"
  moira_yaml_set "$monthly_file" "quality.redos" "0"
  moira_yaml_set "$monthly_file" "quality.retry_loops_total" "0"
  moira_yaml_set "$monthly_file" "quality.reviewer_criticals" "0"
  moira_yaml_set "$monthly_file" "accuracy.classification_correct" "0"

  # Count records from task_records
  local total=0 small=0 medium=0 large=0 epic=0
  local fp=0 tweaks=0 redos=0 retries=0 criticals=0
  local orch_sum=0

  local in_records=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^task_records: ]]; then
      in_records=true
      continue
    fi
    # End of records: next top-level key
    if $in_records && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    if $in_records; then
      if [[ "$line" =~ "- task_id:" ]]; then
        total=$(( total + 1 ))
      elif [[ "$line" =~ "size: small" ]]; then
        small=$(( small + 1 ))
      elif [[ "$line" =~ "size: medium" ]]; then
        medium=$(( medium + 1 ))
      elif [[ "$line" =~ "size: large" ]]; then
        large=$(( large + 1 ))
      elif [[ "$line" =~ "size: epic" ]]; then
        epic=$(( epic + 1 ))
      elif [[ "$line" =~ "first_pass: true" ]]; then
        fp=$(( fp + 1 ))
      elif [[ "$line" =~ "tweaked: true" ]]; then
        tweaks=$(( tweaks + 1 ))
      elif [[ "$line" =~ "redone: true" ]]; then
        redos=$(( redos + 1 ))
      elif [[ "$line" =~ "retries:" ]]; then
        local val="${line#*retries: }"
        val="${val## }"
        retries=$(( retries + val ))
      elif [[ "$line" =~ "reviewer_criticals:" ]]; then
        local val="${line#*reviewer_criticals: }"
        val="${val## }"
        criticals=$(( criticals + val ))
      elif [[ "$line" =~ "orchestrator_pct:" ]]; then
        local val="${line#*orchestrator_pct: }"
        val="${val## }"
        orch_sum=$(( orch_sum + val ))
      fi
    fi
  done < "$monthly_file"

  # Write aggregated values
  moira_yaml_set "$monthly_file" "tasks.total" "$total"
  moira_yaml_set "$monthly_file" "tasks.by_size.small" "$small"
  moira_yaml_set "$monthly_file" "tasks.by_size.medium" "$medium"
  moira_yaml_set "$monthly_file" "tasks.by_size.large" "$large"
  moira_yaml_set "$monthly_file" "tasks.by_size.epic" "$epic"
  moira_yaml_set "$monthly_file" "quality.first_pass_accepted" "$fp"
  moira_yaml_set "$monthly_file" "quality.tweaks" "$tweaks"
  moira_yaml_set "$monthly_file" "quality.redos" "$redos"
  moira_yaml_set "$monthly_file" "quality.retry_loops_total" "$retries"
  moira_yaml_set "$monthly_file" "quality.reviewer_criticals" "$criticals"

  # Compute averages
  if [[ "$total" -gt 0 ]]; then
    moira_yaml_set "$monthly_file" "efficiency.avg_orchestrator_context_pct" "$(( orch_sum / total ))"
  fi

  echo "aggregated: ${total} tasks for ${month}"
}

# ── moira_metrics_dashboard [state_dir] ───────────────────────────────
# Generate the main dashboard display (last 30 days).
# Reads current and previous month aggregates.
moira_metrics_dashboard() {
  local state_dir="${1:-.claude/moira/state}"
  local metrics_dir="${state_dir}/metrics"

  local current_month
  current_month=$(date +%Y-%m)
  local current_file="${metrics_dir}/monthly-${current_month}.yaml"

  if [[ ! -f "$current_file" ]]; then
    echo "No metrics data yet. Complete tasks via /moira to start collecting metrics."
    return 0
  fi

  # Read current period values
  local total fp tweaks redos retries criticals
  total=$(_moira_metrics_read "$current_file" "tasks.total" 0)
  fp=$(_moira_metrics_read "$current_file" "quality.first_pass_accepted" 0)
  tweaks=$(_moira_metrics_read "$current_file" "quality.tweaks" 0)
  redos=$(_moira_metrics_read "$current_file" "quality.redos" 0)
  retries=$(_moira_metrics_read "$current_file" "quality.retry_loops_total" 0)
  criticals=$(_moira_metrics_read "$current_file" "quality.reviewer_criticals" 0)

  local class_correct arch_first plan_first
  class_correct=$(_moira_metrics_read "$current_file" "accuracy.classification_correct" 0)
  arch_first=$(_moira_metrics_read "$current_file" "accuracy.architecture_first_try" 0)
  plan_first=$(_moira_metrics_read "$current_file" "accuracy.plan_first_try" 0)

  local orch_pct impl_pct checkpoints mcp_calls mcp_useful mcp_cache
  orch_pct=$(_moira_metrics_read "$current_file" "efficiency.avg_orchestrator_context_pct" 0)
  impl_pct=$(_moira_metrics_read "$current_file" "efficiency.avg_implementer_context_pct" 0)
  checkpoints=$(_moira_metrics_read "$current_file" "efficiency.checkpoints_needed" 0)
  mcp_calls=$(_moira_metrics_read "$current_file" "efficiency.mcp_calls" 0)
  mcp_useful=$(_moira_metrics_read "$current_file" "efficiency.mcp_useful" 0)
  mcp_cache=$(_moira_metrics_read "$current_file" "efficiency.mcp_cache_hits" 0)

  local pat_total pat_added dec_total dec_added qm_cov fresh stale
  pat_total=$(_moira_metrics_read "$current_file" "knowledge.patterns_total" 0)
  pat_added=$(_moira_metrics_read "$current_file" "knowledge.patterns_added" 0)
  dec_total=$(_moira_metrics_read "$current_file" "knowledge.decisions_total" 0)
  dec_added=$(_moira_metrics_read "$current_file" "knowledge.decisions_added" 0)
  qm_cov=$(_moira_metrics_read "$current_file" "knowledge.quality_map_coverage_pct" 0)
  fresh=$(_moira_metrics_read "$current_file" "knowledge.freshness_pct" 0)
  stale=$(_moira_metrics_read "$current_file" "knowledge.stale_entries" 0)

  local evo_proposed evo_applied evo_deferred evo_rejected evo_regress
  evo_proposed=$(_moira_metrics_read "$current_file" "evolution.improvements_proposed" 0)
  evo_applied=$(_moira_metrics_read "$current_file" "evolution.applied" 0)
  evo_deferred=$(_moira_metrics_read "$current_file" "evolution.deferred" 0)
  evo_rejected=$(_moira_metrics_read "$current_file" "evolution.rejected" 0)
  evo_regress=$(_moira_metrics_read "$current_file" "evolution.regressions" 0)

  local small medium large epic bypassed aborted
  small=$(_moira_metrics_read "$current_file" "tasks.by_size.small" 0)
  medium=$(_moira_metrics_read "$current_file" "tasks.by_size.medium" 0)
  large=$(_moira_metrics_read "$current_file" "tasks.by_size.large" 0)
  epic=$(_moira_metrics_read "$current_file" "tasks.by_size.epic" 0)
  bypassed=$(_moira_metrics_read "$current_file" "tasks.bypassed" 0)
  aborted=$(_moira_metrics_read "$current_file" "tasks.aborted" 0)

  # Calculate percentages
  local fp_pct=0 tweak_pct=0 redo_pct=0 class_pct=0
  if [[ "$total" -gt 0 ]]; then
    fp_pct=$(( fp * 100 / total ))
    tweak_pct=$(( tweaks * 100 / total ))
    redo_pct=$(( redos * 100 / total ))
    class_pct=$(( class_correct * 100 / total ))
  fi

  # Read previous month for trends
  local prev_month
  prev_month=$(_moira_metrics_prev_month "$current_month")
  local prev_file="${metrics_dir}/monthly-${prev_month}.yaml"

  local prev_total=0 prev_fp_pct=0
  if [[ -f "$prev_file" ]]; then
    prev_total=$(_moira_metrics_read "$prev_file" "tasks.total" 0)
    local prev_fp
    prev_fp=$(_moira_metrics_read "$prev_file" "quality.first_pass_accepted" 0)
    if [[ "$prev_total" -gt 0 ]]; then
      prev_fp_pct=$(( prev_fp * 100 / prev_total ))
    fi
  fi

  # Trend indicators
  local fp_trend
  fp_trend=$(_moira_metrics_trend "$fp_pct" "$prev_fp_pct")

  # Output dashboard
  echo "╔══════════════════════════════════════════════════╗"
  echo "║         MOIRA PERFORMANCE DASHBOARD              ║"
  echo "║         Period: ${current_month}                           ║"
  echo "╠══════════════════════════════════════════════════╣"
  echo "║"
  echo "║  TASKS"
  echo "║  Total: ${total}  (S:${small} M:${medium} L:${large} E:${epic})"
  echo "║  Bypassed: ${bypassed}  Aborted: ${aborted}"
  echo "║"
  echo "║  QUALITY                              ${fp_trend}"
  echo "║  First-pass accepted: ${fp}/${total} (${fp_pct}%)"
  echo "║  Tweaks: ${tweaks} (${tweak_pct}%)  Redos: ${redos} (${redo_pct}%)"
  echo "║  Retry loops: ${retries}  Reviewer criticals: ${criticals}"
  echo "║"
  echo "║  ACCURACY"
  echo "║  Classification correct: ${class_correct}/${total} (${class_pct}%)"
  echo "║  Architecture first-try: ${arch_first}  Plan first-try: ${plan_first}"
  echo "║"
  echo "║  EFFICIENCY"
  echo "║  Avg orchestrator context: ${orch_pct}%  Avg implementer: ${impl_pct}%"
  echo "║  Checkpoints: ${checkpoints}  MCP calls: ${mcp_calls} (useful: ${mcp_useful}, cached: ${mcp_cache})"
  echo "║"
  echo "║  KNOWLEDGE"
  echo "║  Patterns: ${pat_total} (+${pat_added})  Decisions: ${dec_total} (+${dec_added})"
  echo "║  Quality map coverage: ${qm_cov}%  Freshness: ${fresh}%  Stale: ${stale}"
  echo "║"
  echo "║  EVOLUTION"
  echo "║  Proposed: ${evo_proposed}  Applied: ${evo_applied}  Deferred: ${evo_deferred}  Rejected: ${evo_rejected}"
  echo "║  Regressions: ${evo_regress}"
  echo "║"
  echo "╚══════════════════════════════════════════════════╝"
}

# ── moira_metrics_drilldown <section> [state_dir] ─────────────────────
# Generate drill-down view for a specific section.
# Valid sections: tasks, quality, accuracy, efficiency, knowledge, evolution
moira_metrics_drilldown() {
  local section="$1"
  local state_dir="${2:-.claude/moira/state}"

  local current_month
  current_month=$(date +%Y-%m)
  local monthly_file="${state_dir}/metrics/monthly-${current_month}.yaml"

  if [[ ! -f "$monthly_file" ]]; then
    echo "No metrics data yet."
    return 0
  fi

  local valid_sections="tasks quality accuracy efficiency knowledge evolution"
  if [[ ! " $valid_sections " =~ " $section " ]]; then
    echo "Invalid section: ${section}"
    echo "Valid sections: ${valid_sections}"
    return 1
  fi

  echo "═══ ${section^^} DRILL-DOWN (${current_month}) ═══"
  echo ""

  # Parse task_records for drill-down
  local in_records=false
  local record_lines=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^task_records: ]]; then
      in_records=true
      continue
    fi
    if $in_records && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    if $in_records; then
      record_lines+="${line}"$'\n'
    fi
  done < "$monthly_file"

  if [[ -z "$record_lines" ]]; then
    echo "No per-task records available."
    return 0
  fi

  # Output per-task details based on section
  local task_id="" pipeline="" size="" first_pass="" tweaked="" redone="" retries="" orch_pct="" criticals=""

  while IFS= read -r line; do
    if [[ "$line" =~ "- task_id:" ]]; then
      # Print previous record if exists
      if [[ -n "$task_id" ]]; then
        _moira_metrics_print_drilldown_record "$section" "$task_id" "$pipeline" "$size" "$first_pass" "$tweaked" "$redone" "$retries" "$orch_pct" "$criticals"
      fi
      task_id="${line#*task_id: }"
      task_id="${task_id## }"
    elif [[ "$line" =~ "pipeline:" ]]; then
      pipeline="${line#*pipeline: }"; pipeline="${pipeline## }"
    elif [[ "$line" =~ "size:" ]]; then
      size="${line#*size: }"; size="${size## }"
    elif [[ "$line" =~ "first_pass:" ]]; then
      first_pass="${line#*first_pass: }"; first_pass="${first_pass## }"
    elif [[ "$line" =~ "tweaked:" ]]; then
      tweaked="${line#*tweaked: }"; tweaked="${tweaked## }"
    elif [[ "$line" =~ "redone:" ]]; then
      redone="${line#*redone: }"; redone="${redone## }"
    elif [[ "$line" =~ "retries:" ]]; then
      retries="${line#*retries: }"; retries="${retries## }"
    elif [[ "$line" =~ "orchestrator_pct:" ]]; then
      orch_pct="${line#*orchestrator_pct: }"; orch_pct="${orch_pct## }"
    elif [[ "$line" =~ "reviewer_criticals:" ]]; then
      criticals="${line#*reviewer_criticals: }"; criticals="${criticals## }"
    fi
  done <<< "$record_lines"

  # Print last record
  if [[ -n "$task_id" ]]; then
    _moira_metrics_print_drilldown_record "$section" "$task_id" "$pipeline" "$size" "$first_pass" "$tweaked" "$redone" "$retries" "$orch_pct" "$criticals"
  fi
}

# ── moira_metrics_compare [state_dir] ─────────────────────────────────
# Generate side-by-side comparison with previous period.
moira_metrics_compare() {
  local state_dir="${1:-.claude/moira/state}"
  local metrics_dir="${state_dir}/metrics"

  local current_month
  current_month=$(date +%Y-%m)
  local prev_month
  prev_month=$(_moira_metrics_prev_month "$current_month")

  local current_file="${metrics_dir}/monthly-${current_month}.yaml"
  local prev_file="${metrics_dir}/monthly-${prev_month}.yaml"

  if [[ ! -f "$current_file" ]]; then
    echo "No metrics data for current period."
    return 0
  fi

  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║              PERIOD COMPARISON                             ║"
  echo "║              ${prev_month} vs ${current_month}                          ║"
  echo "╠════════════════════════════════════════════════════════════╣"
  printf "║ %-30s │ %8s │ %8s │ %6s ║\n" "Metric" "${prev_month}" "${current_month}" "Delta"
  echo "║──────────────────────────────┼──────────┼──────────┼────────║"

  local prev_val cur_val delta

  # Tasks
  cur_val=$(_moira_metrics_read "$current_file" "tasks.total" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "tasks.total" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "Tasks completed" "$prev_val" "$cur_val" "$delta"

  # Quality: first-pass rate
  cur_val=$(_moira_metrics_read "$current_file" "quality.first_pass_accepted" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "quality.first_pass_accepted" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "First-pass accepted" "$prev_val" "$cur_val" "$delta"

  # Quality: tweaks
  cur_val=$(_moira_metrics_read "$current_file" "quality.tweaks" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "quality.tweaks" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "Tweaks" "$prev_val" "$cur_val" "$delta"

  # Quality: redos
  cur_val=$(_moira_metrics_read "$current_file" "quality.redos" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "quality.redos" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "Redos" "$prev_val" "$cur_val" "$delta"

  # Accuracy
  cur_val=$(_moira_metrics_read "$current_file" "accuracy.classification_correct" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "accuracy.classification_correct" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "Classification correct" "$prev_val" "$cur_val" "$delta"

  # Efficiency
  cur_val=$(_moira_metrics_read "$current_file" "efficiency.avg_orchestrator_context_pct" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "efficiency.avg_orchestrator_context_pct" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %7s%% │ %7s%% │ %+5d%% ║\n" "Avg orchestrator context" "$prev_val" "$cur_val" "$delta"

  # Knowledge
  cur_val=$(_moira_metrics_read "$current_file" "knowledge.patterns_total" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "knowledge.patterns_total" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "Patterns total" "$prev_val" "$cur_val" "$delta"

  # Evolution
  cur_val=$(_moira_metrics_read "$current_file" "evolution.applied" 0)
  prev_val=$(_moira_metrics_read_safe "$prev_file" "evolution.applied" 0)
  delta=$(( cur_val - prev_val ))
  printf "║ %-30s │ %8s │ %8s │ %+6d ║\n" "Evolution applied" "$prev_val" "$cur_val" "$delta"

  echo "╚════════════════════════════════════════════════════════════╝"
}

# ── moira_metrics_export [state_dir] ──────────────────────────────────
# Generate markdown export of full dashboard + drill-down.
moira_metrics_export() {
  local state_dir="${1:-.claude/moira/state}"

  local current_month
  current_month=$(date +%Y-%m)
  local export_date
  export_date=$(date +%Y-%m-%d)

  echo "# Moira Metrics Report"
  echo ""
  echo "**Generated:** ${export_date}"
  echo "**Period:** ${current_month}"
  echo ""
  echo "---"
  echo ""
  echo '```'
  moira_metrics_dashboard "$state_dir"
  echo '```'
  echo ""
  echo "## Drill-Down Details"
  echo ""

  local section
  for section in tasks quality accuracy efficiency knowledge evolution; do
    echo "### ${section^}"
    echo ""
    echo '```'
    moira_metrics_drilldown "$section" "$state_dir"
    echo '```'
    echo ""
  done

  echo "## Period Comparison"
  echo ""
  echo '```'
  moira_metrics_compare "$state_dir"
  echo '```'
}

# ── Helper functions ──────────────────────────────────────────────────

_moira_metrics_init_monthly() {
  local file="$1"
  local month="$2"

  cat > "$file" << EOF
period: "${month}"
tasks:
  total: 0
  by_size:
    small: 0
    medium: 0
    large: 0
    epic: 0
  bypassed: 0
  aborted: 0
quality:
  first_pass_accepted: 0
  tweaks: 0
  redos: 0
  retry_loops_total: 0
  reviewer_criticals: 0
accuracy:
  classification_correct: 0
  architecture_first_try: 0
  plan_first_try: 0
efficiency:
  avg_orchestrator_context_pct: 0
  avg_implementer_context_pct: 0
  checkpoints_needed: 0
  mcp_calls: 0
  mcp_useful: 0
  mcp_cache_hits: 0
knowledge:
  patterns_total: 0
  patterns_added: 0
  decisions_total: 0
  decisions_added: 0
  quality_map_coverage_pct: 0
  freshness_pct: 0
  stale_entries: 0
evolution:
  improvements_proposed: 0
  applied: 0
  deferred: 0
  rejected: 0
  regressions: 0
task_records:
EOF
}

_moira_metrics_increment() {
  local file="$1"
  local key="$2"
  local amount="$3"

  local current
  current=$(moira_yaml_get "$file" "$key" 2>/dev/null) || true
  current=${current:-0}
  moira_yaml_set "$file" "$key" "$(( current + amount ))"
}

_moira_metrics_read() {
  local file="$1"
  local key="$2"
  local default="$3"

  local val
  val=$(moira_yaml_get "$file" "$key" 2>/dev/null) || true
  echo "${val:-$default}"
}

_moira_metrics_read_safe() {
  local file="$1"
  local key="$2"
  local default="$3"

  if [[ ! -f "$file" ]]; then
    echo "$default"
    return 0
  fi
  _moira_metrics_read "$file" "$key" "$default"
}

_moira_metrics_prev_month() {
  local current="$1"
  local year="${current%%-*}"
  local month="${current##*-}"

  # Remove leading zero for arithmetic
  month=$(( 10#$month ))

  if [[ "$month" -eq 1 ]]; then
    printf "%d-%02d" "$(( year - 1 ))" "12"
  else
    printf "%d-%02d" "$year" "$(( month - 1 ))"
  fi
}

_moira_metrics_trend() {
  local current="$1"
  local previous="$2"

  local diff=$(( current - previous ))
  if [[ "$diff" -ge "$_MOIRA_METRICS_TREND_THRESHOLD" ]]; then
    echo "↑"
  elif [[ "$diff" -le "-${_MOIRA_METRICS_TREND_THRESHOLD}" ]]; then
    echo "↓"
  else
    echo "→"
  fi
}

_moira_metrics_print_drilldown_record() {
  local section="$1"
  local task_id="$2" pipeline="$3" size="$4" first_pass="$5"
  local tweaked="$6" redone="$7" retries="$8" orch_pct="$9" criticals="${10}"

  case "$section" in
    tasks)
      echo "  ${task_id}: ${size} (${pipeline})"
      ;;
    quality)
      local status="accepted"
      [[ "$tweaked" == "true" ]] && status="tweaked"
      [[ "$redone" == "true" ]] && status="redone"
      echo "  ${task_id}: ${status} | retries: ${retries} | criticals: ${criticals}"
      ;;
    accuracy)
      echo "  ${task_id}: pipeline=${pipeline} size=${size} first_pass=${first_pass}"
      ;;
    efficiency)
      echo "  ${task_id}: orchestrator=${orch_pct}%"
      ;;
    knowledge)
      echo "  ${task_id}: (knowledge data collected at aggregate level)"
      ;;
    evolution)
      echo "  ${task_id}: (evolution data collected at aggregate level)"
      ;;
  esac
}
