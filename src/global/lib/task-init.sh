#!/usr/bin/env bash
# task-init.sh — Task scaffold for Moira
# Creates task directory, initializes state files, sets up session lock.
# Called by task-submit.sh hook (UserPromptSubmit) before orchestrator starts.
#
# Responsibilities: task scaffold + initial state ONLY
# Does NOT handle pipeline logic (that's the orchestrator skill)

set -euo pipefail

_MOIRA_TASK_INIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_TASK_INIT_LIB_DIR}/yaml-utils.sh"
# shellcheck source=task-id.sh
source "${_MOIRA_TASK_INIT_LIB_DIR}/task-id.sh"

# ── moira_task_init <description> [size_hint] [state_dir] ────────────
# Create a new task: generate ID, scaffold directory, write initial state.
# Outputs task_id to stdout.
# size_hint: "small", "medium", "large", "epic", or "" (classifier decides)
# state_dir: defaults to .claude/moira/state
moira_task_init() {
  local description="$1"
  local size_hint="${2:-}"
  local state_dir="${3:-.claude/moira/state}"

  # Generate task ID
  local task_id
  task_id=$(moira_task_id "$state_dir")

  local task_dir="${state_dir}/tasks/${task_id}"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Truncate description for status.yaml (max 100 chars)
  local short_desc="${description:0:100}"

  # Create task directory
  mkdir -p "$task_dir"

  # ── Write manifest.yaml ──
  cat > "$task_dir/manifest.yaml" << EOF
task_id: "${task_id}"
pipeline: null
developer: "user"
checkpoint: null
created_at: "${timestamp}"
EOF

  # ── Write status.yaml ──
  cat > "$task_dir/status.yaml" << EOF
task_id: "${task_id}"
description: "${short_desc}"
developer: "user"
created_at: "${timestamp}"
gates: []
retries:
  quality: 0
  agent_failures: 0
  budget_splits: 0
  total: 0
budget:
  by_agent: []
  estimated_tokens: 0
  actual_tokens: 0
warnings: []
EOF

  # ── Write input.md ──
  local size_line="none — classifier decides"
  if [[ -n "$size_hint" ]]; then
    size_line="$size_hint (user hint)"
  fi

  cat > "$task_dir/input.md" << EOF
# Task: ${task_id}

## Description
${description}

## Size Hint
${size_line}

## Created
${timestamp}
EOF

  # ── Write current.yaml ──
  cat > "$state_dir/current.yaml" << EOF
task_id: "${task_id}"
pipeline: null
step: "classification"
step_status: "pending"
step_started_at: "${timestamp}"
gate_pending: null
gate_options: []
context_budget:
  orchestrator_tokens_used: 0
  orchestrator_percent: 0
  total_agent_tokens: 0
  warning_level: normal
history: []
graph_available: false
temporal_available: false
EOF

  # ── Create session lock ──
  cat > "$state_dir/.session-lock" << EOF
pid: "session"
started: "${timestamp}"
task_id: "${task_id}"
ttl: 3600
EOF

  # ── Create guard-active marker ──
  touch "$state_dir/.guard-active"

  # Output task_id for caller
  echo "$task_id"
}

