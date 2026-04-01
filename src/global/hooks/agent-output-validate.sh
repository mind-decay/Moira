#!/usr/bin/env bash
# Agent Output Validate — SubagentStop hook
# Validates that agent output contains required STATUS line.
# BLOCK agent from stopping if response contract is violated.
# Part of Pipeline Compliance system (D-175).
#
# Fires: SubagentStop (matcher: empty — all agents)
# Reads: last_assistant_message from hook input
# Can output: decision=block to force agent to fix output format
#
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Prevent infinite loop ---
if command -v jq &>/dev/null; then
  stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
  last_msg=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null) || last_msg=""
  agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null) || agent_type=""
else
  stop_hook_active="false"
  echo "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null && stop_hook_active="true"
  last_msg=$(echo "$input" | grep -o '"last_assistant_message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"last_assistant_message"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || last_msg=""
  agent_type=$(echo "$input" | grep -o '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_type"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_type=""
fi

[[ "$stop_hook_active" == "true" ]] && exit 0

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
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

# --- Skip non-pipeline agent types ---
# Only validate general-purpose agents (pipeline agents)
# Built-in types like Explore, Plan have their own output formats
case "$agent_type" in
  Explore|Plan|Bash|"") exit 0 ;;  # built-in or unknown type
  general-purpose|*) ;; # pipeline agents — validate
esac

# --- Validate: response must contain STATUS line ---
[[ -z "$last_msg" ]] && exit 0

# Check for STATUS: line (case-insensitive, at start of a line or after newline)
if echo "$last_msg" | grep -qi 'STATUS:'; then
  exit 0  # STATUS line found — valid
fi

# STATUS line missing — BLOCK agent to fix output
echo "{\"decision\":\"block\",\"reason\":\"RESPONSE CONTRACT VIOLATION: Your response must end with the required format: STATUS: success|failure|blocked|budget_exceeded, SUMMARY: <text>, ARTIFACTS: [<files>], NEXT: <step>. Add these lines now.\"}"
exit 0
