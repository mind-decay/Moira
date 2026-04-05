#!/usr/bin/env bash
# reflection.sh — Reflection system operations for Moira
# Cross-task observation tracking, pattern detection, and proposal management.
#
# Responsibilities: reflection data access ONLY
# Does NOT handle reflection dispatch (that's the reflection skill)
# Does NOT run Mnemosyne (that's the orchestrator via Agent tool)

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_REFLECTION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_REFLECTION_LIB_DIR}/yaml-utils.sh"

# ── moira_reflection_task_history <state_dir> [count] ─────────────────
# Scan completed tasks and return recent history sorted by completion time.
# Output per task: task_id pipeline_type final_review_passed retries_total classification_correct
# Returns 1 if no completed tasks found.
moira_reflection_task_history() {
  local state_dir="$1"
  local count="${2:-10}"
  local tasks_dir="${state_dir}/tasks"

  if [[ ! -d "$tasks_dir" ]]; then
    return 1
  fi

  local found=false
  local entries=""

  for task_dir in "$tasks_dir"/*/; do
    [[ ! -d "$task_dir" ]] && continue
    local status_file="${task_dir}status.yaml"
    [[ ! -f "$status_file" ]] && continue

    local status
    status=$(moira_yaml_get "$status_file" "status" 2>/dev/null) || continue

    # Only include completed tasks
    if [[ "$status" != "completed" ]]; then
      continue
    fi

    local task_id pipeline_type first_pass retry_count classification_correct completed_at
    task_id=$(moira_yaml_get "$status_file" "task_id" 2>/dev/null) || task_id="unknown"
    pipeline_type=$(moira_yaml_get "$status_file" "pipeline" 2>/dev/null) || pipeline_type="unknown"
    first_pass=$(moira_yaml_get "$status_file" "completion.final_review_passed" 2>/dev/null) || first_pass="unknown"
    retry_count=$(moira_yaml_get "$status_file" "retries.total" 2>/dev/null) || retry_count="0"
    local telemetry_file="${task_dir}telemetry.yaml"
    classification_correct=$(moira_yaml_get "$telemetry_file" "pipeline.classification_correct" 2>/dev/null) || classification_correct="unknown"
    completed_at=$(moira_yaml_get "$status_file" "completed_at" 2>/dev/null) || completed_at="unknown"

    found=true
    entries="${entries}${completed_at}|${task_id}|${pipeline_type}|${first_pass}|${retry_count}|${classification_correct}"$'\n'
  done

  if ! $found; then
    return 1
  fi

  # Sort by completion time (descending), take last N, output without timestamp
  echo "$entries" | grep -v '^$' | sort -r | head -n "$count" | while IFS='|' read -r _ts tid ptype fp rc cc; do
    echo "${tid} ${ptype} ${fp} ${rc} ${cc}"
  done

  return 0
}

# ── moira_reflection_observation_count <state_dir> <pattern_key> ──────
# Count observations matching a pattern key across task reflections.
# Returns integer count to stdout.
moira_reflection_observation_count() {
  local state_dir="$1"
  local pattern_key="$2"
  local tasks_dir="${state_dir}/tasks"
  local count=0

  if [[ ! -d "$tasks_dir" ]]; then
    echo "0"
    return 0
  fi

  for task_dir in "$tasks_dir"/*/; do
    [[ ! -d "$task_dir" ]] && continue
    local reflection_file="${task_dir}reflection.md"
    [[ ! -f "$reflection_file" ]] && continue

    local matches
    matches=$(grep -c "OBSERVATION: \[pattern_key:${pattern_key}\]" "$reflection_file" 2>/dev/null || echo "0")
    count=$(( count + matches ))
  done

  echo "$count"
  return 0
}

# ── moira_reflection_get_observations <state_dir> <pattern_key> ───────
# Return task_id, observation text, and evidence for each matching observation.
# Output format: task_id | observation_text | evidence_text
moira_reflection_get_observations() {
  local state_dir="$1"
  local pattern_key="$2"
  local tasks_dir="${state_dir}/tasks"

  if [[ ! -d "$tasks_dir" ]]; then
    return 0
  fi

  for task_dir in "$tasks_dir"/*/; do
    [[ ! -d "$task_dir" ]] && continue
    local reflection_file="${task_dir}reflection.md"
    [[ ! -f "$reflection_file" ]] && continue

    # Extract task_id from directory name
    local task_id
    task_id=$(basename "$task_dir")

    # Find OBSERVATION lines matching pattern key, then grab following EVIDENCE line
    local in_match=false
    local obs_text=""
    while IFS= read -r line; do
      if echo "$line" | grep -q "OBSERVATION: \[pattern_key:${pattern_key}\]" 2>/dev/null; then
        obs_text="$line"
        in_match=true
      elif $in_match; then
        if echo "$line" | grep -q "^[[:space:]]*EVIDENCE:" 2>/dev/null; then
          local evidence_text
          evidence_text=$(echo "$line" | sed 's/^[[:space:]]*EVIDENCE:[[:space:]]*//')
          echo "${task_id} | ${obs_text} | ${evidence_text}"
        fi
        in_match=false
        obs_text=""
      fi
    done < "$reflection_file"
  done

  return 0
}

