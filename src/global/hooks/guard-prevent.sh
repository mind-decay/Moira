#!/usr/bin/env bash
# Guard Prevent — PreToolUse hook for Read/Write/Edit/Bash boundary enforcement
# DENY orchestrator access to project files outside .moira/ and .ariadne/
# Upgrades guard.sh from detection (PostToolUse) to prevention (PreToolUse).
# Part of Pipeline Compliance system (D-175). Bash boundary added D-203.
#
# Fires: PreToolUse (matcher: Read|Write|Edit|Bash)
# Can output: permissionDecision=deny to block file access or Bash commands
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

# Only process Read, Write, Edit, and Bash
case "$tool_name" in
  Read|Write|Edit) ;;
  Bash) ;; # handled separately below
  *) exit 0 ;;
esac

# --- Subagent bypass ---
# Dispatched agents (Hermes, Hephaestus, etc.) MUST access project files.
# Orchestrator boundaries apply ONLY to the top-level session.
# agent_id is present only in subagent contexts.
if command -v jq &>/dev/null; then
  agent_id=$(echo "$input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""
else
  agent_id=$(echo "$input" | grep -o '"agent_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_id"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_id=""
fi
[[ -n "$agent_id" ]] && exit 0

# --- Find Moira state directory ---
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.moira/state/current.yaml" ]]; then
      echo "$dir/.moira/state"
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

# ═══════════════════════════════════════════════════════════
# BASH BOUNDARY (D-203) — orchestrator can only Bash on .moira/
# ═══════════════════════════════════════════════════════════
if [[ "$tool_name" == "Bash" ]]; then
  # Parse command from tool_input
  bash_command=""
  if command -v jq &>/dev/null; then
    bash_command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || bash_command=""
  else
    bash_command=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || bash_command=""
  fi

  # Unparseable command — allow silently (jq/fallback both failed)
  [[ -z "$bash_command" ]] && exit 0

  # Allow Bash commands that operate on .moira/ paths.
  # Known limitation: compound commands like "cat .moira/x && rm /tmp/y" are allowed
  # because we match the whole string. Full command parsing is out of scope.
  if echo "$bash_command" | grep -qE '\.moira(/|[[:space:]]|$)' 2>/dev/null; then
    exit 0
  fi

  # Deny all other Bash commands — orchestrator must dispatch agents
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"
  cmd_short="${bash_command:0:80}"
  echo "$timestamp DENIED Bash \"$cmd_short\" " >> "$state_dir/violations.log" 2>/dev/null || true

  cmd_escaped=$(echo "$cmd_short" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || cmd_escaped="$cmd_short"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION (Art 1.1, D-203): Orchestrator cannot run Bash commands on project. Command: '${cmd_escaped}'. Dispatch Hephaestus (implementer) for build/test/lint or Hermes (explorer) for information gathering.\"}}"
  exit 0
fi

# For Read/Write/Edit — need file_path
[[ -z "$file_path" ]] && exit 0

# --- Allowed paths ---
# .moira/ — orchestrator state/config (read+write)
# .ariadne/ — graph data (read only, D-105)
# ~/.claude/moira/ — global core/skills/hooks (read only)
case "$file_path" in
  *".moira"*)  exit 0 ;; # project-local moira state — allowed
  *".claude/"*)
    case "$tool_name" in
      Read) exit 0 ;; # read Claude Code config — allowed
      Write|Edit)
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION: Orchestrator cannot write to .claude/ — Claude Code config is read-only for orchestrator.\"}}"
        exit 0
        ;;
    esac
    ;;
  *".ariadne/"*)
    case "$tool_name" in
      Read) exit 0 ;; # read graph data — allowed
      Write|Edit)
        # Writing to .ariadne/ is only for ariadne CLI, not orchestrator
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION (Art 1.2): Orchestrator cannot write to .ariadne/ — only Ariadne CLI writes graph data.\"}}"
        exit 0
        ;;
    esac
    ;;
  "$HOME/.claude/moira/"*)
    case "$tool_name" in
      Read) exit 0 ;; # read global core definitions — allowed
      Write|Edit)
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION: Orchestrator cannot write to global Moira installation (~/.claude/moira/). Global files are read-only.\"}}"
        exit 0
        ;;
    esac
    ;;
esac

# Any other path — DENY and log
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"
echo "$timestamp DENIED $tool_name $file_path" >> "$state_dir/violations.log" 2>/dev/null || true

local_escaped=$(echo "$file_path" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || local_escaped="$file_path"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"BOUNDARY VIOLATION (Art 1.1): Orchestrator cannot $tool_name project file $local_escaped. Use agents for project file operations. Dispatch Hermes (explorer) to read or Hephaestus (implementer) to write.\"}}"
exit 0
