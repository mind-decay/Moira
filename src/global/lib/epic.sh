#!/usr/bin/env bash
# epic.sh — Epic task queue management and DAG-based sub-task scheduling
# Provides queue parsing, DAG validation (Kahn's algorithm), dependency
# checking, next-task selection, and progress updates for epic pipelines.
#
# Source: design/specs/2026-03-16-phase12-implementation-plan.md Task 3.1

set -euo pipefail

# Source yaml-utils from the same directory
_EPIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_EPIC_DIR}/yaml-utils.sh"

# ── moira_epic_parse_queue <task_id> [state_dir] ─────────────────────
# Read state/tasks/{task_id}/queue.yaml, validate required fields,
# output parsed task list (id, description, size, status, depends_on).
moira_epic_parse_queue() {
  [[ -n "${ZSH_VERSION:-}" ]] && setopt localoptions KSH_ARRAYS

  local task_id="$1"
  local state_dir="${2:-.moira/state}"
  local queue_file="${state_dir}/tasks/${task_id}/queue.yaml"

  if [[ ! -f "$queue_file" ]]; then
    echo "Error: queue file not found: $queue_file" >&2
    return 1
  fi

  # Validate required fields
  local epic_id
  epic_id=$(moira_yaml_get "$queue_file" "epic_id" 2>/dev/null) || true
  if [[ -z "$epic_id" || "$epic_id" == "null" ]]; then
    echo "Error: missing required field 'epic_id' in $queue_file" >&2
    return 1
  fi

  # Parse tasks block — extract sub-task entries
  # Each sub-task is a YAML list item under "tasks:" with fields:
  #   id, description, size, status, depends_on
  local in_tasks=false
  local current_id="" current_desc="" current_size="" current_status=""
  local current_depends=""

  while IFS= read -r line; do
    # Detect start of tasks block
    if [[ "$line" =~ ^tasks: ]]; then
      in_tasks=true
      continue
    fi

    # End of tasks block: next top-level key (non-indented, not comment/blank)
    if $in_tasks && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]] ]] && [[ ! "$line" =~ ^# ]]; then
      break
    fi

    if ! $in_tasks; then
      continue
    fi

    # New sub-task entry (list item)
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+id:[[:space:]]*(.*) ]]; then
      # Print previous sub-task if we had one
      if [[ -n "$current_id" ]]; then
        echo "id:${current_id}|description:${current_desc}|size:${current_size}|status:${current_status}|depends_on:${current_depends}"
      fi
      current_id="${BASH_REMATCH[1]}"
      current_id="${current_id## }"
      current_id="${current_id%% }"
      current_desc=""
      current_size=""
      current_status=""
      current_depends=""
    elif [[ "$line" =~ ^[[:space:]]+description:[[:space:]]*(.*) ]]; then
      current_desc="${BASH_REMATCH[1]}"
      current_desc="${current_desc#\"}"
      current_desc="${current_desc%\"}"
    elif [[ "$line" =~ ^[[:space:]]+size:[[:space:]]*(.*) ]]; then
      current_size="${BASH_REMATCH[1]}"
      current_size="${current_size## }"
    elif [[ "$line" =~ ^[[:space:]]+status:[[:space:]]*(.*) ]]; then
      current_status="${BASH_REMATCH[1]}"
      current_status="${current_status## }"
    elif [[ "$line" =~ ^[[:space:]]+depends_on:[[:space:]]*\[(.*)\] ]]; then
      # Inline array: depends_on: [task-1, task-2]
      current_depends="${BASH_REMATCH[1]}"
      current_depends="${current_depends// /}"
    elif [[ "$line" =~ ^[[:space:]]+depends_on:[[:space:]]*$ ]]; then
      # Block-style depends_on — will read items on next lines
      current_depends=""
    elif [[ -n "$current_id" ]] && [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
      # Block-style depends_on item
      local dep_item="${BASH_REMATCH[1]}"
      dep_item="${dep_item## }"
      dep_item="${dep_item%% }"
      if [[ -n "$current_depends" ]]; then
        current_depends="${current_depends},${dep_item}"
      else
        current_depends="${dep_item}"
      fi
    fi
  done < "$queue_file"

  # Print last sub-task
  if [[ -n "$current_id" ]]; then
    echo "id:${current_id}|description:${current_desc}|size:${current_size}|status:${current_status}|depends_on:${current_depends}"
  fi
}

