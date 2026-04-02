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

# --- Read dispatched_role from current.yaml (D-198: consolidated) ---
role=""
if [[ -f "$state_dir/current.yaml" ]]; then
  role=$(grep '^dispatched_role:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^dispatched_role:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

# No dispatched role = not a tracked pipeline dispatch
[[ -z "$role" || "$role" == "null" ]] && exit 0

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

# --- Clear dispatched_role from current.yaml (D-198: consolidated) ---
if [[ -f "$state_dir/current.yaml" ]]; then
  if grep -q '^dispatched_role:' "$state_dir/current.yaml" 2>/dev/null; then
    sed -i.bak 's|^dispatched_role:.*|dispatched_role: null|' "$state_dir/current.yaml" 2>/dev/null
    rm -f "$state_dir/current.yaml.bak" 2>/dev/null
  fi
fi

# --- Read budget state for injection ---
orch_pct="0"
warning_level="normal"
if [[ -f "$state_dir/current.yaml" ]]; then
  orch_pct=$(grep 'orchestrator_percent' "$state_dir/current.yaml" 2>/dev/null | head -1 | sed 's/.*orchestrator_percent:[[:space:]]*//' | tr -d '"' 2>/dev/null) || orch_pct="0"
  warning_level=$(grep 'warning_level' "$state_dir/current.yaml" 2>/dev/null | tail -1 | sed 's/.*warning_level:[[:space:]]*//' | tr -d '"' 2>/dev/null) || warning_level="normal"
fi

# ═══════════════════════════════════════════════════════════
# PASSIVE AUDITS (D-203) — automatic checks after specific agents
# ═══════════════════════════════════════════════════════════

passive_warnings=""

# --- Helper: trim whitespace (no xargs, no subshell per call) ---
_trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

# --- Helper: JSON-safe string escaping (handles \, ", newlines, tabs) ---
_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' '; }

# --- e1b: Knowledge drift check (after explorer) ---
if [[ "$role" == "explorer" ]]; then
  knowledge_summary="${state_dir%/state}/knowledge/project-model/summary.md"
  task_id=""
  if [[ -f "$state_dir/current.yaml" ]]; then
    task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  fi
  exploration_artifact=""
  if [[ -n "$task_id" && "$task_id" != "null" ]]; then
    exploration_artifact="$state_dir/tasks/$task_id/artifacts/exploration.md"
  fi

  if [[ -f "$knowledge_summary" && -f "$exploration_artifact" ]]; then
    # Extract key facts from knowledge summary (stack, language, framework lines)
    known_facts=$(grep -iE '^(language|framework|stack|database|runtime):' "$knowledge_summary" 2>/dev/null | head -10) || true
    if [[ -n "$known_facts" ]]; then
      drift_found=""
      while IFS=: read -r key rest; do
        key_clean=$(_trim "$(echo "$key" | tr '[:upper:]' '[:lower:]')") || continue
        value_clean=$(_trim "${rest# }") || continue
        [[ -z "$key_clean" || -z "$value_clean" ]] && continue
        # If the key appears in exploration but with different value, flag it
        # Use -F for fixed-string matching (no regex interpretation of dots, parens, etc.)
        exploration_mention=$(grep -iF "$key_clean" "$exploration_artifact" 2>/dev/null | head -1) || true
        if [[ -n "$exploration_mention" ]] && ! echo "$exploration_mention" | grep -qiF "$value_clean" 2>/dev/null; then
          drift_found="${drift_found}${key_clean}: known='${value_clean}'; "
        fi
      done <<< "$known_facts"

      if [[ -n "$drift_found" ]]; then
        passive_warnings="${passive_warnings}PASSIVE AUDIT (e1b): Knowledge drift detected -- ${drift_found%. }. Review .moira/knowledge/project-model/summary.md for accuracy. "
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"
        status_file="$state_dir/tasks/$task_id/status.yaml"
        if [[ -f "$status_file" ]]; then
          printf '\n  - type: knowledge_drift\n    detected_at: "%s"\n    details: "%s"' "$timestamp" "${drift_found:0:120}" >> "$status_file" 2>/dev/null || true
        fi
      fi
    fi
  fi
fi

