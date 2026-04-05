#!/usr/bin/env bash
# checkpoint.sh — Checkpoint management for interrupted task resume
# Creates, validates, and cleans up checkpoint manifests so that tasks
# interrupted by context limits, user pauses, or errors can be resumed
# with full context in a new session.
#
# Source: design/specs/2026-03-16-phase12-advanced-features.md, Task 2.1

set -euo pipefail

# Source yaml-utils from the same directory
_CHECKPOINT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_CHECKPOINT_DIR}/yaml-utils.sh"

# ── moira_checkpoint_create <task_id> <step> <reason> [state_dir] ────
# Create a checkpoint manifest for the given task at the current step.
# Captures git state, files modified, gate decisions, and resume context.
# Writes manifest.yaml to state/tasks/{task_id}/manifest.yaml.
moira_checkpoint_create() {
  local task_id="$1"
  local step="$2"
  local reason="$3"
  local state_dir="${4:-.moira/state}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local manifest_file="${task_dir}/manifest.yaml"
  local current_file="${state_dir}/current.yaml"
  local status_file="${task_dir}/status.yaml"

  if [[ ! -d "$task_dir" ]]; then
    echo "Error: task directory not found: $task_dir" >&2
    return 1
  fi

  # Validate reason
  case "$reason" in
    context_limit|user_pause|error|session_end) ;;
    *)
      echo "Error: invalid checkpoint reason '$reason' (must be context_limit/user_pause/error/session_end)" >&2
      return 1
      ;;
  esac

  # Read pipeline from current.yaml
  local pipeline="standard"
  if [[ -f "$current_file" ]]; then
    local p
    p=$(moira_yaml_get "$current_file" "pipeline" 2>/dev/null) || true
    pipeline=${p:-standard}
  fi

  # Read decisions_made from status.yaml gates block
  local decisions_made=""
  if [[ -f "$status_file" ]]; then
    local in_gates=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^gates: ]]; then
        in_gates=true
        continue
      fi
      if $in_gates && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
        break
      fi
      if $in_gates && [[ -n "$line" ]]; then
        if [[ -z "$decisions_made" ]]; then
          decisions_made="$line"
        else
          decisions_made="${decisions_made}"$'\n'"${line}"
        fi
      fi
    done < "$status_file"
  fi

  # Git state (warn if unavailable — resume validation depends on this)
  local git_branch=""
  git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true
  if [[ -z "$git_branch" ]]; then
    echo "Warning: git branch not available — resume validation will be limited" >&2
  fi

  local git_head=""
  git_head=$(git rev-parse HEAD 2>/dev/null) || true
  if [[ -z "$git_head" ]]; then
    echo "Warning: git HEAD not available — resume validation will be limited" >&2
  fi

  # Files modified since task start
  # Try to read pre-task HEAD from status.yaml for accurate diff
  local files_modified=""
  local pre_task_head=""
  if [[ -f "$status_file" ]]; then
    pre_task_head=$(moira_yaml_get "$status_file" "git.pre_task_head" 2>/dev/null) || true
  fi
  if [[ -n "$pre_task_head" && "$pre_task_head" != "null" ]]; then
    # Diff all changes (committed + staged + unstaged) since task start
    files_modified=$(git diff --name-only "$pre_task_head" 2>/dev/null) || true
  elif [[ -n "$git_head" ]]; then
    # Fallback: capture staged + unstaged changes against HEAD
    files_modified=$(git diff --name-only HEAD 2>/dev/null) || true
  fi

  # Build resume context
  local resume_context=""
  resume_context=$(moira_checkpoint_build_resume_context "$task_id" "$state_dir") || true

  # Timestamp
  local created_at
  created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Developer (from current.yaml or fallback)
  local developer="user"
  if [[ -f "$current_file" ]]; then
    local d
    d=$(moira_yaml_get "$current_file" "developer" 2>/dev/null) || true
    developer=${d:-user}
  fi

  # Write manifest.yaml
  cat > "$manifest_file" << EOF
task_id: "${task_id}"
pipeline: ${pipeline}
developer: "${developer}"
checkpoint:
  step: "${step}"
  batch: null
  created_at: "${created_at}"
  reason: ${reason}