# ── moira_epic_validate_dag <task_id> [state_dir] ────────────────────
# Parse queue, extract task IDs and depends_on edges.
# Run Kahn's algorithm to detect cycles.
# Check all depends_on references are valid task IDs and no self-references.
# Returns: echo "valid" or "cycle_detected:{path}"
moira_epic_validate_dag() {
  [[ -n "${ZSH_VERSION:-}" ]] && setopt localoptions KSH_ARRAYS

  local task_id="$1"
  local state_dir="${2:-.moira/state}"

  local parsed
  parsed=$(moira_epic_parse_queue "$task_id" "$state_dir") || return $?

  if [[ -z "$parsed" ]]; then
    echo "valid"
    return 0
  fi

  # Collect all task IDs into an associative-style flat list
  # Bash 3.2 compatible: use parallel arrays instead of associative arrays
  local all_ids=""
  local -a node_ids=()
  local -a node_deps=()
  local node_count=0

  while IFS= read -r record; do
    local tid=""
    local deps=""
    # Parse fields from pipe-delimited record
    if [[ -n "${ZSH_VERSION:-}" ]]; then IFS='|' read -rA fields <<< "$record"; else IFS='|' read -ra fields <<< "$record"; fi
    for field in "${fields[@]}"; do
      case "$field" in
        id:*) tid="${field#id:}" ;;
        depends_on:*) deps="${field#depends_on:}" ;;
      esac
    done

    if [[ -n "$tid" ]]; then
      node_ids+=("$tid")
      node_deps+=("$deps")
      all_ids="${all_ids} ${tid}"
      node_count=$(( node_count + 1 ))
    fi
  done <<< "$parsed"

  # Check for self-references and invalid depends_on references
  for (( i=0; i<node_count; i++ )); do
    local tid="${node_ids[$i]}"
    local deps="${node_deps[$i]}"
    if [[ -z "$deps" ]]; then
      continue
    fi
    if [[ -n "${ZSH_VERSION:-}" ]]; then IFS=',' read -rA dep_list <<< "$deps"; else IFS=',' read -ra dep_list <<< "$deps"; fi
    for dep in "${dep_list[@]}"; do
      dep="${dep## }"
      dep="${dep%% }"
      if [[ -z "$dep" ]]; then
        continue
      fi
      # Self-reference check
      if [[ "$dep" == "$tid" ]]; then
        echo "cycle_detected:${tid}->${tid}"
        return 0
      fi
      # Valid reference check
      if [[ ! " ${all_ids} " =~ " ${dep} " ]]; then
        echo "Error: task '${tid}' depends on unknown task '${dep}'" >&2
        return 1
      fi
    done
  done

  # Kahn's algorithm for topological sort / cycle detection
  # Build in-degree counts (bash 3.2 compatible: parallel arrays)
  local -a in_degree=()
  for (( i=0; i<node_count; i++ )); do
    in_degree+=("0")
  done

  # Helper: find index of a node ID
  _epic_find_index() {
    local target="$1"
    for (( j=0; j<node_count; j++ )); do
      if [[ "${node_ids[$j]}" == "$target" ]]; then
        echo "$j"
        return 0
      fi
    done
    return 1
  }

  # Calculate in-degrees: in-degree of a node = count of its dependencies
  # (depends_on means "I depend on these", so edge goes dep->me, and in-degree = |depends_on|)
  for (( i=0; i<node_count; i++ )); do
    local deps="${node_deps[$i]}"
    if [[ -z "$deps" ]]; then
      continue
    fi
    local count=0
    if [[ -n "${ZSH_VERSION:-}" ]]; then IFS=',' read -rA dep_list <<< "$deps"; else IFS=',' read -ra dep_list <<< "$deps"; fi
    for dep in "${dep_list[@]}"; do
      dep="${dep## }"
      dep="${dep%% }"
      if [[ -n "$dep" ]]; then
        count=$(( count + 1 ))
      fi
    done
    in_degree[$i]=$count
  done

  # Initialize queue with zero-in-degree nodes
  local -a queue=()
  for (( i=0; i<node_count; i++ )); do
    if [[ "${in_degree[$i]}" -eq 0 ]]; then
      queue+=("$i")
    fi
  done

  # Process: dequeue, decrement dependents' in-degrees, enqueue new zeros
  local processed=0
  local q_front=0
  while [[ "$q_front" -lt "${#queue[@]}" ]]; do
    local current_idx="${queue[$q_front]}"
    q_front=$(( q_front + 1 ))
    processed=$(( processed + 1 ))

    local current_node="${node_ids[$current_idx]}"

    # Find all nodes that depend on current_node and decrement their in-degree
    for (( i=0; i<node_count; i++ )); do
      local deps="${node_deps[$i]}"
      if [[ -z "$deps" ]]; then
        continue
      fi
      if [[ -n "${ZSH_VERSION:-}" ]]; then IFS=',' read -rA dep_list <<< "$deps"; else IFS=',' read -ra dep_list <<< "$deps"; fi
      for dep in "${dep_list[@]}"; do
        dep="${dep## }"
        dep="${dep%% }"
        if [[ "$dep" == "$current_node" ]]; then
          in_degree[$i]=$(( ${in_degree[$i]} - 1 ))
          if [[ "${in_degree[$i]}" -eq 0 ]]; then
            queue+=("$i")
          fi
          break
        fi
      done
    done
  done

  # If processed count < total nodes, cycle exists
  if [[ "$processed" -lt "$node_count" ]]; then
    # Collect nodes still with in-degree > 0 for the cycle path
    local cycle_nodes=""
    for (( i=0; i<node_count; i++ )); do
      if [[ "${in_degree[$i]}" -gt 0 ]]; then
        if [[ -n "$cycle_nodes" ]]; then
          cycle_nodes="${cycle_nodes}->${node_ids[$i]}"
        else
          cycle_nodes="${node_ids[$i]}"
        fi
      fi
    done
    echo "cycle_detected:${cycle_nodes}"
    return 0
  fi

  echo "valid"
}

