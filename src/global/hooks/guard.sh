#!/usr/bin/env bash
# Guard hook — PostToolUse violation detection and audit logging (Layer 2, D-031)
# Fires after every tool call during a Moira session.
# MUST NOT fail — any error exits 0 silently.
# MUST be fast — no library sourcing, minimal forks.

# Read hook input from stdin
input=$(cat 2>/dev/null) || exit 0

# --- Parse JSON fields ---
# Try jq first, fall back to grep/sed
if command -v jq &>/dev/null; then
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
  if [[ -z "$file_path" ]]; then
    file_path=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || file_path=""
  fi
else
  # Fallback: grep-based extraction
  tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || tool_name=""
  file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || file_path=""
  if [[ -z "$file_path" ]]; then
    file_path=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || file_path=""
  fi
fi

# No tool name = nothing to do
[[ -z "$tool_name" ]] && exit 0

# --- Subagent bypass ---
# Guard boundaries apply ONLY to the orchestrator, not dispatched agents.
# agent_id is present only in subagent contexts.
if command -v jq &>/dev/null; then
  agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""
else
  agent_id=$(echo "$input" | grep -o '"agent_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_id"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_id=""
fi
[[ -n "$agent_id" ]] && exit 0

# --- Find Moira state directory ---
# Walk up from CWD looking for .claude/moira/state/current.yaml
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/moira/state/current.yaml" ]]; then
      echo "$dir/.claude/moira/state"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

state_dir=$(find_state_dir) || exit 0

# --- Guard activation check (design/subsystems/self-monitoring.md) ---
# Only enforce during active pipeline — .guard-active marker created by orchestrator
if [[ ! -f "$state_dir/.guard-active" ]]; then
  exit 0
fi

# --- Extract task_id from current.yaml (lightweight, no library sourcing) ---
task_id=""
if [[ -f "$state_dir/current.yaml" ]]; then
  task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

# --- Config check: hooks.guard_enabled ---
config_file="${state_dir%/state}/config.yaml"
if [[ -f "$config_file" ]]; then
  guard_val=$(grep 'guard_enabled' "$config_file" 2>/dev/null | head -1) || true
  if [[ "$guard_val" == *"false"* ]]; then
    exit 0
  fi
fi

# --- Timestamp ---
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"

# --- Log ALL tool usage (Art 3.1 audit trail) ---
echo "$timestamp $tool_name $file_path" >> "$state_dir/tool-usage.log" 2>/dev/null || true

# --- Violation detection ---
# Only check Read/Write/Edit (D-072: Grep/Glob blocked by allowed-tools, unobservable here)
case "$tool_name" in
  Read)
    # .ariadne/ is Ariadne graph output — orchestrator may check existence (D-105)
    # Read is allowed for both .claude/moira and .ariadne/ paths
    if [[ -n "$file_path" && "$file_path" != *".claude/moira"* && "$file_path" != *".ariadne/"* ]]; then
      # VIOLATION: orchestrator accessed project file directly
      if [[ -n "$task_id" ]]; then
        echo "$timestamp VIOLATION $tool_name $file_path task_id=$task_id" >> "$state_dir/violations.log" 2>/dev/null || true
      else
        echo "$timestamp VIOLATION $tool_name $file_path" >> "$state_dir/violations.log" 2>/dev/null || true
      fi

      # Inject warning into Claude context
      echo "{\"hookSpecificOutput\":{\"additionalContext\":\"CONSTITUTIONAL VIOLATION (Art 1.1): Orchestrator used $tool_name on $file_path. Direct project file operations are prohibited.\"}}"
    fi
    ;;
  Write|Edit)
    # Write/Edit only allowed within .claude/moira — .ariadne/ is written by ariadne CLI only
    if [[ -n "$file_path" && "$file_path" != *".claude/moira"* ]]; then
      # VIOLATION: orchestrator accessed project file directly
      if [[ -n "$task_id" ]]; then
        echo "$timestamp VIOLATION $tool_name $file_path task_id=$task_id" >> "$state_dir/violations.log" 2>/dev/null || true
      else
        echo "$timestamp VIOLATION $tool_name $file_path" >> "$state_dir/violations.log" 2>/dev/null || true
      fi

      # Inject warning into Claude context
      echo "{\"hookSpecificOutput\":{\"additionalContext\":\"CONSTITUTIONAL VIOLATION (Art 1.1): Orchestrator used $tool_name on $file_path. Direct project file operations are prohibited.\"}}"
    fi
    ;;
esac

exit 0
