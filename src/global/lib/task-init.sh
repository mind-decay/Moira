#!/usr/bin/env bash
# task-init.sh — Task scaffold for Moira
# Creates task directory, initializes state files, sets up session lock.
# Called by task-submit.sh hook (UserPromptSubmit) before orchestrator starts.
#
# Responsibilities: task scaffold + initial state ONLY
# Does NOT handle pipeline logic (that's the orchestrator skill)

set -euo pipefail

_MOIRA_TASK_INIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