# ── moira_epic_next_tasks <task_id> [state_dir] ─────────────────────
# Find tasks where status=pending AND all depends_on tasks are completed.
# Sort by transitive dependency depth (fewest deps first).
# Output eligible task IDs, one per line.
moira_epic_next_tasks() {
  [[ -n "${ZSH_VERSION:-}" ]] && setopt localoptions KSH_ARRAYS

  local task_id="$1"
  local state_dir="${2:-.moira/state}"

  local parsed
  parsed=$(moira_epic_parse_queue "$task_id" "$state_dir") || return $?

  if [[ -z "$parsed" ]]; then
    return 0
  fi

  # Build parallel arrays of task data
  local -a t_ids=()
  local -a t_statuses=()
  local -a t_deps=()
  local t_count=0

  while IFS= read -r record; do
    local tid="" status="" deps=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then IFS='|' read -rA fields <<< "$record"; else IFS='|' read -ra fields <<< "$record"; fi
    for field in "${fields[@]}"; do
      case "$field" in
        id:*) tid="${field#id:}" ;;
        status:*) status="${field#status:}" ;;
        depends_on:*) deps="${field#depends_on:}" ;;
      esac
    done
    t_ids+=("$tid")
    t_statuses+=("$status")
    t_deps+=("$deps")
    t_count=$(( t_count + 1 ))
  done <<< "$parsed"

  # Helper: get status of a task by ID
  _epic_get_status() {
    local target="$1"
    for (( k=0; k<t_count; k++ )); do
      if [[ "${t_ids[$k]}" == "$target" ]]; then
        echo "${t_statuses[$k]}"
        return 0
      fi
    done
    echo "unknown"
  }

  # Helper: calculate transitive dependency depth (memoized via recursion limit)
  _epic_dep_depth() {
    local target="$1"
    local max_depth=0
    for (( k=0; k<t_count; k++ )); do
      if [[ "${t_ids[$k]}" == "$target" ]]; then
        local deps="${t_deps[$k]}"
        if [[ -z "$deps" ]]; then
          echo 0
          return 0
        fi
        if [[ -n "${ZSH_VERSION:-}" ]]; then IFS=',' read -rA dep_list <<< "$deps"; else IFS=',' read -ra dep_list <<< "$deps"; fi
        for dep in "${dep_list[@]}"; do
          dep="${dep## }"
          dep="${dep%% }"
          if [[ -z "$dep" ]]; then
            continue
          fi
          local child_depth
          child_depth=$(_epic_dep_depth "$dep")
          local total=$(( child_depth + 1 ))
          if [[ "$total" -gt "$max_depth" ]]; then
            max_depth=$total
          fi
        done
        echo "$max_depth"
        return 0
      fi
    done
    echo 0
  }

  # Find eligible tasks: status=pending and all dependencies completed
  local -a eligible_ids=()
  local -a eligible_depths=()

  for (( i=0; i<t_count; i++ )); do
    if [[ "${t_statuses[$i]}" != "pending" ]]; then
      continue
    fi

    local deps="${t_deps[$i]}"
    local all_deps_met=true

    if [[ -n "$deps" ]]; then
      if [[ -n "${ZSH_VERSION:-}" ]]; then IFS=',' read -rA dep_list <<< "$deps"; else IFS=',' read -ra dep_list <<< "$deps"; fi
      for dep in "${dep_list[@]}"; do
        dep="${dep## }"
        dep="${dep%% }"
        if [[ -z "$dep" ]]; then
          continue
        fi
        local dep_status
        dep_status=$(_epic_get_status "$dep")
        if [[ "$dep_status" != "completed" ]]; then
          all_deps_met=false
          break
        fi
      done
    fi

    if $all_deps_met; then
      local depth
      depth=$(_epic_dep_depth "${t_ids[$i]}")
      eligible_ids+=("${t_ids[$i]}")
      eligible_depths+=("$depth")
    fi
  done

  # Sort by depth (fewest deps first) — simple insertion sort
  local eligible_count="${#eligible_ids[@]}"
  for (( i=1; i<eligible_count; i++ )); do
    local key_id="${eligible_ids[$i]}"
    local key_depth="${eligible_depths[$i]}"
    local j=$(( i - 1 ))
    while [[ "$j" -ge 0 ]] && [[ "${eligible_depths[$j]}" -gt "$key_depth" ]]; do
      eligible_ids[$(( j + 1 ))]="${eligible_ids[$j]}"
      eligible_depths[$(( j + 1 ))]="${eligible_depths[$j]}"
      j=$(( j - 1 ))
    done
    eligible_ids[$(( j + 1 ))]="$key_id"
    eligible_depths[$(( j + 1 ))]="$key_depth"
  done

  # Output eligible task IDs, one per line
  for (( i=0; i<eligible_count; i++ )); do
    echo "${eligible_ids[$i]}"
  done
}

