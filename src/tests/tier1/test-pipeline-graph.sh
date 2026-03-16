#!/usr/bin/env bash
# test-pipeline-graph.sh — Graph-theoretic verification of pipeline YAML definitions
# Verifies: reachability, gate completeness, no gate bypass, fork/join balance,
# and error recovery reachability for all 4 pipeline types.
# Source: Constitution Art 2.2, design/architecture/pipelines.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPELINES_DIR="$SRC_DIR/global/core/pipelines"
LIB_DIR="$SRC_DIR/global/lib"
source "$LIB_DIR/yaml-utils.sh"

# ── Helper: extract step IDs from a pipeline YAML ────────────────────
# Returns newline-separated list of top-level step IDs in order.
# For repeatable_group steps, returns the parent step id only.
extract_step_ids() {
  local file="$1"
  awk '
  /^steps:/ { in_steps=1; next }
  in_steps && /^[a-z]/ { exit }
  in_steps && /^  - id:/ {
    sub(/^  - id:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    print
  }
  ' "$file"
}

# ── Helper: extract gate IDs and their after_step values ─────────────
# Output: "gate_id|after_step" per line
extract_gates() {
  local file="$1"
  awk '
  /^gates:/ { in_gates=1; next }
  in_gates && /^[a-z]/ { exit }
  in_gates && /^  - id:/ {
    sub(/^  - id:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    gate_id = $0
  }
  in_gates && /after_step:/ {
    sub(/.*after_step:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    gsub(/"/, "")
    print gate_id "|" $0
  }
  ' "$file"
}

# ── Helper: check if a step has mode: parallel ───────────────────────
step_is_parallel() {
  local file="$1"
  local step_id="$2"
  awk -v sid="$step_id" '
  /^steps:/ { in_steps=1; next }
  in_steps && /^[a-z]/ { exit }
  in_steps && /^  - id:/ {
    sub(/^  - id:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    current = $0
  }
  in_steps && current == sid && /mode:[[:space:]]*parallel/ { print "yes"; exit }
  ' "$file"
}

# ── Helper: count parallel agents for a step ─────────────────────────
count_parallel_agents() {
  local file="$1"
  local step_id="$2"
  awk -v sid="$step_id" '
  /^steps:/ { in_steps=1; next }
  in_steps && /^[a-z]/ { exit }
  in_steps && /^  - id:/ {
    sub(/^  - id:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    current = $0
    in_agents = 0
  }
  in_steps && current == sid && /agents:/ { in_agents = 1; next }
  in_steps && current == sid && in_agents && /- agent:/ { count++ }
  in_steps && /^  - id:/ && current != sid { in_agents = 0 }
  END { print count+0 }
  ' "$file"
}

# ── Helper: check if step has repeatable_group ───────────────────────
step_is_repeatable() {
  local file="$1"
  local step_id="$2"
  awk -v sid="$step_id" '
  /^steps:/ { in_steps=1; next }
  in_steps && /^[a-z]/ { exit }
  in_steps && /^  - id:/ {
    sub(/^  - id:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    current = $0
  }
  in_steps && current == sid && /repeatable_group:/ { print "yes"; exit }
  ' "$file"
}

# ── Helper: extract error handler entries ────────────────────────────
# Output: "error_code|action" per line
extract_error_handlers() {
  local file="$1"
  awk '
  /^error_handlers:/ { in_eh=1; next }
  in_eh && /^[a-z]/ && !/^  / { exit }
  in_eh && /^  E[0-9]/ {
    sub(/^  /, "")
    gsub(/:.*/, "")
    error_code = $0
  }
  in_eh && /action:[[:space:]]/ {
    sub(/.*action:[[:space:]]*/, "")
    gsub(/[[:space:]]/, "")
    print error_code "|" $0
  }
  ' "$file"
}

# ── Helper: BFS reachability check ───────────────────────────────────
# Given step IDs as a linear sequence, checks if last step is reachable
# from first step. Steps are connected sequentially (i -> i+1).
# Gates sit between steps; removing a gate means removing that edge.
# Args: step_list (space-separated), excluded_step (or "" for none)
# Returns 0 if last reachable from first, 1 otherwise.
bfs_reachable() {
  local steps="$1"
  local excluded="$2"
  local start=""
  local target=""

  # Build ordered list
  local ordered=""
  local count=0
  local IFS_SAVE="$IFS"
  IFS=' '
  for s in $steps; do
    if [ $count -eq 0 ]; then
      start="$s"
    fi
    target="$s"
    count=$((count + 1))
    ordered="$ordered $s"
  done
  IFS="$IFS_SAVE"

  if [ $count -le 1 ]; then
    return 0
  fi

  # BFS through sequential adjacency, skipping excluded
  local visited=""
  local queue="$start"

  while [ -n "$queue" ]; do
    local current=""
    # Dequeue first element
    IFS_SAVE="$IFS"
    IFS=' '
    local rest=""
    local first=true
    for q in $queue; do
      if $first; then
        current="$q"
        first=false
      else
        rest="$rest $q"
      fi
    done
    IFS="$IFS_SAVE"
    queue="${rest# }"

    # Skip if already visited
    case " $visited " in
      *" $current "*) continue ;;
    esac
    visited="$visited $current"

    # Check if we reached the target
    if [ "$current" = "$target" ]; then
      return 0
    fi

    # Find next step(s) in sequence
    local found_current=false
    IFS_SAVE="$IFS"
    IFS=' '
    for s in $ordered; do
      if $found_current; then
        # s is the next step after current
        if [ "$s" != "$excluded" ]; then
          case " $visited " in
            *" $s "*) ;;
            *) queue="$queue $s" ;;
          esac
        fi
        break
      fi
      if [ "$s" = "$current" ]; then
        found_current=true
      fi
    done
    IFS="$IFS_SAVE"
  done

  return 1
}

# ── Helper: find index of step in list ───────────────────────────────
step_index() {
  local target="$1"
  shift
  local idx=0
  for s in "$@"; do
    if [ "$s" = "$target" ]; then
      echo "$idx"
      return 0
    fi
    idx=$((idx + 1))
  done
  echo "-1"
  return 1
}

# ── Required gates per pipeline (Constitution Art 2.2) ───────────────
# Format: pipeline_name|gate_id_1,gate_id_2,...
REQUIRED_GATES_quick="classification_gate,final_gate"
REQUIRED_GATES_standard="classification_gate,architecture_gate,plan_gate,final_gate"
REQUIRED_GATES_full="classification_gate,architecture_gate,plan_gate,final_gate"
REQUIRED_GATES_decomposition="classification_gate,architecture_gate,decomposition_gate,final_gate"

# ═══════════════════════════════════════════════════════════════════════
# Test each pipeline
# ═══════════════════════════════════════════════════════════════════════

for pipeline in quick standard full decomposition; do
  PIPELINE_FILE="$PIPELINES_DIR/${pipeline}.yaml"

  # Get step IDs
  step_ids_nl=$(extract_step_ids "$PIPELINE_FILE")
  step_ids=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    step_ids="$step_ids $line"
  done <<EOF
$step_ids_nl
EOF
  step_ids="${step_ids# }"

  # Get first and last step
  first_step=""
  last_step=""
  step_count=0
  for s in $step_ids; do
    if [ $step_count -eq 0 ]; then
      first_step="$s"
    fi
    last_step="$s"
    step_count=$((step_count + 1))
  done

  # ── 1. Reachability: BFS from first step must reach completion ────
  if [ "$last_step" = "completion" ]; then
    if bfs_reachable "$step_ids" ""; then
      pass "${pipeline}: all steps reachable from ${first_step} to completion"
    else
      fail "${pipeline}: completion not reachable from ${first_step}"
    fi
  else
    fail "${pipeline}: last step is '${last_step}', expected 'completion'"
  fi

  # ── 2. Gate completeness: required gates present ──────────────────
  eval "required_gates_csv=\$REQUIRED_GATES_${pipeline}"
  IFS_SAVE="$IFS"
  IFS=','
  required_gates_list=""
  for g in $required_gates_csv; do
    required_gates_list="$required_gates_list $g"
  done
  IFS="$IFS_SAVE"
  required_gates_list="${required_gates_list# }"

  gate_data=$(extract_gates "$PIPELINE_FILE")
  actual_gate_ids=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    gid="${line%%|*}"
    actual_gate_ids="$actual_gate_ids $gid"
  done <<EOF
$gate_data
EOF

  gates_complete=true
  for rg in $required_gates_list; do
    case " $actual_gate_ids " in
      *" $rg "*)
        ;;
      *)
        fail "${pipeline}: required gate '${rg}' missing"
        gates_complete=false
        ;;
    esac
  done
  if $gates_complete; then
    pass "${pipeline}: all required gates present"
  fi

  # ── 2b. Gates are on the path from start to completion ────────────
  # Verify each required gate's after_step is actually in the step list
  gates_on_path=true
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    gid="${line%%|*}"
    after="${line#*|}"
    # Remove quotes from after_step if present (e.g., repeatable_group.testing)
    after=$(echo "$after" | tr -d '"')

    # Check if this is a required gate
    is_required=false
    for rg in $required_gates_list; do
      if [ "$rg" = "$gid" ]; then
        is_required=true
        break
      fi
    done
    $is_required || continue

    # For repeatable_group references, extract the parent step
    after_base="${after%%.*}"

    found=false
    for s in $step_ids; do
      if [ "$s" = "$after_base" ]; then
        found=true
        break
      fi
    done
    if ! $found; then
      fail "${pipeline}: gate '${gid}' references step '${after}' not in step list"
      gates_on_path=false
    fi
  done <<EOF
$gate_data
EOF
  if $gates_on_path; then
    pass "${pipeline}: all required gates reference valid steps"
  fi

  # ── 3. No gate bypass: removing gate step must block post-gate ────
  # For each required gate, verify the after_step is between
  # pre-gate and post-gate steps — there is no alternative path.
  # In a linear pipeline, this is guaranteed if the gate's after_step
  # is in the step list and the pipeline is sequential. We verify by
  # checking that removing the gate's after_step makes completion
  # unreachable from start.
  no_bypass=true
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    gid="${line%%|*}"
    after="${line#*|}"
    after=$(echo "$after" | tr -d '"')
    after_base="${after%%.*}"

    # Only check required gates
    is_required=false
    for rg in $required_gates_list; do
      if [ "$rg" = "$gid" ]; then
        is_required=true
        break
      fi
    done
    $is_required || continue

    # Skip if gate is on a repeatable_group sub-step (phase_gate, subtask_gate)
    # — these gate sub-steps within a group, not the linear pipeline path
    case "$after" in
      repeatable_group.*) continue ;;
    esac

    # Removing the gate's after_step should make completion unreachable
    if bfs_reachable "$step_ids" "$after_base"; then
      fail "${pipeline}: gate '${gid}' can be bypassed (completion reachable without '${after_base}')"
      no_bypass=false
    fi
  done <<EOF
$gate_data
EOF
  if $no_bypass; then
    pass "${pipeline}: no required gate can be bypassed"
  fi

  # ── 4. Fork/join balance: parallel steps have matching join ───────
  fork_join_ok=true
  fork_found=false
  prev_step=""
  for s in $step_ids; do
    is_parallel=$(step_is_parallel "$PIPELINE_FILE" "$s")
    if [ "$is_parallel" = "yes" ]; then
      fork_found=true
      agent_count=$(count_parallel_agents "$PIPELINE_FILE" "$s")
      if [ "$agent_count" -lt 2 ]; then
        fail "${pipeline}: parallel step '${s}' has < 2 agents ($agent_count)"
        fork_join_ok=false
      fi

      # Find the next step after this one — it should be the join point
      found_current=false
      next_step=""
      for ns in $step_ids; do
        if $found_current; then
          next_step="$ns"
          break
        fi
        if [ "$ns" = "$s" ]; then
          found_current=true
        fi
      done

      if [ -n "$next_step" ]; then
        # Next step should be sequential (foreground), serving as join point
        next_is_parallel=$(step_is_parallel "$PIPELINE_FILE" "$next_step")
        if [ "$next_is_parallel" = "yes" ]; then
          fail "${pipeline}: parallel step '${s}' followed by another parallel step '${next_step}' (no join point)"
          fork_join_ok=false
        else
          pass "${pipeline}: parallel step '${s}' (${agent_count} agents) joins at '${next_step}'"
        fi
      else
        fail "${pipeline}: parallel step '${s}' has no subsequent join step"
        fork_join_ok=false
      fi
    fi
  done

  if ! $fork_found; then
    # No parallel steps — that's fine (quick pipeline)
    pass "${pipeline}: no parallel steps (fork/join check not applicable)"
  fi

  # ── 5. Error recovery reachability ────────────────────────────────
  error_data=$(extract_error_handlers "$PIPELINE_FILE")
  error_recovery_ok=true
  error_count=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    error_code="${line%%|*}"
    action="${line#*|}"
    error_count=$((error_count + 1))

    # Each action must have a resolution path:
    # retry/retry_with_feedback → back to step (resolution: retry loop)
    # pause/stop → user interaction (resolution: user gate)
    # escalate/escalate_to_user/diagnose_and_escalate → user (resolution: user decision)
    # log/warn → non-blocking (resolution: continues)
    # auto_split/split_and_retry → automatic (resolution: system handles)
    # save_partial → partial save (resolution: spawn new agent)
    # retry_reduced_scope → automatic retry (resolution: retry loop)
    case "$action" in
      retry|retry_with_feedback|retry_reduced_scope)
        # Retry actions resolve back to the step — valid
        ;;
      pause|stop)
        # Blocking actions escalate to user — valid
        ;;
      escalate_to_user|escalate|diagnose_and_escalate)
        # Explicit escalation to user — valid
        ;;
      log|warn)
        # Non-blocking — continues pipeline — valid
        ;;
      auto_split|split_and_retry|save_partial)
        # Automatic resolution — valid
        ;;
      *)
        fail "${pipeline}: error '${error_code}' has unknown action '${action}'"
        error_recovery_ok=false
        ;;
    esac
  done <<EOF
