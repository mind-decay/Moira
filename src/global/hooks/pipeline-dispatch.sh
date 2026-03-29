#!/usr/bin/env bash
# Pipeline Dispatch — PreToolUse hook for Agent dispatches
# Validates dispatches against per-pipeline transition tables AND
# auto-writes step transitions to current.yaml.
# Replaces pipeline-compliance.sh (D-175) + adds step-transition (D-178).
#
# Three enforcement layers:
#   L1: review_pending — implementer MUST be followed by reviewer
#   L2: test_pending — reviewer MUST be followed by tester (when pipeline has testing)
#   L3: Transition table — each role can only transition to specific next roles per pipeline
#
# After validation passes:
#   - Writes dispatched_role to pipeline-tracker.state (for agent-done.sh)
#   - Writes step transition to current.yaml via state.sh
#
# Fires: PreToolUse (matcher: Agent)
# Reads: .claude/moira/state/pipeline-tracker.state
# Writes: .claude/moira/state/current.yaml (step transition), pipeline-tracker.state (dispatched_role)
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Parse JSON fields ---
if command -v jq &>/dev/null; then
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
  description=$(echo "$input" | jq -r '.tool_input.description // empty' 2>/dev/null) || description=""
  run_in_bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null) || run_in_bg="false"
else
  tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || tool_name=""
  description=$(echo "$input" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"description"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || description=""
  run_in_bg="false"
  echo "$input" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true' 2>/dev/null && run_in_bg="true"
fi

[[ "$tool_name" != "Agent" ]] && exit 0
[[ "$run_in_bg" == "true" ]] && exit 0

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

# --- Extract agent role from description ---
# Moira format: "Name (role) — description"
role=$(echo "$description" | grep -oE '\([a-z_]+\)' | head -1 | tr -d '()' 2>/dev/null) || true
[[ -z "$role" ]] && exit 0

# Always-allowed roles (outside pipeline step sequence)
case "$role" in
  reflector|auditor) exit 0 ;;
esac

# --- Read tracker state ---
tracker_file="$state_dir/pipeline-tracker.state"

pipeline=""
last_role=""
review_pending="false"
test_pending="false"
subtask_mode="false"
current_subtask=""
if [[ -f "$tracker_file" ]]; then
  pipeline=$(grep '^pipeline=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
  subtask_mode=$(grep '^subtask_mode=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
  current_subtask=$(grep '^current_subtask=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true

  # Per-subtask state isolation: in decomposition subtask mode, read from per-subtask file
  if [[ "$subtask_mode" == "true" && -n "$current_subtask" ]]; then
    subtask_file="$state_dir/pipeline-tracker-sub-${current_subtask}.state"
    if [[ -f "$subtask_file" ]]; then
      last_role=$(grep '^last_role=' "$subtask_file" 2>/dev/null | cut -d= -f2) || true
      review_pending=$(grep '^review_pending=' "$subtask_file" 2>/dev/null | cut -d= -f2) || true
      test_pending=$(grep '^test_pending=' "$subtask_file" 2>/dev/null | cut -d= -f2) || true
    fi
  else
    last_role=$(grep '^last_role=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
    review_pending=$(grep '^review_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
    test_pending=$(grep '^test_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
  fi
fi

# If no tracker yet, read pipeline from current.yaml
if [[ -z "$pipeline" || "$pipeline" == "null" ]]; then
  if [[ -f "$state_dir/current.yaml" ]]; then
    pipeline=$(grep '^pipeline:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^pipeline:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  fi
fi

# No pipeline = probably first dispatch (classifier) — allow and write transition
[[ -z "$pipeline" || "$pipeline" == "null" ]] && {
  # Write dispatched_role for agent-done.sh
  if [[ -n "$state_dir" ]]; then
    echo "dispatched_role=$role" >> "$tracker_file" 2>/dev/null || true
  fi
  exit 0
}

# --- Helper: output DENY ---
deny() {
  local reason="$1"
  local escaped
  escaped=$(echo "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || escaped="$reason"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$escaped\"}}"
  exit 0
}

# ═══════════════════════════════════════════════════════════
# LAYER 1: review_pending — implementer must be followed by reviewer
# ═══════════════════════════════════════════════════════════
if [[ "$review_pending" == "true" ]]; then
  case "$role" in
    reviewer)       ;; # correct — review happening
    implementer)
      case "$pipeline" in
        standard)   ;; # standard allows batched implementation
        *)          deny "PIPELINE COMPLIANCE: Review pending. Dispatch Themis (reviewer) before another Hephaestus (implementer)." ;;
      esac ;;
    architect|planner) ;; # error recovery (rearchitect/replan) — resets review_pending via tracker
    *) deny "PIPELINE COMPLIANCE: Review pending. Dispatch Themis (reviewer) before $role." ;;
  esac
fi

# ═══════════════════════════════════════════════════════════
# LAYER 2: test_pending — reviewer must be followed by tester
# ═══════════════════════════════════════════════════════════
if [[ "$test_pending" == "true" ]]; then
  case "$role" in
    tester)             ;; # correct — testing happening
    reviewer)           ;; # reviewer retry
    implementer)        ;; # re-implementation after review findings (E5 quality retry)
    architect|planner)  ;; # error recovery
    *) deny "PIPELINE COMPLIANCE: Testing pending. Dispatch Aletheia (tester) before $role." ;;
  esac
