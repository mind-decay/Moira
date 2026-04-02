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
inject="$inject AGENT ROLE: You are a DISPATCHED AGENT, not the orchestrator. The 'Orchestrator Boundaries' section in CLAUDE.md does NOT apply to you. You MUST freely use Read, Edit, Write, Grep, Glob, and Bash on project files to complete your task."
inject="$inject RESPONSE CONTRACT: You MUST end your response with exactly this format:"
inject="$inject STATUS: success|failure|blocked|budget_exceeded"
inject="$inject SUMMARY: <1-2 sentences, factual>"
inject="$inject ARTIFACTS: [<list of file paths written>]"
inject="$inject NEXT: <recommended next pipeline step>"
inject="$inject INVIOLABLE RULES: (1) Never fabricate APIs, URLs, schemas, or data structures. (2) Never proceed when information is insufficient — return STATUS: blocked. (3) Never suppress errors. (4) Write all detailed output to state files, return only status summary. (5) Never modify files outside stated scope."

# --- Cross-gate traceability injection (D-184) ---
# Inject focused context from previous pipeline gates so agents can't ignore scope/criteria/UNVERIFIED items.
# This is a lightweight backup — primary injection is via dispatch.md step 4g.
# The hook focuses on UNVERIFIED assumption propagation since it's the most critical for epistemic integrity.

traceability=""

# Determine agent role from description in input
agent_desc=""
if command -v jq &>/dev/null; then
  agent_desc=$(echo "$input" | jq -r '.agent_description // empty' 2>/dev/null) || agent_desc=""
else
  agent_desc=$(echo "$input" | grep -o '"agent_description"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_description"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_desc=""
fi

role=""
case "$agent_desc" in
  *"(architect)"*|*"Metis"*)      role="metis" ;;
  *"(planner)"*|*"Daedalus"*)     role="daedalus" ;;
  *"(implementer)"*|*"Hephaestus"*) role="hephaestus" ;;
  *"(reviewer)"*|*"Themis"*)      role="themis" ;;
esac

if [[ -n "$role" && -n "$task_id" && "$task_id" != "null" ]]; then
  task_dir="$state_dir/tasks/$task_id"

  # --- Inject classification scope + acceptance criteria ---
  if [[ -f "$task_dir/classification.md" ]]; then
    # Extract acceptance criteria (lightweight — just the section header presence reminder)
    has_criteria=$(grep -c '^## Acceptance Criteria' "$task_dir/classification.md" 2>/dev/null) || has_criteria=0
    if [[ "$has_criteria" -gt 0 ]]; then
      traceability="$traceability TRACEABILITY (D-184): Classification acceptance criteria are defined — your output must address them."
    fi
  fi

  # --- Inject UNVERIFIED assumptions from architecture ---
  if [[ "$role" == "daedalus" || "$role" == "hephaestus" || "$role" == "themis" ]]; then
    if [[ -f "$task_dir/architecture.md" ]]; then
      # Check for UNVERIFIED items
      unverified_count=$(grep -ci 'UNVERIFIED' "$task_dir/architecture.md" 2>/dev/null) || unverified_count=0
      if [[ "$unverified_count" -gt 0 ]]; then
        # Extract UNVERIFIED lines (up to 5)
        unverified_items=$(grep -i 'UNVERIFIED' "$task_dir/architecture.md" 2>/dev/null | head -5 | tr '\n' '; ' | sed 's/[#*-]//g; s/  */ /g' 2>/dev/null) || unverified_items=""
        traceability="$traceability UNVERIFIED ASSUMPTIONS ($unverified_count items from architecture): $unverified_items"

        case "$role" in
          daedalus)
            traceability="$traceability You MUST include ## Unverified Dependencies section addressing each UNVERIFIED item." ;;
          hephaestus)
            traceability="$traceability Before implementing code that depends on these: verify via docs or mark with // UNVERIFIED comment." ;;
          themis)
            traceability="$traceability AUDIT each UNVERIFIED item: was it verified during implementation? Report unresolved items as WARNING." ;;
        esac
      fi
    fi
  fi
fi

if [[ -n "$traceability" ]]; then
  inject="$inject $traceability"
fi

# --- Inject (escape for JSON: backslashes, quotes, tabs, collapse newlines) ---
inject_escaped=$(printf '%s' "$inject" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ') || exit 0
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"$inject_escaped\"}}"

exit 0
