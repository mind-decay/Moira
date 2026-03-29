#!/usr/bin/env bash
# Pipeline Tracker — PostToolUse hook for Agent dispatches
# Tracks which agents have been dispatched and injects next-step guidance.
# Part of Pipeline Compliance system (D-175).
#
# Fires: PostToolUse (matcher: Agent)
# Writes: .claude/moira/state/pipeline-tracker.state
# Outputs: hookSpecificOutput.additionalContext with next-step instructions
#
# MUST NOT fail — exits 0 silently on any error.
# MUST be fast — no library sourcing, minimal forks.

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

# Only process foreground Agent tool calls
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

# Only during active pipeline
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

# --- Extract agent role from description ---
# Moira format: "Name (role) — description"
role=$(echo "$description" | grep -oE '\([a-z]+\)' | head -1 | tr -d '()' 2>/dev/null) || true

# No role = not a standard Moira dispatch (completion processor, scanner, etc.)
[[ -z "$role" ]] && exit 0

# Skip non-pipeline agents
case "$role" in
  reflector|auditor) exit 0 ;;
esac

# --- Read pipeline type from current.yaml ---
pipeline=""
if [[ -f "$state_dir/current.yaml" ]]; then
  pipeline=$(grep '^pipeline:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^pipeline:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi
[[ -z "$pipeline" || "$pipeline" == "null" ]] && exit 0

# --- Tracker state file ---
tracker_file="$state_dir/pipeline-tracker.state"

# Read current state (defaults if file doesn't exist)
last_role=""
review_pending="false"
test_pending="false"
subtask_mode="false"
if [[ -f "$tracker_file" ]]; then
  last_role=$(grep '^last_role=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
  review_pending=$(grep '^review_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
  test_pending=$(grep '^test_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
  subtask_mode=$(grep '^subtask_mode=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
fi

# --- Compute new state ---
new_review_pending="$review_pending"
new_test_pending="$test_pending"
new_subtask_mode="$subtask_mode"

case "$role" in
  implementer)
    new_review_pending="true"
    new_test_pending="false"  # new implementation invalidates prior test requirement
    ;;
  reviewer)
    new_review_pending="false"
    case "$pipeline" in
      standard|full|decomposition)
        new_test_pending="true"
        ;;
      *)
        new_test_pending="false"
        ;;
    esac
    ;;
  tester)
    new_test_pending="false"
    ;;
  classifier)
    # New classification = new task/sub-task — reset pending flags
    new_review_pending="false"
    new_test_pending="false"
    ;;
  architect|planner)
    # Re-architecture/re-plan invalidates previous implementation
    new_review_pending="false"
    new_test_pending="false"
    ;;
esac

# Decomposition sub-task mode tracking
# subtask_mode activates on the first classifier AFTER the main-level planner,
# not on the planner itself — so compliance uses decomposition transitions for
# the dispatch immediately following planner (must be classifier or tester).
if [[ "$pipeline" == "decomposition" ]]; then
  if [[ "$role" == "classifier" && "$last_role" == "planner" && "$subtask_mode" != "true" ]]; then
    # First sub-task classifier dispatched after main-level planner
    new_subtask_mode="true"
  fi
fi

# --- Write tracker state ---
cat > "$tracker_file" 2>/dev/null << EOF
active=true
pipeline=$pipeline
last_role=$role
review_pending=$new_review_pending
test_pending=$new_test_pending
subtask_mode=$new_subtask_mode
EOF

# --- Inject next-step guidance via additionalContext ---
guidance=""

# Determine effective pipeline for guidance
eff_pipeline="$pipeline"
if [[ "$pipeline" == "decomposition" && "$new_subtask_mode" == "true" && "$role" != "planner" ]]; then
  eff_pipeline="decomposition_sub"
fi

