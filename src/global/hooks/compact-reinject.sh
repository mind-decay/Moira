#!/usr/bin/env bash
# Compact Re-injection — SessionStart hook (matcher: compact)
# Re-injects pipeline state into orchestrator context after compaction.
# Prevents orchestrator from losing track of pipeline state after context compression.
# Part of Pipeline Compliance system (D-175).
#
# Fires: SessionStart (matcher: compact)
# Reads: .claude/moira/state/current.yaml, pipeline-tracker.state
# Outputs: hookSpecificOutput.additionalContext with pipeline state
#
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

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

# --- Read pipeline state from current.yaml ---
task_id=""
pipeline=""
step=""
step_status=""
if [[ -f "$state_dir/current.yaml" ]]; then
  task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  pipeline=$(grep '^pipeline:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^pipeline:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  step=$(grep '^step:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  step_status=$(grep '^step_status:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

[[ -z "$pipeline" || "$pipeline" == "null" ]] && exit 0

# --- Read tracker state ---
tracker_file="$state_dir/pipeline-tracker.state"
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

# --- Build re-injection message ---
msg="CONTEXT RECOVERY AFTER COMPACTION — You are Moira, the orchestrator."
msg="$msg Task: $task_id. Pipeline: $pipeline. Current step: $step ($step_status). Last agent dispatched: $last_role."

if [[ "$review_pending" == "true" ]]; then
  msg="$msg REVIEW IS PENDING — you MUST dispatch Themis (reviewer) before any other step."
elif [[ "$test_pending" == "true" ]]; then
  msg="$msg TESTING IS PENDING — you MUST dispatch Aletheia (tester) before any other step."
fi

if [[ "$pipeline" == "decomposition" && "$subtask_mode" == "true" ]]; then
  msg="$msg You are executing decomposition sub-tasks. Each sub-task requires a full nested pipeline."
fi

msg="$msg CRITICAL RULES: You are a pure orchestrator — NEVER read/write project files directly. Dispatch agents for all work. Follow the pipeline step sequence. Present all required gates."
msg="$msg Read the orchestrator skill: ~/.claude/moira/skills/orchestrator.md and the current pipeline definition: ~/.claude/moira/core/pipelines/$pipeline.yaml"

# --- Inject ---
msg_escaped=$(echo "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || exit 0
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$msg_escaped\"}}"

exit 0
