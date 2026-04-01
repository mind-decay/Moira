#!/usr/bin/env bash
# Compact Re-injection — SessionStart hook (matcher: compact)
# Re-injects pipeline state into orchestrator context after compaction.
# Prevents orchestrator from losing track of pipeline state after context compression.
# Part of Pipeline Compliance system (D-175).
#
# Fires: SessionStart (matcher: compact)
# Reads: .moira/state/current.yaml, pipeline-tracker.state
# Outputs: hookSpecificOutput.additionalContext with pipeline state
#
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

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

# --- Read tracker state from current.yaml (D-198: consolidated) ---
_yaml_get() {
  grep "^${2}:" "$1" 2>/dev/null | sed "s/^${2}:[[:space:]]*//" | tr -d '"' | tr -d "'" 2>/dev/null
}

last_role=""
review_pending="false"
test_pending="false"
subtask_mode="false"
current_subtask=""
if [[ -f "$state_dir/current.yaml" ]]; then
  subtask_mode=$(_yaml_get "$state_dir/current.yaml" "subtask_mode") || true
  current_subtask=$(_yaml_get "$state_dir/current.yaml" "current_subtask") || true

  # Per-subtask state isolation
  if [[ "$subtask_mode" == "true" && -n "$current_subtask" && "$current_subtask" != "null" ]]; then
    subtask_file="$state_dir/subtasks/${current_subtask}.yaml"
    if [[ -f "$subtask_file" ]]; then
      last_role=$(_yaml_get "$subtask_file" "last_role") || true
      review_pending=$(_yaml_get "$subtask_file" "review_pending") || true
      test_pending=$(_yaml_get "$subtask_file" "test_pending") || true
    fi
  else
    last_role=$(_yaml_get "$state_dir/current.yaml" "last_role") || true
    review_pending=$(_yaml_get "$state_dir/current.yaml" "review_pending") || true
    test_pending=$(_yaml_get "$state_dir/current.yaml" "test_pending") || true
  fi
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
moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
msg="$msg Read the orchestrator skill: $moira_home/skills/orchestrator.md and the current pipeline definition: $moira_home/core/pipelines/$pipeline.yaml"

# --- Ariadne graph context (re-inject after compaction) ---
if command -v ariadne &>/dev/null; then
  graph_overview=$(timeout 10 ariadne query overview --project "$PWD" 2>/dev/null) || true
  if [[ -n "$graph_overview" ]]; then
    # Extract key stats for compact injection
    if command -v jq &>/dev/null; then
      nodes=$(echo "$graph_overview" | jq -r '.node_count // "?"' 2>/dev/null) || nodes="?"
      edges=$(echo "$graph_overview" | jq -r '.edge_count // "?"' 2>/dev/null) || edges="?"
      cycles=$(echo "$graph_overview" | jq -r '.cycle_count // 0' 2>/dev/null) || cycles="0"
      layers=$(echo "$graph_overview" | jq -r '.max_depth // "?"' 2>/dev/null) || layers="?"
      msg="$msg PROJECT GRAPH (Ariadne): ${nodes} files, ${edges} edges, ${cycles} cycles, ${layers} layers deep. Graph is available — agents should use ariadne_* tools for structural queries."
    fi
  fi
fi

# --- Inject ---
msg_escaped=$(echo "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || exit 0
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$msg_escaped\"}}"

exit 0