case "$role" in
  classifier)
    case "$eff_pipeline" in
      quick)
        guidance="Pipeline compliance: Classification complete. Next: dispatch Hermes (explorer)." ;;
      standard|full)
        guidance="Pipeline compliance: Classification complete. Next: dispatch Hermes (explorer) and Athena (analyst) in parallel." ;;
      decomposition)
        guidance="Pipeline compliance: Classification complete. Next: dispatch Athena (analyst)." ;;
      decomposition_sub)
        guidance="Pipeline compliance: Sub-task classified. Next: dispatch Hermes (explorer), or Hermes (explorer) and Athena (analyst) in parallel depending on sub-task pipeline." ;;
      analytical)
        guidance="Pipeline compliance: Classification complete. Next: dispatch Hermes (explorer) for data gathering." ;;
    esac
    ;;
  explorer)
    case "$eff_pipeline" in
      quick)
        guidance="Pipeline compliance: Exploration complete. Next: dispatch Hephaestus (implementer)." ;;
      decomposition_sub)
        guidance="Pipeline compliance: Exploration complete. Next: dispatch Metis (architect), or Hephaestus (implementer) if sub-task is quick pipeline." ;;
      analytical)
        guidance="Pipeline compliance: Gathering complete. Next: dispatch Athena (analyst) for scope formalization." ;;
      *)
        guidance="Pipeline compliance: Exploration complete. Proceed to Metis (architect), or wait for parallel Athena (analyst)." ;;
    esac
    ;;
  analyst)
    case "$eff_pipeline" in
      decomposition)
        guidance="Pipeline compliance: Analysis complete. Next: dispatch Metis (architect) for epic architecture." ;;
      analytical)
        guidance="Pipeline compliance: Scope formalized. Proceed to analysis step per analytical pipeline." ;;
      *)
        guidance="Pipeline compliance: Analysis complete. Proceed to Metis (architect), or wait for parallel Hermes (explorer)." ;;
    esac
    ;;
  architect)
    case "$eff_pipeline" in
      decomposition)
        guidance="Pipeline compliance: Architecture complete. Next: dispatch Daedalus (planner) for task decomposition." ;;
      *)
        guidance="Pipeline compliance: Architecture complete. Next: dispatch Daedalus (planner)." ;;
    esac
    ;;
  planner)
    case "$pipeline" in
      decomposition)
        if [[ "$subtask_mode" != "true" ]]; then
          # Main-level planner completed decomposition
          guidance="PIPELINE COMPLIANCE — SUB-PIPELINE REQUIRED: Decomposition complete. For EACH sub-task you MUST run a FULL nested pipeline: Apollo (classifier) first, then the classified pipeline steps including Hermes (explorer), architecture, planning, Hephaestus (implementer), Themis (reviewer), and Aletheia (tester). Start by dispatching Apollo (classifier) for the first sub-task. Do NOT dispatch Hephaestus (implementer) directly."
        else
          # Sub-task planner
          guidance="Pipeline compliance: Sub-task planning complete. Next: dispatch Hephaestus (implementer)."
        fi
        ;;
      *)
        guidance="Pipeline compliance: Planning complete. Next: dispatch Hephaestus (implementer)." ;;
    esac
    ;;
  implementer)
    guidance="PIPELINE COMPLIANCE — REVIEW REQUIRED: Implementation complete. You MUST dispatch Themis (reviewer) for code review BEFORE any other step. Do NOT dispatch another implementer for a different task, and do NOT dispatch Apollo (classifier) for the next sub-task, until Themis reviews this implementation."
    ;;
  reviewer)
    case "$eff_pipeline" in
      quick)
        guidance="Pipeline compliance: Review complete. Proceed to final gate." ;;
      analytical)
        guidance="Pipeline compliance: Review complete. Proceed per analytical pipeline flow." ;;
      decomposition_sub)
        guidance="Pipeline compliance: Review complete. Next: dispatch Aletheia (tester), or if sub-task is quick pipeline, proceed to next sub-task via Apollo (classifier)." ;;
      *)
        guidance="Pipeline compliance: Review complete. Next: dispatch Aletheia (tester) for testing." ;;
    esac
    ;;
  tester)
    case "$eff_pipeline" in
      full)
        guidance="Pipeline compliance: Testing complete. Proceed to next phase (Hephaestus implementer), or integration testing (Aletheia tester), or final gate." ;;
      decomposition_sub)
        guidance="Pipeline compliance: Sub-task testing complete. Proceed to next sub-task (Apollo classifier) or integration testing (Aletheia tester) if all sub-tasks done." ;;
      *)
        guidance="Pipeline compliance: Testing complete. Proceed to final gate." ;;
    esac
    ;;
  scribe)
    guidance="Pipeline compliance: Synthesis complete. Next: dispatch Themis (reviewer) for final review."
    ;;
esac

if [[ -n "$guidance" ]]; then
  # Escape for JSON output
  guidance_escaped=$(echo "$guidance" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || exit 0
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$guidance_escaped\"}}"
fi

exit 0