# ── moira_epic_update_progress <task_id> <subtask_id> <new_status> [state_dir]
# Update subtask status in queue.yaml using moira_yaml_set.
# Recalculate progress.completed/in_progress/pending/failed.
moira_epic_update_progress() {
  [[ -n "${ZSH_VERSION:-}" ]] && setopt localoptions KSH_ARRAYS

  local task_id="$1"
  local subtask_id="$2"
  local new_status="$3"
  local state_dir="${4:-.moira/state}"
  local queue_file="${state_dir}/tasks/${task_id}/queue.yaml"

  if [[ ! -f "$queue_file" ]]; then
    echo "Error: queue file not found: $queue_file" >&2
    return 1
  fi

  # Validate status
  case "$new_status" in
    pending|in_progress|completed|failed) ;;
    *)
      echo "Error: invalid subtask status '$new_status' (must be pending/in_progress/completed/failed)" >&2
      return 1
      ;;
  esac

  # Update the subtask status in queue.yaml
  # Since yaml-utils supports simple key paths but tasks are a block list,
  # we do an in-place sed update for the specific subtask's status field.
  local found=false
  local in_target=false
  local tmpfile="${queue_file}.tmp.$$"

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+id:[[:space:]]*${subtask_id}[[:space:]]*$ ]]; then
      in_target=true
      echo "$line" >> "$tmpfile"
      continue
    fi
    # New list item or top-level key ends our target
    if $in_target && [[ "$line" =~ ^[[:space:]]*-[[:space:]]+id: || ( -n "$line" && ! "$line" =~ ^[[:space:]] && ! "$line" =~ ^# ) ]]; then
      in_target=false
    fi
    if $in_target && [[ "$line" =~ ^([[:space:]]+status:)[[:space:]]*.* ]]; then
      echo "${BASH_REMATCH[1]} ${new_status}" >> "$tmpfile"
      found=true
      continue
    fi
    echo "$line" >> "$tmpfile"
  done < "$queue_file"

  if ! $found; then
    rm -f "$tmpfile"
    echo "Error: subtask '${subtask_id}' not found in queue" >&2
    return 1
  fi

  mv "$tmpfile" "$queue_file"

  # Recalculate progress counts from the updated file
  local completed=0 in_progress=0 pending=0 failed=0 total=0

  local parsed
  parsed=$(moira_epic_parse_queue "$task_id" "$state_dir") || return $?

  while IFS= read -r record; do
    local status=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then IFS='|' read -rA fields <<< "$record"; else IFS='|' read -ra fields <<< "$record"; fi
    for field in "${fields[@]}"; do
      case "$field" in
        status:*) status="${field#status:}" ;;
      esac
    done
    total=$(( total + 1 ))
    case "$status" in
      completed) completed=$(( completed + 1 )) ;;
      in_progress) in_progress=$(( in_progress + 1 )) ;;
      pending) pending=$(( pending + 1 )) ;;
      failed) failed=$(( failed + 1 )) ;;
    esac
  done <<< "$parsed"

  moira_yaml_set "$queue_file" "progress.total" "$total"
  moira_yaml_set "$queue_file" "progress.completed" "$completed"
  moira_yaml_set "$queue_file" "progress.in_progress" "$in_progress"
  moira_yaml_set "$queue_file" "progress.pending" "$pending"
  moira_yaml_set "$queue_file" "progress.failed" "$failed"

  echo "updated: ${subtask_id} -> ${new_status} (${completed}/${total} completed)"
}

