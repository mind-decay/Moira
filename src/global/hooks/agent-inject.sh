#!/usr/bin/env bash
# Agent Inject — SubagentStart hook
# Injects response contract and critical rules into every subagent's context.
# Ensures agents always receive minimum required instructions regardless of
# orchestrator prompt quality.
# Part of Pipeline Compliance system (D-175).
#
# Fires: SubagentStart (matcher: empty — all agents)
# Outputs: hookSpecificOutput.additionalContext with response contract + rules
#
# MUST NOT fail — exits 0 silently on any error.
# MUST be fast — minimal forks.

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

# --- Read task context ---
task_id=""
pipeline=""
if [[ -f "$state_dir/current.yaml" ]]; then
  task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  pipeline=$(grep '^pipeline:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^pipeline:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

[[ -z "$pipeline" || "$pipeline" == "null" ]] && exit 0

# --- Build injection ---
# Response contract + inviolable rules — compact but complete
inject="MOIRA AGENT CONTEXT (auto-injected) — Task: $task_id, Pipeline: $pipeline."
inject="$inject RESPONSE CONTRACT: You MUST end your response with exactly this format:"
inject="$inject STATUS: success|failure|blocked|budget_exceeded"
inject="$inject SUMMARY: <1-2 sentences, factual>"
inject="$inject ARTIFACTS: [<list of file paths written>]"
inject="$inject NEXT: <recommended next pipeline step>"
inject="$inject INVIOLABLE RULES: (1) Never fabricate APIs, URLs, schemas, or data structures. (2) Never proceed when information is insufficient — return STATUS: blocked. (3) Never suppress errors. (4) Write all detailed output to state files, return only status summary. (5) Never modify files outside stated scope."

# --- Inject ---
inject_escaped=$(echo "$inject" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null) || exit 0
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"$inject_escaped\"}}"

exit 0
