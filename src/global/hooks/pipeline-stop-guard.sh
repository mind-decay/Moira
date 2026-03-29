#!/usr/bin/env bash
# Pipeline Stop Guard — Stop hook
# Prevents orchestrator from stopping with incomplete pipeline steps.
# Part of Pipeline Compliance system (D-175).
#
# Fires: Stop (no matcher — always fires)
# Reads: .claude/moira/state/pipeline-tracker.state
# Can output: decision=block to prevent premature completion
#
# MUST NOT fail — exits 0 silently on any error.
# MUST be fast — no library sourcing, minimal forks.

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

# --- Prevent infinite loop (Stop hook re-entry) ---
if command -v jq &>/dev/null; then
  stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
else
  stop_hook_active="false"
  echo "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null && stop_hook_active="true"
fi
[[ "$stop_hook_active" == "true" ]] && exit 0

# --- Read tracker state ---
tracker_file="$state_dir/pipeline-tracker.state"
[[ ! -f "$tracker_file" ]] && exit 0

review_pending=$(grep '^review_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true
test_pending=$(grep '^test_pending=' "$tracker_file" 2>/dev/null | cut -d= -f2) || true

# --- Block stop if mandatory steps are pending ---
if [[ "$review_pending" == "true" ]]; then
  echo "{\"decision\":\"block\",\"reason\":\"PIPELINE COMPLIANCE: Cannot stop — review is pending. You must dispatch Themis (reviewer) to review the implementation before completing the pipeline.\"}"
  exit 0
fi

if [[ "$test_pending" == "true" ]]; then
  echo "{\"decision\":\"block\",\"reason\":\"PIPELINE COMPLIANCE: Cannot stop — testing is pending. You must dispatch Aletheia (tester) to test the reviewed implementation before completing the pipeline.\"}"
  exit 0
fi

# Pipeline compliance OK — allow stop
exit 0
