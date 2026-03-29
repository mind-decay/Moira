#!/usr/bin/env bash
# Agent Done — SubagentStop hook
# Records agent completion in current.yaml (history, budget) automatically.
# Replaces manual orchestrator Read/Write cycles for agent completion tracking.
# Part of State Automation (D-178).
#
# Fires: SubagentStop (matcher: empty — all agents)
# Reads: pipeline-tracker.state (dispatched_role from pipeline-dispatch.sh)
# Writes: current.yaml (history, budget via state.sh), status.yaml (budget via budget.sh)
# Outputs: hookSpecificOutput.additionalContext with budget state
#
# Runs in PARALLEL with agent-output-validate.sh — no file write conflicts.
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Parse JSON fields ---
if command -v jq &>/dev/null; then
  stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
  agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null) || agent_type=""
  last_msg=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null) || last_msg=""
else
  stop_hook_active="false"
  echo "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null && stop_hook_active="true"
  agent_type=$(echo "$input" | grep -o '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_type"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_type=""
  last_msg=$(echo "$input" | grep -o '"last_assistant_message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"last_assistant_message"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || last_msg=""
fi

# Allow re-entry: agent-done must still record completion after agent-output-validate
# blocks and the agent retries. Only agent-output-validate.sh skips on re-entry.

# Skip built-in agent types
case "$agent_type" in
  Explore|Plan|Bash|"") exit 0 ;;
esac

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
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

# --- Read dispatched_role from tracker ---
tracker_file="$state_dir/pipeline-tracker.state"
role=""
if [[ -f "$tracker_file" ]]; then
  role=$(grep '^dispatched_role=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
fi

# No dispatched role = not a tracked pipeline dispatch
[[ -z "$role" ]] && exit 0

# Skip non-pipeline roles
case "$role" in
  reflector|auditor) exit 0 ;;
esac

# --- Read current step from current.yaml ---
current_step=""
step_started=""
if [[ -f "$state_dir/current.yaml" ]]; then
  current_step=$(grep '^step:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  step_started=$(grep '^step_started_at:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step_started_at:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

[[ -z "$current_step" ]] && exit 0

# --- Extract STATUS and SUMMARY from agent output ---
agent_status="success"  # default
agent_summary="(no summary)"

if [[ -n "$last_msg" ]]; then
  # Extract STATUS: line
  parsed_status=$(echo "$last_msg" | grep -oiE 'STATUS:[[:space:]]*(success|failure|blocked|budget_exceeded)' | head -1 | sed 's/STATUS:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' 2>/dev/null) || true
  if [[ -n "$parsed_status" ]]; then
    agent_status="$parsed_status"
  fi

  # Extract SUMMARY: line (take first 80 chars)
  parsed_summary=$(echo "$last_msg" | grep -oiE 'SUMMARY:[[:space:]]*.*' | head -1 | sed 's/SUMMARY:[[:space:]]*//' 2>/dev/null) || true
  if [[ -n "$parsed_summary" ]]; then
    agent_summary="${parsed_summary:0:80}"
  fi
fi

# --- Compute duration ---
duration_sec=0
if [[ -n "$step_started" && "$step_started" != "null" ]]; then
  now_epoch=$(date -u +%s 2>/dev/null) || now_epoch=0
  # Parse ISO 8601 timestamp
  start_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$step_started" +%s 2>/dev/null) || {
    # Linux fallback
    start_epoch=$(date -d "$step_started" +%s 2>/dev/null) || start_epoch=0
  }
  if [[ "$start_epoch" -gt 0 && "$now_epoch" -gt 0 ]]; then
    duration_sec=$(( now_epoch - start_epoch ))
    # Sanity check — cap at 1 hour
    [[ "$duration_sec" -gt 3600 ]] && duration_sec=3600
    [[ "$duration_sec" -lt 0 ]] && duration_sec=0
  fi
fi

# --- Record agent completion via state.sh ---
moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
if [[ -f "$moira_home/lib/state.sh" ]]; then
  # shellcheck source=../lib/state.sh
  source "$moira_home/lib/state.sh" 2>/dev/null || exit 0

  # Escape summary for YAML (replace double quotes)
  safe_summary=$(echo "$agent_summary" | sed 's/"/\\"/g' 2>/dev/null) || safe_summary="$agent_summary"

  if type moira_state_agent_done &>/dev/null; then
    moira_state_agent_done "$current_step" "$role" "$agent_status" "$duration_sec" "0" "$safe_summary" "$state_dir" 2>/dev/null || true
  fi
fi

# --- Clear dispatched_role from tracker ---
if [[ -f "$tracker_file" ]]; then
  grep -v '^dispatched_role=' "$tracker_file" > "${tracker_file}.tmp" 2>/dev/null || true
  mv "${tracker_file}.tmp" "$tracker_file" 2>/dev/null || true
fi

# --- Read budget state for injection ---
orch_pct="0"
warning_level="normal"
if [[ -f "$state_dir/current.yaml" ]]; then
  orch_pct=$(grep 'orchestrator_percent' "$state_dir/current.yaml" 2>/dev/null | head -1 | sed 's/.*orchestrator_percent:[[:space:]]*//' | tr -d '"' 2>/dev/null) || orch_pct="0"
  warning_level=$(grep 'warning_level' "$state_dir/current.yaml" 2>/dev/null | tail -1 | sed 's/.*warning_level:[[:space:]]*//' | tr -d '"' 2>/dev/null) || warning_level="normal"
fi

# --- Inject completion summary via additionalContext ---
msg="AGENT DONE — ${role}: ${agent_status} (${duration_sec}s). Budget: ${orch_pct}% (${warning_level}). Step: ${current_step}."
msg_escaped=$(echo "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || exit 0
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStop\",\"additionalContext\":\"$msg_escaped\"}}"

exit 0
