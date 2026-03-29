#!/usr/bin/env bash
# Guard Prevent — PreToolUse hook for Read/Write boundary enforcement
# DENY orchestrator access to project files outside .claude/moira/ and .ariadne/
# Upgrades guard.sh from detection (PostToolUse) to prevention (PreToolUse).
# Part of Pipeline Compliance system (D-175).
#
# Fires: PreToolUse (matcher: Read|Write)
# Can output: permissionDecision=deny to block file access
#
# guard.sh (PostToolUse) remains for audit logging — this hook adds blocking.
# MUST NOT fail — exits 0 silently on any error.
# MUST be fast — no library sourcing, minimal forks.

input=$(cat 2>/dev/null) || exit 0

# --- Parse JSON fields ---
if command -v jq &>/dev/null; then
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
else
  tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || tool_name=""
  file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || file_path=""
fi

# Only process Read and Write
case "$tool_name" in
  Read|Write) ;;
  *) exit 0 ;;
esac

[[ -z "$file_path" ]] && exit 0

# --- Find Moira state directory ---
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

# Only during active pipeline
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

# --- Config check: hooks.guard_enabled ---
config_file="${state_dir%/state}/config.yaml"
if [[ -f "$config_file" ]]; then
  guard_val=$(grep 'guard_enabled' "$config_file" 2>/dev/null | head -1) || true
  if [[ "$guard_val" == *"false"* ]]; then
    exit 0
  fi
fi

# --- Allowed paths ---
# .claude/moira/ — orchestrator state/config (read+write)
# .ariadne/ — graph data (read only, D-105)
# ~/.claude/moira/ — global core/skills/hooks (read only)
case "$file_path" in
  *".claude/moira"*)  exit 0 ;; # project-local moira state — allowed
  *".ariadne/"*)
    case "$tool_name" in
      Read) exit 0 ;; # read graph data — allowed
      Write)
        # Writing to .ariadne/ is only for ariadne CLI, not orchestrator
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION (Art 1.2): Orchestrator cannot write to .ariadne/ — only Ariadne CLI writes graph data.\"}}"
        exit 0
        ;;
    esac
    ;;
  "$HOME/.claude/moira/"*|"$HOME/.claude/moira"*)
    case "$tool_name" in
      Read) exit 0 ;; # read global core definitions — allowed
      Write)
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION: Orchestrator cannot write to global Moira installation (~/.claude/moira/). Global files are read-only.\"}}"
        exit 0
        ;;
    esac
    ;;
esac

# Any other path — DENY
local_escaped=$(echo "$file_path" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || local_escaped="$file_path"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION (Art 1.1): Orchestrator cannot $tool_name project file $local_escaped. Use agents for project file operations. Dispatch Hermes (explorer) to read or Hephaestus (implementer) to write.\"}}"
exit 0