fi

# ═══════════════════════════════════════════════════════════
# LAYER 3: Per-pipeline transition table
# ═══════════════════════════════════════════════════════════

# Only validate if we have a last_role (not first dispatch)
if [[ -n "$last_role" ]]; then
  # Same role = retry — always valid
  [[ "$last_role" == "$role" ]] || {
    # Architect and planner are re-entry points for error recovery
    [[ "$role" == "architect" || "$role" == "planner" ]] || {
      # Determine effective pipeline for transition lookup
      effective_pipeline="$pipeline"
      if [[ "$pipeline" == "decomposition" && "$subtask_mode" == "true" ]]; then
        effective_pipeline="decomposition_sub"
      fi

      valid=""
      case "$effective_pipeline:$last_role" in
        quick:classifier)             valid="explorer" ;;
        quick:explorer)               valid="implementer" ;;
        quick:implementer)            valid="reviewer" ;;
        quick:reviewer)               valid="implementer" ;;
        standard:classifier)          valid="explorer,analyst" ;;
        standard:explorer)            valid="architect,analyst" ;;
        standard:analyst)             valid="architect,explorer" ;;
        standard:architect)           valid="planner" ;;
        standard:planner)             valid="implementer" ;;
        standard:implementer)         valid="implementer,reviewer" ;;
        standard:reviewer)            valid="tester,implementer" ;;
        standard:tester)              valid="implementer" ;;
        full:classifier)              valid="explorer,analyst" ;;
        full:explorer)                valid="architect,analyst" ;;
        full:analyst)                 valid="architect,explorer" ;;
        full:architect)               valid="planner" ;;
        full:planner)                 valid="implementer" ;;
        full:implementer)             valid="reviewer" ;;
        full:reviewer)                valid="tester,implementer" ;;
        full:tester)                  valid="implementer,tester" ;;
        decomposition:classifier)     valid="analyst" ;;
        decomposition:analyst)        valid="architect" ;;
        decomposition:architect)      valid="planner" ;;
        decomposition:planner)        valid="classifier,tester" ;;
        decomposition:tester)         valid="TERMINAL" ;;
        decomposition_sub:classifier) valid="explorer,analyst" ;;
        decomposition_sub:explorer)   valid="architect,analyst" ;;
        decomposition_sub:analyst)    valid="architect,explorer" ;;
        decomposition_sub:architect)  valid="planner" ;;
        decomposition_sub:planner)    valid="implementer" ;;
        decomposition_sub:implementer) valid="reviewer" ;;
        decomposition_sub:reviewer)   valid="tester,classifier,implementer" ;;
        decomposition_sub:tester)     valid="classifier,tester" ;;
        analytical:classifier)        valid="explorer" ;;
        analytical:explorer)          valid="analyst" ;;
        analytical:analyst)           valid="architect,explorer,analyst" ;;
        analytical:analytical_primary) valid="reviewer" ;;
        analytical:analytical_organizer) valid="scribe" ;;
        analytical:architect)         valid="analyst,reviewer,scribe" ;;
        analytical:reviewer)          valid="analyst,architect,analytical_organizer,scribe" ;;
        analytical:scribe)            valid="reviewer" ;;
        *) ;; # Unknown state — allow
      esac

      # TERMINAL = explicit dead end (deny all non-recovery transitions)
      if [[ "$valid" == "TERMINAL" ]]; then
        deny "PIPELINE COMPLIANCE: $last_role is a terminal step in $pipeline pipeline. No further agent dispatches expected. Proceed to final gate."
      fi

      if [[ -n "$valid" ]] && ! echo ",$valid," | grep -q ",$role,"; then
        deny "PIPELINE COMPLIANCE: Invalid step transition in $pipeline pipeline. After $last_role, valid next agents are: [$valid]. You are trying to dispatch $role which is not in the allowed sequence."
      fi
    }
  }
