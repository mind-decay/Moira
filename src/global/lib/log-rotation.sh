#!/usr/bin/env bash
# Log rotation — archive oversized log files (D-143)
# Called at task start, before new task begins writing.
# MUST be safe: never truncate without successful archive.

# Source: architecture.md Decision 5 (task-2026-03-24-006)

moira_rotate_logs() {
  local state_dir="${1:?Usage: moira_rotate_logs <state_dir>}"
  local config_file="${2:-}"

  # Default threshold (overridden by config if available)
  local threshold=5000
  local archive_dir="$state_dir/archive"

  # Read threshold from config if available
  if [[ -n "$config_file" && -f "$config_file" ]]; then
    local config_threshold
    config_threshold=$(grep '^  rotation_threshold_lines:' "$config_file" 2>/dev/null | sed 's/.*rotation_threshold_lines:[[:space:]]*//' | tr -d '"' 2>/dev/null) || true
    if [[ -n "$config_threshold" && "$config_threshold" =~ ^[0-9]+$ ]]; then
      threshold="$config_threshold"
    fi

    local config_archive
    config_archive=$(grep '^  archive_dir:' "$config_file" 2>/dev/null | sed 's/.*archive_dir:[[:space:]]*//' | tr -d '"' 2>/dev/null) || true
    if [[ -n "$config_archive" ]]; then
      # archive_dir in config is relative to state_dir's parent (.claude/moira/)
      local moira_dir
      moira_dir=$(dirname "$state_dir")
      archive_dir="$moira_dir/$config_archive"
    fi
  fi

  # Target log files
  local log_files=("violations.log" "tool-usage.log" "budget-tool-usage.log")
  local rotated=0

  for log_name in "${log_files[@]}"; do
    local log_path="$state_dir/$log_name"

    # Skip if file doesn't exist or is empty
    [[ -f "$log_path" ]] || continue

    # Check line count
    local line_count
    line_count=$(wc -l < "$log_path" 2>/dev/null) || continue
    line_count=$(echo "$line_count" | tr -d ' ')

    if [[ "$line_count" -gt "$threshold" ]]; then
      # Create archive directory if needed
      if ! mkdir -p "$archive_dir" 2>/dev/null; then
        echo "WARNING: Cannot create archive dir $archive_dir, skipping rotation for $log_name" >&2
        continue
      fi

      # Generate timestamp for archive filename
      local timestamp
      timestamp=$(date '+%Y-%m-%d-%H%M%S' 2>/dev/null) || timestamp="unknown"

      local archive_path="$archive_dir/${log_name}.${timestamp}"

      # Move-then-create (atomic: archive first, create empty second)
      if mv "$log_path" "$archive_path" 2>/dev/null; then
        touch "$log_path" 2>/dev/null || true
        rotated=$((rotated + 1))
      else
        echo "WARNING: Failed to rotate $log_name, skipping" >&2
      fi
    fi
  done

  if [[ "$rotated" -gt 0 ]]; then
    echo "Rotated $rotated log file(s) to $archive_dir"
  fi

  return 0
}
