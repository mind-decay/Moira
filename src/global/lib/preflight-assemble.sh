#!/usr/bin/env bash
# preflight-assemble.sh — Pre-planning instruction file assembly
# Generates instruction files for pre-planning agents before orchestrator dispatches them.
# D-200: Unified instruction file mechanism for all agents.
#
# Called by:
#   - task-submit.sh: moira_preflight_assemble_apollo() — at task init
#   - pipeline-dispatch.sh: moira_preflight_assemble_exploration() — at Hermes/Athena dispatch

set -euo pipefail

_MOIRA_PREFLIGHT_ASSEMBLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"

# Source rules.sh (provides moira_rules_assemble_instruction)
# shellcheck source=rules.sh
source "${_MOIRA_PREFLIGHT_ASSEMBLE_LIB_DIR}/rules.sh" 2>/dev/null || {
  echo "Error: cannot source rules.sh" >&2
  return 1 2>/dev/null || exit 1
}

# ── moira_preflight_assemble_apollo <task_id> <state_dir> ──────────────
# Assemble instruction file for Apollo (classifier) at task init.
# Apollo needs: role definition, base rules, response contract, task input.
# No prior artifacts needed (first agent in pipeline).
moira_preflight_assemble_apollo() {
  local task_id="$1"
  local state_dir="$2"
  local moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local output_path="${task_dir}/instructions/apollo.md"
  local role_file="${moira_home}/core/rules/roles/apollo.yaml"
  local base_file="${moira_home}/core/rules/base.yaml"
  local task_context="${task_dir}/input.md"
  local project_rules_dir="${state_dir}/../config/rules"
  local knowledge_dir="${state_dir}/../knowledge"
  local matrix_file="${moira_home}/core/rules/knowledge-matrix.yaml"

  # Validate required files
  if [[ ! -f "$role_file" ]]; then
    echo "Warning: apollo.yaml not found at ${role_file}" >&2
    return 1
  fi
  if [[ ! -f "$base_file" ]]; then
    echo "Warning: base.yaml not found at ${base_file}" >&2
    return 1
  fi
  if [[ ! -f "$task_context" ]]; then
    echo "Warning: input.md not found at ${task_context}" >&2
    return 1
  fi

  # Create instructions directory
  mkdir -p "${task_dir}/instructions"

  # Assemble instruction using existing rules.sh function
  moira_rules_assemble_instruction \
    "$output_path" \
    "apollo" \
    "$base_file" \
    "$role_file" \
    "$project_rules_dir" \
    "$knowledge_dir" \
    "$task_context" \
    "$matrix_file" 2>/dev/null

  if [[ $? -eq 0 && -f "$output_path" && -s "$output_path" ]]; then
    echo "$output_path"
    return 0
  else
    # Cleanup empty/failed file
    rm -f "$output_path" 2>/dev/null || true
    return 1
  fi
}

# ── moira_preflight_assemble_agent <agent_name> <task_id> <state_dir> ──
# Assemble instruction file for any pre-planning agent.
# Uses classification.md as additional context if available.
moira_preflight_assemble_agent() {
  local agent_name="$1"
  local task_id="$2"
  local state_dir="$3"
  local moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"

  local task_dir="${state_dir}/tasks/${task_id}"
  local output_path="${task_dir}/instructions/${agent_name}.md"
  local role_file="${moira_home}/core/rules/roles/${agent_name}.yaml"
  local base_file="${moira_home}/core/rules/base.yaml"
  local project_rules_dir="${state_dir}/../config/rules"
  local knowledge_dir="${state_dir}/../knowledge"
  local matrix_file="${moira_home}/core/rules/knowledge-matrix.yaml"

  # Build task context: input.md + classification.md if available
  local task_context="${task_dir}/input.md"
  local combined_context="${task_dir}/instructions/.${agent_name}-context.tmp"

  if [[ ! -f "$role_file" || ! -f "$base_file" || ! -f "$task_context" ]]; then
    return 1
  fi

  mkdir -p "${task_dir}/instructions"

  # Combine input + classification as task context
  cat "$task_context" > "$combined_context" 2>/dev/null || return 1
  if [[ -f "${task_dir}/classification.md" ]]; then
    printf '\n---\n\n' >> "$combined_context"
    cat "${task_dir}/classification.md" >> "$combined_context" 2>/dev/null || true
  fi

  moira_rules_assemble_instruction \
    "$output_path" \
    "$agent_name" \
    "$base_file" \
    "$role_file" \
    "$project_rules_dir" \
    "$knowledge_dir" \
    "$combined_context" \
    "$matrix_file" 2>/dev/null

  local rc=$?

  # Cleanup temp file
  rm -f "$combined_context" 2>/dev/null || true

  if [[ $rc -eq 0 && -f "$output_path" && -s "$output_path" ]]; then
    echo "$output_path"
    return 0
  else
    rm -f "$output_path" 2>/dev/null || true
    return 1
  fi
}

# ── moira_preflight_assemble_exploration <task_id> <state_dir> ─────────
# Assemble instruction files for Hermes (explorer) and optionally Athena (analyst).
# Called after classification gate — classification.md exists.
moira_preflight_assemble_exploration() {
  local task_id="$1"
  local state_dir="$2"
  local assembled=""

  # Always assemble Hermes
  local hermes_path
  hermes_path=$(moira_preflight_assemble_agent "hermes" "$task_id" "$state_dir" 2>/dev/null) || true
  if [[ -n "$hermes_path" ]]; then
    assembled="hermes"
  fi

  # Athena: only if role file exists (may not be dispatched in all pipelines)
  local athena_path
  athena_path=$(moira_preflight_assemble_agent "athena" "$task_id" "$state_dir" 2>/dev/null) || true
  if [[ -n "$athena_path" ]]; then
    assembled="${assembled:+$assembled,}athena"
  fi

  if [[ -n "$assembled" ]]; then
    echo "$assembled"
    return 0
  fi
  return 1
}