$error_data
EOF

  if $error_recovery_ok && [ "$error_count" -gt 0 ]; then
    pass "${pipeline}: all ${error_count} error handlers have valid resolution paths"
  elif [ "$error_count" -eq 0 ]; then
    fail "${pipeline}: no error handlers found"
  fi

  # ── 5b. Error handlers with retry must have max_attempts ──────────
  retry_without_max=""
  current_error=""
  has_retry=false
  has_max=false

  while IFS= read -r line; do
    case "$line" in
      "  E"[0-9]*)
        # New error handler — check previous
        if $has_retry && ! $has_max && [ -n "$current_error" ]; then
          retry_without_max="$retry_without_max $current_error"
        fi
        current_error="${line%%:*}"
        current_error="${current_error#  }"
        has_retry=false
        has_max=false
        ;;
      *"action: retry"*|*"action: retry_with_feedback"*|*"action: retry_reduced_scope"*)
        has_retry=true
        ;;
      *"max_attempts:"*)
        has_max=true
        ;;
    esac
  done < <(awk '/^error_handlers:/,/^[a-z]/' "$PIPELINE_FILE" 2>/dev/null)

  # Check last error handler
  if $has_retry && ! $has_max && [ -n "$current_error" ]; then
    retry_without_max="$retry_without_max $current_error"
  fi

  retry_without_max="${retry_without_max# }"
  if [ -z "$retry_without_max" ]; then
    pass "${pipeline}: all retry error handlers have max_attempts"
  else
    fail "${pipeline}: retry handlers without max_attempts: ${retry_without_max}"
  fi

done

test_summary