resume_context: |
EOF

  # Append resume_context lines with proper indentation
  if [[ -n "$resume_context" ]]; then
    while IFS= read -r ctx_line; do
      echo "  ${ctx_line}" >> "$manifest_file"
    done <<< "$resume_context"
  else
    echo "  (none)" >> "$manifest_file"
  fi

  # Append decisions_made block
  if [[ -n "$decisions_made" ]]; then
    echo "decisions_made:" >> "$manifest_file"
    echo "$decisions_made" >> "$manifest_file"
  else
    echo "decisions_made: null" >> "$manifest_file"
  fi

  # Append files_modified block
  if [[ -n "$files_modified" ]]; then
    echo "files_modified:" >> "$manifest_file"
    while IFS= read -r f; do
      [[ -n "$f" ]] && echo "  - \"${f}\"" >> "$manifest_file"
    done <<< "$files_modified"
  else
    echo "files_modified: null" >> "$manifest_file"
  fi

  # Static/null fields
  echo "files_expected: null" >> "$manifest_file"
  echo "dependencies: null" >> "$manifest_file"

  # Validation block
  cat >> "$manifest_file" << EOF
validation:
  git_branch: "${git_branch}"
  git_head_at_checkpoint: "${git_head}"
  external_changes_expected: false
EOF

  echo "checkpoint_created: ${task_id} at ${step} (${reason})"
}

# ── moira_checkpoint_validate <task_id> [state_dir] ──────────────────
# Validate a checkpoint manifest against current repository state.
# Returns one of:
#   valid
#   inconsistent:{details}
#   branch_changed:{expected}:{actual}
#   external_changes:{file_list}
moira_checkpoint_validate() {
  local task_id="$1"
  local state_dir="${2:-.moira/state}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local manifest_file="${task_dir}/manifest.yaml"
  local current_file="${state_dir}/current.yaml"

  if [[ ! -f "$manifest_file" ]]; then
    echo "inconsistent:manifest_not_found"
    return 0
  fi

  # Check 1: Artifact existence for completed steps
  if [[ -f "$current_file" ]]; then
    local in_history=false
    local missing_artifacts=""
    while IFS= read -r line; do
      if [[ "$line" =~ ^history: ]]; then
        in_history=true
        continue
      fi
      if $in_history && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
        break
      fi
      if $in_history && [[ "$line" =~ "status: success" ]]; then
        # Extract step name from preceding line context
        # We track the current step as we iterate
        true
      fi
      if $in_history && [[ "$line" =~ "- step:" ]]; then
        local hist_step="${line#*step: }"
        hist_step="${hist_step## }"
        local hist_status=""
      fi
      if $in_history && [[ "$line" =~ "status:" && ! "$line" =~ "step_status:" ]]; then
        hist_status="${line#*status: }"
        hist_status="${hist_status## }"
        if [[ "$hist_status" == "success" && -n "${hist_step:-}" ]]; then
          local artifact_file="${task_dir}/${hist_step}.md"
          if [[ ! -f "$artifact_file" ]]; then
            if [[ -z "$missing_artifacts" ]]; then
              missing_artifacts="${hist_step}"
            else
              missing_artifacts="${missing_artifacts},${hist_step}"
            fi
          fi
        fi
      fi
    done < "$current_file"

    if [[ -n "$missing_artifacts" ]]; then
      echo "inconsistent:missing_artifacts:${missing_artifacts}"
      return 0
    fi
  fi

  # Check 2: Git branch
  local expected_branch
  expected_branch=$(moira_yaml_get "$manifest_file" "validation.git_branch" 2>/dev/null) || true

  local actual_branch
  actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || true

  if [[ -n "$expected_branch" && "$expected_branch" != "null" && "$expected_branch" != "$actual_branch" ]]; then
    echo "branch_changed:${expected_branch}:${actual_branch}"
    return 0
  fi

  # Check ancestry: current HEAD should be descendant of checkpoint HEAD
  local checkpoint_head
  checkpoint_head=$(moira_yaml_get "$manifest_file" "validation.git_head_at_checkpoint" 2>/dev/null) || true

  if [[ -n "$checkpoint_head" && "$checkpoint_head" != "null" ]]; then
    if ! git merge-base --is-ancestor "$checkpoint_head" HEAD 2>/dev/null; then
      echo "inconsistent:head_not_descendant_of_checkpoint"
      return 0
    fi

    # Check 3: External changes
    local external_expected
    external_expected=$(moira_yaml_get "$manifest_file" "validation.external_changes_expected" 2>/dev/null) || true
    external_expected=${external_expected:-false}

    local changed_files
    changed_files=$(git diff --name-only "$checkpoint_head" 2>/dev/null) || true

    if [[ -n "$changed_files" && "$external_expected" == "false" ]]; then
      # Collapse to comma-separated single line
      local file_list
      file_list=$(echo "$changed_files" | tr '\n' ',' | sed 's/,$//')
      echo "external_changes:${file_list}"
      return 0
    fi
  fi

  echo "valid"
}