# ── moira_reflection_mcp_call_frequency <state_dir> ──────────────────
# Detect repeated MCP calls across tasks for caching recommendations.
# Returns entries with 3+ occurrences.
# Output: server tool query_pattern count total_tokens
moira_reflection_mcp_call_frequency() {
  local state_dir="$1"
  local tasks_dir="${state_dir}/tasks"

  if [[ ! -d "$tasks_dir" ]]; then
    return 0
  fi

  # Collect all mcp_calls entries across tasks into a temp file
  local tmpfile
  tmpfile=$(mktemp)

  for task_dir in "$tasks_dir"/*/; do
    [[ ! -d "$task_dir" ]] && continue
    local telemetry_file="${task_dir}telemetry.yaml"
    [[ ! -f "$telemetry_file" ]] && continue

    # Extract mcp_calls entries using awk
    awk '
    /^mcp_calls:/ { in_mcp=1; next }
    in_mcp && /^[^ ]/ { in_mcp=0 }
    in_mcp && /^[[:space:]]*- server:/ {
      gsub(/^[[:space:]]*- server:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      server=$0
    }
    in_mcp && /^[[:space:]]*tool:/ {
      gsub(/^[[:space:]]*tool:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      tool=$0
    }
    in_mcp && /^[[:space:]]*query_summary:/ {
      gsub(/^[[:space:]]*query_summary:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      query=$0
    }
    in_mcp && /^[[:space:]]*tokens_used:/ {
      gsub(/^[[:space:]]*tokens_used:[[:space:]]*/, "")
      tokens=$0+0
      print server "|" tool "|" query "|" tokens
    }
    ' "$telemetry_file" >> "$tmpfile"
  done

  if [[ ! -s "$tmpfile" ]]; then
    rm -f "$tmpfile"
    return 0
  fi

  # Aggregate by server:tool:query, count occurrences and sum tokens
  awk -F'|' '
  {
    key = $1 "|" $2 "|" $3
    counts[key]++
    tokens[key] += $4
  }
  END {
    for (key in counts) {
      if (counts[key] >= 3) {
        split(key, parts, "|")
        print parts[1] " " parts[2] " " parts[3] " " counts[key] " " tokens[key]
      }
    }
  }' "$tmpfile"

  rm -f "$tmpfile"
  return 0
}

# ── moira_reflection_pending_proposals <state_dir> ───────────────────
# List pending rule change proposals.
# Returns proposal entries with status=pending, empty if file doesn't exist.
moira_reflection_pending_proposals() {
  local state_dir="$1"
  local proposals_file="${state_dir}/reflection/proposals.yaml"

  if [[ ! -f "$proposals_file" ]]; then
    return 0
  fi

  # Extract pending proposals using awk
  awk '
  /^[[:space:]]*- id:/ {
    gsub(/^[[:space:]]*- id:[[:space:]]*/, "")
    gsub(/["'"'"']/, "")
    current_id=$0
    current_status=""
    current_block=""
  }
  /^[[:space:]]*status:/ {
    gsub(/^[[:space:]]*status:[[:space:]]*/, "")
    gsub(/["'"'"']/, "")
    current_status=$0
  }
  /^[[:space:]]*- id:/ || /^$/ {
    if (current_id != "" && current_status == "pending") {
      print current_block
    }
    current_block=""
  }
  { current_block = current_block $0 "\n" }
  END {
    if (current_id != "" && current_status == "pending") {
      print current_block
    }
  }
  ' "$proposals_file"

  return 0
}

# ── moira_reflection_record_proposal <state_dir> <proposal_yaml> ─────
# Record a new rule change proposal.
# Appends to state/reflection/proposals.yaml with status=pending and timestamp.
moira_reflection_record_proposal() {
  local state_dir="$1"
  local proposal_yaml="$2"
  local proposals_file="${state_dir}/reflection/proposals.yaml"

  mkdir -p "${state_dir}/reflection"

  # Create file with header if it doesn't exist
  if [[ ! -f "$proposals_file" ]]; then
    echo "# Rule change proposals" > "$proposals_file"
    echo "proposals:" >> "$proposals_file"
  fi

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Append the proposal with status and timestamp
  {
    echo "  - ${proposal_yaml}"
    echo "    status: pending"
    echo "    created: \"${timestamp}\""
  } >> "$proposals_file"

  return 0
}

# ── moira_reflection_resolve_proposal <state_dir> <proposal_id> <resolution>
# Update proposal status (approved/rejected/deferred).
moira_reflection_resolve_proposal() {
  local state_dir="$1"
  local proposal_id="$2"
  local resolution="$3"
  local proposals_file="${state_dir}/reflection/proposals.yaml"

  if [[ ! -f "$proposals_file" ]]; then
    echo "Error: proposals file not found: $proposals_file" >&2
    return 1
  fi

  # Validate resolution
  case "$resolution" in
    approved|rejected|deferred) ;;
    *)
      echo "Error: invalid resolution '$resolution' (must be approved, rejected, or deferred)" >&2
      return 1
      ;;
  esac

  # Use sed to find the proposal by id and update its status field
  # Find line with matching id, then find next status: line and replace value
  local tmpfile
  tmpfile=$(mktemp)

  awk -v pid="$proposal_id" -v res="$resolution" '
  {
    if ($0 ~ "id:.*" pid) {
      found=1
    }
    if (found && /^[[:space:]]*status:/) {
      sub(/status:.*/, "status: " res)
      found=0
    }
    print
  }
  ' "$proposals_file" > "$tmpfile"

  mv "$tmpfile" "$proposals_file"
  return 0
}