# ── moira_epic_check_dependencies <task_id> <subtask_id> [state_dir] ─
# Find subtask's depends_on list, check each dependency status.
# Returns: echo "ready" or "blocked:{incomplete_deps}"
moira_epic_check_dependencies() {
  [[ -n "${ZSH_VERSION:-}" ]] && setopt localoptions KSH_ARRAYS

  local task_id="$1"
  local subtask_id="$2"
  local state_dir="${3:-.moira/state}"

  local parsed
  parsed=$(moira_epic_parse_queue "$task_id" "$state_dir") || return $?

  if [[ -z "$parsed" ]]; then
    echo "Error: no tasks found in queue" >&2
    return 1
  fi

  # Build parallel arrays of task data
  local -a t_ids=()
  local -a t_statuses=()
  local -a t_deps=()
  local t_count=0

  while IFS= read -r record; do
    local tid="" status="" deps=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then IFS='|' read -rA fields <<< "$record"; else IFS='|' read -ra fields <<< "$record"; fi
    for field in "${fields[@]}"; do
      case "$field" in
        id:*) tid="${field#id:}" ;;
        status:*) status="${field#status:}" ;;
        depends_on:*) deps="${field#depends_on:}" ;;
      esac
    done
    t_ids+=("$tid")
    t_statuses+=("$status")
    t_deps+=("$deps")
    t_count=$(( t_count + 1 ))
  done <<< "$parsed"

  # Find the target subtask
  local target_deps=""
  local found=false
  for (( i=0; i<t_count; i++ )); do
    if [[ "${t_ids[$i]}" == "$subtask_id" ]]; then
      target_deps="${t_deps[$i]}"
      found=true
      break
    fi
  done

  if ! $found; then
    echo "Error: subtask '${subtask_id}' not found in queue" >&2
    return 1
  fi

  # No dependencies means ready
  if [[ -z "$target_deps" ]]; then
    echo "ready"
    return 0
  fi

  # Check each dependency
  local incomplete=""
  if [[ -n "${ZSH_VERSION:-}" ]]; then IFS=',' read -rA dep_list <<< "$target_deps"; else IFS=',' read -ra dep_list <<< "$target_deps"; fi
  for dep in "${dep_list[@]}"; do
    dep="${dep## }"
    dep="${dep%% }"
    if [[ -z "$dep" ]]; then
      continue
    fi

    # Find dependency status
    local dep_status="unknown"
    for (( i=0; i<t_count; i++ )); do
      if [[ "${t_ids[$i]}" == "$dep" ]]; then
        dep_status="${t_statuses[$i]}"
        break
      fi
    done

    if [[ "$dep_status" != "completed" ]]; then
      if [[ -n "$incomplete" ]]; then
        incomplete="${incomplete},${dep}"
      else
        incomplete="${dep}"
      fi
    fi
  done

  if [[ -z "$incomplete" ]]; then
    echo "ready"
  else
    echo "blocked:${incomplete}"
  fi
}
