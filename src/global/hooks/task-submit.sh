#!/usr/bin/env bash
# Task Submit — UserPromptSubmit hook
# Auto-scaffolds task state when user invokes /moira:task.
# Runs BEFORE Claude processes the prompt, so orchestrator starts with state ready.
#
# Fires: UserPromptSubmit (no matcher — always fires)
# Sources: lib/task-init.sh
# Outputs: hookSpecificOutput.additionalContext with task_id
#
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Parse prompt from JSON input ---
if command -v jq &>/dev/null; then
  prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null) || prompt=""
else
  # Fallback: grep-based extraction (fragile for multi-line prompts)
  prompt=$(echo "$input" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || prompt=""
fi

[[ -z "$prompt" ]] && exit 0

# --- Detect /moira:resume invocation (D-216) ---
# Create .guard-active and .session-lock BEFORE LLM processes resume.md
if echo "$prompt" | grep -qiE '^\s*/moira[: ]resume\b'; then
  state_dir=""
  _dir="$PWD"
  while [[ "$_dir" != "/" ]]; do
    if [[ -d "$_dir/.moira/state" ]]; then
      state_dir="$_dir/.moira/state"
      break
    fi
    _dir=$(dirname "$_dir")
  done
  if [[ -n "$state_dir" && -f "$state_dir/current.yaml" ]]; then
    _step_status=$(grep '^step_status:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    if [[ "$_step_status" == "checkpointed" ]]; then
      # Activate guard enforcement for resumed pipeline
      touch "$state_dir/.guard-active" 2>/dev/null || true
      # Recreate session lock
      _task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
      printf 'pid: session\nstarted: %s\ntask_id: %s\nttl: 86400\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$_task_id" > "$state_dir/.session-lock" 2>/dev/null || true
    fi
  fi
  exit 0
fi

# --- Detect /moira:task invocation ---
# Match: /moira:task <description> or /moira task <description>
# The prompt from Skill invocation is the raw user input
if ! echo "$prompt" | grep -qiE '^\s*/moira[: ]task\b'; then
  exit 0
fi

# --- Extract description and size hint ---
# Strip the command prefix
description=$(echo "$prompt" | sed -E 's|^\s*/moira[: ]task\s*||i' 2>/dev/null) || description=""
[[ -z "$description" ]] && exit 0

# Check for size hint prefix
size_hint=""
case "$description" in
  small:*)  size_hint="small";  description="${description#small:}" ;;
  medium:*) size_hint="medium"; description="${description#medium:}" ;;
  large:*)  size_hint="large";  description="${description#large:}" ;;
  epic:*)   size_hint="epic";   description="${description#epic:}" ;;
esac
# Trim leading whitespace from description
description=$(echo "$description" | sed 's/^[[:space:]]*//' 2>/dev/null) || true
[[ -z "$description" ]] && exit 0

# --- Find Moira state directory ---
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.moira/state" ]]; then
      echo "$dir/.moira/state"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

state_dir=$(find_state_dir) || exit 0

# --- Check for existing active pipeline ---
if [[ -f "$state_dir/current.yaml" ]]; then
  existing_task=""
  existing_status=""
  if command -v jq &>/dev/null; then
    : # YAML, not JSON — use grep
  fi
  existing_task=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  existing_status=$(grep '^step_status:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true

  if [[ -n "$existing_task" && "$existing_task" != "null" && ( "$existing_status" == "in_progress" || "$existing_status" == "pending" ) ]]; then
    # Active pipeline — don't overwrite, let orchestrator handle
    exit 0
  fi
fi

# --- Error logging helper (D-229) ---
_log_error() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || ts="unknown"
  printf '%s task-submit: %s\n' "$ts" "$1" >> "$state_dir/errors.log" 2>/dev/null || true
}

# --- Source task-init and scaffold ---
moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
if [[ ! -f "$moira_home/lib/task-init.sh" ]]; then
  _log_error "task-init.sh not found at $moira_home/lib/task-init.sh"
  exit 0
fi

# shellcheck source=../lib/task-init.sh
if ! source "$moira_home/lib/task-init.sh" 2>/dev/null; then
  _log_error "failed to source task-init.sh"
  exit 0
fi

task_id=$(moira_task_init "$description" "$size_hint" "$state_dir" 2>/dev/null)
if [[ $? -ne 0 || -z "$task_id" ]]; then
  _log_error "moira_task_init failed for description='${description:0:80}'"
  exit 0
fi

# --- Collect preflight context (D-199) ---
preflight=""
if command -v moira_preflight_collect &>/dev/null; then
  preflight=$(moira_preflight_collect "$state_dir" 2>/dev/null) || preflight=""
fi

# --- Pre-assemble Apollo instruction file (D-200) ---
apollo_instruction=""
if [[ -f "$moira_home/lib/preflight-assemble.sh" ]]; then
  # shellcheck source=../lib/preflight-assemble.sh
  if ! source "$moira_home/lib/preflight-assemble.sh" 2>/dev/null; then
    _log_error "failed to source preflight-assemble.sh"
  elif command -v moira_preflight_assemble_apollo &>/dev/null; then
    apollo_instruction=$(moira_preflight_assemble_apollo "$task_id" "$state_dir" 2>&1) || {
      _log_error "preflight_assemble_apollo failed for task=$task_id"
      apollo_instruction=""
    }
  fi
fi

# --- Inject task_id + preflight into context ---
msg="MOIRA TASK INITIALIZED: task_id=${task_id}. State files pre-scaffolded by hook — skip Steps 2-7 of task.md. Proceed directly to Step 8 (load orchestrator skill)."

if [[ -n "$preflight" ]]; then
  msg="${msg}
MOIRA_PREFLIGHT:
${preflight}"
fi

# Escape for JSON string: backslashes, double quotes, newlines
msg_escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//' 2>/dev/null) || exit 0

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"$msg_escaped\"}}"

exit 0