# ── moira_reflection_deep_counter <state_dir> [increment|reset] ──────
# Manage the periodic deep reflection counter.
# No args: return current count (0 if file missing)
# increment: increment by 1
# reset: set to 0
moira_reflection_deep_counter() {
  local state_dir="$1"
  local action="${2:-}"
  local counter_file="${state_dir}/reflection/deep-reflection-counter.yaml"

  mkdir -p "${state_dir}/reflection"

  if [[ -z "$action" ]]; then
    # Read current count
    if [[ ! -f "$counter_file" ]]; then
      echo "0"
      return 0
    fi
    local count
    count=$(moira_yaml_get "$counter_file" "count" 2>/dev/null) || count="0"
    echo "$count"
    return 0
  fi

  case "$action" in
    increment)
      local current=0
      if [[ -f "$counter_file" ]]; then
        current=$(moira_yaml_get "$counter_file" "count" 2>/dev/null) || current="0"
      fi
      local new_count=$(( current + 1 ))
      echo "count: ${new_count}" > "$counter_file"
      echo "$new_count"
      ;;
    reset)
      echo "count: 0" > "$counter_file"
      echo "0"
      ;;
    *)
      echo "Error: invalid action '$action' (must be increment or reset)" >&2
      return 1
      ;;
  esac

  return 0
}

# ── moira_reflection_auto_defer_stale <state_dir> ───────────────────
# Scan proposals.yaml for pending entries older than 30 days, set status=deferred.
moira_reflection_auto_defer_stale() {
  local state_dir="$1"
  local proposals_file="${state_dir}/reflection/proposals.yaml"

  if [[ ! -f "$proposals_file" ]]; then
    return 0
  fi

  # Get current date as epoch seconds
  local now_epoch
  if date -j -f "%Y-%m-%d" "2000-01-01" "+%s" >/dev/null 2>&1; then
    # macOS date
    now_epoch=$(date -j "+%s")
  else
    # GNU date
    now_epoch=$(date "+%s")
  fi

  local threshold=$(( now_epoch - 30 * 86400 ))

  # Extract pending proposal IDs with old dates, then resolve each
  local -a stale_ids=()
  local current_id="" current_status="" current_created=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '- id:' 2>/dev/null; then
      # Process previous proposal if stale
      if [[ -n "$current_id" && "$current_status" == "pending" && -n "$current_created" ]]; then
        local created_date
        created_date=$(echo "$current_created" | sed 's/T.*//')
        local created_epoch
        if date -j -f "%Y-%m-%d" "$created_date" "+%s" >/dev/null 2>&1; then
          created_epoch=$(date -j -f "%Y-%m-%d" "$created_date" "+%s" 2>/dev/null) || created_epoch="$now_epoch"
        else
          created_epoch=$(date -d "$created_date" "+%s" 2>/dev/null) || created_epoch="$now_epoch"
        fi

        if [[ "$created_epoch" -lt "$threshold" ]]; then
          stale_ids+=("$current_id")
        fi
      fi

      current_id=$(echo "$line" | sed 's/.*- id:[[:space:]]*//' | sed 's/["'"'"']//g')
      current_status=""
      current_created=""
    fi

    if echo "$line" | grep -q '^\s*status:' 2>/dev/null; then
      current_status=$(echo "$line" | sed 's/.*status:[[:space:]]*//' | sed 's/["'"'"']//g')
    fi

    if echo "$line" | grep -q '^\s*created:' 2>/dev/null; then
      current_created=$(echo "$line" | sed 's/.*created:[[:space:]]*//' | sed 's/["'"'"']//g')
    fi
  done < "$proposals_file"

  # Process last proposal
  if [[ -n "$current_id" && "$current_status" == "pending" && -n "$current_created" ]]; then
    local created_date
    created_date=$(echo "$current_created" | sed 's/T.*//')
    local created_epoch
    if date -j -f "%Y-%m-%d" "$created_date" "+%s" >/dev/null 2>&1; then
      created_epoch=$(date -j -f "%Y-%m-%d" "$created_date" "+%s" 2>/dev/null) || created_epoch="$now_epoch"
    else
      created_epoch=$(date -d "$created_date" "+%s" 2>/dev/null) || created_epoch="$now_epoch"
    fi

    if [[ "$created_epoch" -lt "$threshold" ]]; then
      stale_ids="${stale_ids} ${current_id}"
    fi
  fi

  # Resolve each stale proposal
  for pid in "${stale_ids[@]}"; do
    moira_reflection_resolve_proposal "$state_dir" "$pid" "deferred"
  done

  return 0
}