fi

# ═══════════════════════════════════════════════════════════
# STEP TRANSITION (D-178) — validation passed, write state
# ═══════════════════════════════════════════════════════════

# Map role → pipeline step
step=""
case "$role" in
  classifier)   step="classification" ;;
  explorer)
    if [[ "$pipeline" == "analytical" ]]; then
      step="gather"
    else
      step="exploration"
    fi ;;
  analyst)
    if [[ "$pipeline" == "analytical" ]]; then
      # scope if after explorer, analysis otherwise
      if [[ "$last_role" == "explorer" ]]; then
        step="scope"
      else
        step="analysis"
      fi
    else
      step="analysis"
    fi ;;
  architect)
    if [[ "$pipeline" == "analytical" ]]; then
      # organize step comes after depth_checkpoint/reviewer; analysis step comes after scope/analyst
      if [[ "$last_role" == "reviewer" ]]; then
        step="organize"
      else
        step="analysis"
      fi
    else
      step="architecture"
    fi ;;
  analytical_primary)  step="analysis" ;;
  analytical_organizer) step="organize" ;;
  planner)
    if [[ "$pipeline" == "decomposition" && "$subtask_mode" != "true" ]]; then
      step="decomposition"
    else
      step="plan"
    fi ;;
  implementer)  step="implementation" ;;
  reviewer)
    if [[ "$pipeline" == "analytical" ]]; then
      # depth_checkpoint if after analyst/architect, review if after scribe
      if [[ "$last_role" == "scribe" ]]; then
        step="review"
      else
        step="depth_checkpoint"
      fi
    else
      step="review"
    fi ;;
  tester)       step="testing" ;;
  scribe)       step="synthesis" ;;
esac

# Write step transition to current.yaml
if [[ -n "$step" ]]; then
  moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
  if [[ -f "$moira_home/lib/state.sh" ]]; then
    # shellcheck source=../lib/state.sh
    source "$moira_home/lib/state.sh" 2>/dev/null || true
    if type moira_state_transition &>/dev/null; then
      moira_state_transition "$step" "in_progress" "$state_dir" 2>/dev/null || true
    fi
  fi
fi

# Write dispatched_role to tracker state (for agent-done.sh to read)
# Append/update the dispatched_role line
if [[ -f "$tracker_file" ]]; then
  # Remove existing dispatched_role line and add new one
  grep -v '^dispatched_role=' "$tracker_file" > "${tracker_file}.tmp" 2>/dev/null || true
  echo "dispatched_role=$role" >> "${tracker_file}.tmp"
  mv "${tracker_file}.tmp" "$tracker_file" 2>/dev/null || true
else
  echo "dispatched_role=$role" > "$tracker_file" 2>/dev/null || true
fi

exit 0