# ── moira_checkpoint_build_resume_context <task_id> [state_dir] ──────
# Build a multi-line resume context summary (~200-500 tokens target).
# Reads status.yaml for gate decisions and current.yaml for step history.
# Output: "Task: {description}. Pipeline: {type}. Completed: {steps}.
#          Key decisions: {decisions}. Continue from: {step}."
moira_checkpoint_build_resume_context() {
  local task_id="$1"
  local state_dir="${2:-.moira/state}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local current_file="${state_dir}/current.yaml"
  local status_file="${task_dir}/status.yaml"

  # Read basic info from current.yaml
  local pipeline="unknown" current_step="unknown" description=""
  if [[ -f "$current_file" ]]; then
    local p s d
    p=$(moira_yaml_get "$current_file" "pipeline" 2>/dev/null) || true
    pipeline=${p:-unknown}
    s=$(moira_yaml_get "$current_file" "step" 2>/dev/null) || true
    current_step=${s:-unknown}
  fi

  # Read task description from status.yaml
  if [[ -f "$status_file" ]]; then
    local sd
    sd=$(moira_yaml_get "$status_file" "description" 2>/dev/null) || true
    description=${sd:-}
  fi
  description=${description:-"(no description)"}

  # Collect completed steps from history
  local completed_steps=""
  if [[ -f "$current_file" ]]; then
    local in_history=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^history: ]]; then
        in_history=true
        continue
      fi
      if $in_history && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
        break
      fi
      if $in_history && [[ "$line" =~ "- step:" ]]; then
        local h_step="${line#*step: }"
        h_step="${h_step## }"
        if [[ -z "$completed_steps" ]]; then
          completed_steps="${h_step}"
        else
          completed_steps="${completed_steps}, ${h_step}"
        fi
      fi
    done < "$current_file"
  fi
  completed_steps=${completed_steps:-"(none)"}

  # Collect key decisions from status.yaml gates
  local key_decisions=""
  if [[ -f "$status_file" ]]; then
    local in_gates=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^gates: ]]; then
        in_gates=true
        continue
      fi
      if $in_gates && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
        break
      fi
      if $in_gates && [[ "$line" =~ "gate:" ]]; then
        local gate_name="${line#*gate: }"
        gate_name="${gate_name## }"
      fi
      if $in_gates && [[ "$line" =~ "decision:" ]]; then
        local gate_decision="${line#*decision: }"
        gate_decision="${gate_decision## }"
        local entry="${gate_name:-?}=${gate_decision}"
        if [[ -z "$key_decisions" ]]; then
          key_decisions="${entry}"
        else
          key_decisions="${key_decisions}, ${entry}"
        fi
      fi
    done < "$status_file"
  fi
  key_decisions=${key_decisions:-"(none)"}

  # Build summary
  echo "Task: ${description}. Pipeline: ${pipeline}. Completed: ${completed_steps}. Key decisions: ${key_decisions}. Continue from: ${current_step}."
}

# ── moira_checkpoint_cleanup <task_id> [state_dir] ───────────────────
# Remove the checkpoint manifest for a completed/abandoned task.
moira_checkpoint_cleanup() {
  local task_id="$1"
  local state_dir="${2:-.moira/state}"

  local manifest_file="${state_dir}/tasks/${task_id}/manifest.yaml"
  rm -f "$manifest_file"
}