# --- e1c: Convention drift check (after reviewer) ---
if [[ "$role" == "reviewer" ]]; then
  conventions_summary="${state_dir%/state}/knowledge/conventions/summary.md"
  task_id=""
  if [[ -f "$state_dir/current.yaml" ]]; then
    task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  fi
  review_artifact=""
  if [[ -n "$task_id" && "$task_id" != "null" ]]; then
    review_artifact="$state_dir/tasks/$task_id/artifacts/review.md"
  fi

  if [[ -f "$conventions_summary" && -f "$review_artifact" ]]; then
    review_findings=$(grep -iE '(convention|pattern|style|naming|format)' "$review_artifact" 2>/dev/null | head -5) || true
    if [[ -n "$review_findings" ]]; then
      undocumented=""
      while IFS= read -r finding; do
        [[ -z "$finding" ]] && continue
        key_term=$(echo "$finding" | grep -oE '[A-Za-z_]+Convention|[A-Za-z_]+Pattern|[A-Za-z_]+Style' 2>/dev/null | head -1) || true
        if [[ -n "$key_term" ]] && ! grep -qiF "$key_term" "$conventions_summary" 2>/dev/null; then
          undocumented="${undocumented}${key_term}; "
        fi
      done <<< "$review_findings"

      if [[ -n "$undocumented" ]]; then
        passive_warnings="${passive_warnings}PASSIVE AUDIT (e1c): Convention drift -- reviewer found patterns not in conventions doc: ${undocumented%. }. Consider updating .moira/knowledge/conventions/summary.md. "
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"
        status_file="$state_dir/tasks/$task_id/status.yaml"
        if [[ -f "$status_file" ]]; then
          printf '\n  - type: convention_drift\n    detected_at: "%s"\n    details: "%s"' "$timestamp" "${undocumented:0:120}" >> "$status_file" 2>/dev/null || true
        fi
      fi
    fi
  fi
fi

# --- d1: Agent guard check (after implementer) ---
if [[ "$role" == "implementer" ]]; then
  protected_violations=""
  if command -v git &>/dev/null; then
    project_root="${state_dir%/.moira/state}"
    # Use git status --porcelain (works on repos with no commits, consistent with snapshot)
    changed_files=$(cd "$project_root" 2>/dev/null && git status --porcelain 2>/dev/null | sed 's/^...//' | sort -u) || true
    if [[ -n "$changed_files" ]]; then
      while IFS= read -r changed; do
        [[ -z "$changed" ]] && continue
        case "$changed" in
          design/CONSTITUTION.md)
            protected_violations="${protected_violations}CRITICAL: design/CONSTITUTION.md modified; " ;;
          design/*)
            protected_violations="${protected_violations}design/ file modified: ${changed}; " ;;
          .moira/core/*|.moira/config/*)
            protected_violations="${protected_violations}system config modified: ${changed}; " ;;
          src/global/*)
            protected_violations="${protected_violations}Moira source modified: ${changed}; " ;;
        esac
      done <<< "$changed_files"
    fi
  fi

  if [[ -n "$protected_violations" ]]; then
    passive_warnings="${passive_warnings}GUARD CHECK (d1): Agent modified protected paths -- ${protected_violations%. }. Review changes before proceeding. "
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"
    echo "$timestamp AGENT_VIOLATION implementer ${protected_violations:0:200}" >> "$state_dir/violations.log" 2>/dev/null || true
  fi
fi

# --- Save git snapshot for workspace change detection (D-203 Change 4) ---
if command -v git &>/dev/null; then
  project_root="${project_root:-${state_dir%/.moira/state}}"
  (cd "$project_root" 2>/dev/null && git status --porcelain 2>/dev/null) > "$state_dir/.git-snapshot" 2>/dev/null || true
fi

# --- Inject completion summary via additionalContext ---
msg="AGENT DONE -- ${role}: ${agent_status} (${duration_sec}s). Budget: ${orch_pct}% (${warning_level}). Step: ${current_step}."
if [[ -n "$passive_warnings" ]]; then
  msg="${msg} ${passive_warnings}"
fi
msg_escaped=$(_json_escape "$msg") || exit 0
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStop\",\"additionalContext\":\"$msg_escaped\"}}"

exit 0
