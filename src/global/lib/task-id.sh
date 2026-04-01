#!/usr/bin/env bash
# task-id.sh — Task ID generation for Moira
# Format: task-YYYY-MM-DD-NNN (zero-padded 3-digit counter)
# Provides sortability and cross-day uniqueness.
#
# Responsibilities: ID generation ONLY

set -euo pipefail

# ── moira_task_id [state_dir] ─────────────────────────────────────────
# Generate a unique task ID based on today's date and existing tasks.
# state_dir defaults to .moira/state (current project).
# Outputs the new task ID to stdout.
moira_task_id() {
  local state_dir="${1:-.moira/state}"
  local today
  today=$(date +%Y-%m-%d)
  local tasks_dir="${state_dir}/tasks"

  # If tasks directory doesn't exist, start at 001
  if [[ ! -d "$tasks_dir" ]]; then
    echo "task-${today}-001"
    return 0
  fi

  # Find highest NNN for today's date
  local max_num=0
  local pattern="task-${today}-"

  for dir in "$tasks_dir"/${pattern}*/; do
    [[ -d "$dir" ]] || continue
    local basename
    basename=$(basename "$dir")
    # Extract NNN from task-YYYY-MM-DD-NNN
    local num_str="${basename##*-}"
    # Remove leading zeros for arithmetic
    local num=$((10#$num_str))
    if (( num > max_num )); then
      max_num=$num
    fi
  done

  local next_num=$(( max_num + 1 ))

  if (( next_num > 999 )); then
    echo "Error: exceeded 999 tasks for $today" >&2
    return 1
  fi

  printf "task-%s-%03d\n" "$today" "$next_num"
}
