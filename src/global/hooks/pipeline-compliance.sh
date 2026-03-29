#!/usr/bin/env bash
# Pipeline Compliance — PreToolUse hook for Agent dispatches
# Validates dispatches against per-pipeline transition tables.
# DENY wrong dispatches to enforce step ordering.
# Part of Pipeline Compliance system (D-175).
#
# Three enforcement layers:
#   L1: review_pending — implementer MUST be followed by reviewer
#   L2: test_pending — reviewer MUST be followed by tester (when pipeline has testing)
#   L3: Transition table — each role can only transition to specific next roles per pipeline
#
# Fires: PreToolUse (matcher: Agent)
# Reads: .claude/moira/state/pipeline-tracker.state
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
role=$(echo "$description" | grep -oE '\([a-z]+\)' | head -1 | tr -d '()' 2>/dev/null) || true
[[ -z "$role" ]] && exit 0

# Always-allowed roles (outside pipeline step sequence)
case "$role" in
  reflector|auditor) exit 0 ;;
esac

# --- Read tracker state ---
tracker_file="$state_dir/pipeline-tracker.state"
[[ ! -f "$tracker_file" ]] && exit 0

pipeline=$(grep '^pipeline=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
last_role=$(grep '^last_role=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
review_pending=$(grep '^review_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
test_pending=$(grep '^test_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
subtask_mode=$(grep '^subtask_mode=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true

[[ -z "$pipeline" ]] && exit 0

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

# Same role = retry — always valid
[[ "$last_role" == "$role" ]] && exit 0

# Architect and planner are re-entry points for error recovery
# (rearchitect at any gate, replan, E5/E6 escalation)
# Always allowed — L1/L2 already guard the critical invariants
[[ "$role" == "architect" || "$role" == "planner" ]] && exit 0

# Determine effective pipeline for transition lookup
effective_pipeline="$pipeline"
if [[ "$pipeline" == "decomposition" && "$subtask_mode" == "true" ]]; then
  effective_pipeline="decomposition_sub"
fi

# Transition table: "pipeline:last_role" → comma-separated valid next roles
# Architect/planner transitions included for completeness but subsumed by always-allow above
valid=""
case "$effective_pipeline:$last_role" in
  # ── Quick pipeline ──────────────────────────────────────
  quick:classifier)             valid="explorer" ;;
  quick:explorer)               valid="implementer" ;;
  quick:implementer)            valid="reviewer" ;;
  quick:reviewer)               valid="" ;; # completion

  # ── Standard pipeline ───────────────────────────────────
  standard:classifier)          valid="explorer,analyst" ;; # parallel dispatch
  standard:explorer)            valid="architect,analyst" ;; # wait for parallel or advance
  standard:analyst)             valid="architect,explorer" ;; # wait for parallel or advance
  standard:architect)           valid="planner" ;;
  standard:planner)             valid="implementer" ;;
  standard:implementer)         valid="implementer,reviewer" ;; # batches allowed
  standard:reviewer)            valid="tester" ;;
  standard:tester)              valid="" ;; # completion

  # ── Full pipeline ───────────────────────────────────────
  full:classifier)              valid="explorer,analyst" ;;
  full:explorer)                valid="architect,analyst" ;;
  full:analyst)                 valid="architect,explorer" ;;
  full:architect)               valid="planner" ;;
  full:planner)                 valid="implementer" ;;
  full:implementer)             valid="reviewer" ;; # strict 1:1 per phase
  full:reviewer)                valid="tester" ;;
  full:tester)                  valid="implementer,tester" ;; # next phase or integration

  # ── Decomposition pipeline (main level) ─────────────────
  decomposition:classifier)     valid="analyst" ;;
  decomposition:analyst)        valid="architect" ;;
  decomposition:architect)      valid="planner" ;;
  decomposition:planner)        valid="classifier,tester" ;; # sub-task classification or integration

  # ── Decomposition sub-tasks (union of quick/standard/full) ──
  decomposition_sub:classifier) valid="explorer,analyst" ;;
  decomposition_sub:explorer)   valid="implementer,architect,analyst" ;; # quick→impl, standard→arch
  decomposition_sub:analyst)    valid="architect,explorer" ;;
  decomposition_sub:architect)  valid="planner" ;;
  decomposition_sub:planner)    valid="implementer" ;;
  decomposition_sub:implementer) valid="reviewer" ;;
  decomposition_sub:reviewer)   valid="tester,classifier" ;; # test, or next sub-task (quick has no test)
  decomposition_sub:tester)     valid="classifier,tester" ;; # next sub-task or integration

  # ── Analytical pipeline (permissive — complex branching) ──
  analytical:classifier)        valid="explorer" ;;
  analytical:explorer)          valid="analyst" ;;
  analytical:analyst)           valid="architect,explorer,analyst,reviewer,scribe" ;; # various analysis paths
  analytical:architect)         valid="analyst,reviewer,scribe" ;; # Metis as organizer
  analytical:reviewer)          valid="analyst,architect,scribe" ;; # deepen/redirect/proceed
  analytical:scribe)            valid="reviewer" ;; # final review after synthesis

  # Unknown state → allow (don't block on unrecognized state)
  *) exit 0 ;;
esac

# Empty valid = completion phase — only completion processor/reflector remain (already filtered)
[[ -z "$valid" ]] && exit 0

# Check if dispatched role is in valid transitions
if echo ",$valid," | grep -q ",$role,"; then
  exit 0 # valid transition
fi

# Invalid transition — DENY with actionable message
deny "PIPELINE COMPLIANCE: Invalid step transition in $pipeline pipeline. After $last_role, valid next agents are: [$valid]. You are trying to dispatch $role which is not in the allowed sequence. Follow the pipeline step order."