# ── moira_preflight_collect <state_dir> ────────────────────────────────
# Gather all init-time context the orchestrator needs, output as key=value lines.
# Called by task-submit.sh after moira_task_init(). Values injected via additionalContext.
# Deterministic: file reads + simple logic only. No MCP, no LLM, no network.
moira_preflight_collect() {
  local state_dir="$1"
  local project_dir
  project_dir=$(dirname "$(dirname "$(dirname "$state_dir")")")

  local config_file="${state_dir}/../config.yaml"
  local current_file="${state_dir}/current.yaml"

  # --- Graph availability ---
  local graph_available="false"
  local graph_stale="false"
  local graph_enabled="true"

  # Check config.yaml → graph.enabled
  if [[ -f "$config_file" ]]; then
    local ge
    ge=$(grep '^  enabled:' "$config_file" 2>/dev/null | head -1 | sed 's/.*enabled:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    # More precise: read the graph section
    ge=$(awk '/^graph:/{found=1;next} found && /^[^ ]/{found=0} found && /enabled:/{print $2;exit}' "$config_file" 2>/dev/null | tr -d '"' | tr -d "'" 2>/dev/null) || true
    if [[ "$ge" == "false" ]]; then
      graph_enabled="false"
    fi
  fi

  if [[ "$graph_enabled" == "true" && -f "${project_dir}/.ariadne/graph/graph.json" ]]; then
    graph_available="true"

    # Check staleness: compare meta.json timestamp vs latest git commit
    if [[ -f "${project_dir}/.ariadne/graph/meta.json" ]]; then
      local meta_ts git_ts
      meta_ts=$(stat -f '%m' "${project_dir}/.ariadne/graph/meta.json" 2>/dev/null || stat -c '%Y' "${project_dir}/.ariadne/graph/meta.json" 2>/dev/null) || meta_ts=0
      git_ts=$(git -C "$project_dir" log -1 --format='%ct' 2>/dev/null) || git_ts=0
      if [[ "$meta_ts" -gt 0 && "$git_ts" -gt 0 && "$git_ts" -gt "$meta_ts" ]]; then
        graph_stale="true"
      fi
    fi
  fi

  # Write graph_available to current.yaml for downstream hooks
  if [[ -f "$current_file" ]]; then
    sed -i.bak "s/^graph_available:.*/graph_available: ${graph_available}/" "$current_file" 2>/dev/null && rm -f "${current_file}.bak" || true
  fi

  # --- Quality mode ---
  local quality_mode="conform"
  local evolution_target=""
  if [[ -f "$config_file" ]]; then
    quality_mode=$(awk '/^quality:/{found=1;next} found && /^[^ ]/{found=0} found && /mode:/{print $2;exit}' "$config_file" 2>/dev/null | tr -d '"' | tr -d "'" 2>/dev/null) || quality_mode="conform"
    [[ -z "$quality_mode" ]] && quality_mode="conform"
    if [[ "$quality_mode" == "evolve" ]]; then
      evolution_target=$(awk '/current_target:/{print $2;exit}' "$config_file" 2>/dev/null | tr -d '"' | tr -d "'" 2>/dev/null) || evolution_target=""
    fi
  fi

  # --- Bench mode ---
  local bench_mode="false"
  if [[ -f "$current_file" ]]; then
    local bm
    bm=$(grep '^bench_mode:' "$current_file" 2>/dev/null | sed 's/^bench_mode:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || bm=""
    [[ "$bm" == "true" ]] && bench_mode="true"
  fi

  # --- Deep scan pending ---
  local deep_scan_pending="false"
  if [[ -f "$config_file" ]]; then
    local dsp
    dsp=$(awk '/deep_scan_pending:/{print $2;exit}' "$config_file" 2>/dev/null | tr -d '"' | tr -d "'" 2>/dev/null) || dsp=""
    [[ "$dsp" == "true" ]] && deep_scan_pending="true"
  fi

  # --- Audit pending ---
  local audit_pending="false"
  local audit_depth=""
  if [[ -f "${state_dir}/audit-pending.yaml" ]]; then
    audit_pending="true"
    audit_depth=$(grep '^audit_pending:' "${state_dir}/audit-pending.yaml" 2>/dev/null | sed 's/^audit_pending:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || audit_depth="standard"
    [[ -z "$audit_depth" ]] && audit_depth="standard"
  fi

  # --- Checkpointed task ---
  local checkpointed="false"
  local checkpointed_task=""
  local checkpointed_step=""
  if [[ -f "$current_file" ]]; then
    local ss
    ss=$(grep '^step_status:' "$current_file" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || ss=""
    if [[ "$ss" == "checkpointed" ]]; then
      checkpointed="true"
      checkpointed_task=$(grep '^task_id:' "$current_file" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
      checkpointed_step=$(grep '^step:' "$current_file" 2>/dev/null | sed 's/^step:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    fi
  fi

  # --- Stale knowledge ---
  local stale_knowledge_count=0
  if [[ -f "${_MOIRA_TASK_INIT_LIB_DIR}/knowledge.sh" ]]; then
    # Source knowledge lib if available
    source "${_MOIRA_TASK_INIT_LIB_DIR}/knowledge.sh" 2>/dev/null || true
    if command -v moira_knowledge_stale_entries &>/dev/null; then
      local knowledge_dir="${state_dir}/../knowledge"
      local task_num
      task_num=$(grep '^task_id:' "$current_file" 2>/dev/null | sed 's/.*T-0*//' | tr -d '"' | tr -d "'" 2>/dev/null) || task_num="1"
      stale_knowledge_count=$(moira_knowledge_stale_entries "$knowledge_dir" "$task_num" 2>/dev/null | wc -l | tr -d ' ') || stale_knowledge_count=0
    fi
  fi

  # --- Stale locks ---
  local stale_locks=""
  local locks_file="${state_dir}/../config/locks.yaml"
  if [[ -f "$locks_file" ]]; then
    local now_ts
    now_ts=$(date +%s 2>/dev/null) || now_ts=0
    # Simple TTL check: look for ttl: lines and compare with created_at
    # This is a best-effort check — locks.yaml structure may vary
    local lock_count
    lock_count=$(grep -c '^  ttl:' "$locks_file" 2>/dev/null) || lock_count=0
    if [[ "$lock_count" -gt 0 ]]; then
      stale_locks="$lock_count lock(s) found — check TTL manually"
    fi
  fi

  # --- Orphaned state ---
  local orphaned_state="false"
  if [[ -f "$current_file" ]]; then
    local ot os
    ot=$(grep '^task_id:' "$current_file" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || ot=""
    os=$(grep '^step_status:' "$current_file" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || os=""
    if [[ -n "$ot" && "$ot" != "null" && "$os" == "in_progress" ]]; then
      # Check if session lock is stale
      if [[ ! -f "${state_dir}/.session-lock" ]]; then
        orphaned_state="true"
      fi
    fi
  fi

  # --- Output structured block ---
  cat << EOF
graph_available=${graph_available}
graph_stale=${graph_stale}
quality_mode=${quality_mode}
evolution_target=${evolution_target}
bench_mode=${bench_mode}
deep_scan_pending=${deep_scan_pending}
audit_pending=${audit_pending}
audit_depth=${audit_depth}
checkpointed=${checkpointed}
checkpointed_task=${checkpointed_task}
checkpointed_step=${checkpointed_step}
stale_knowledge_count=${stale_knowledge_count}
stale_locks=${stale_locks}
orphaned_state=${orphaned_state}
EOF
}
