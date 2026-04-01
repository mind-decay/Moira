#!/usr/bin/env bash
# Pipeline Stop Guard — Stop hook
# Prevents orchestrator from stopping with incomplete pipeline steps.
# Part of Pipeline Compliance system (D-175).
#
# Fires: Stop (no matcher — always fires)
# Reads: .moira/state/pipeline-tracker.state
# Can output: decision=block to prevent premature completion
#
# MUST NOT fail — exits 0 silently on any error.
# MUST be fast — no library sourcing, minimal forks.

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

# --- Prevent infinite loop (Stop hook re-entry) ---
if command -v jq &>/dev/null; then
  stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
else
  stop_hook_active="false"
  echo "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null && stop_hook_active="true"
fi
[[ "$stop_hook_active" == "true" ]] && exit 0

# --- Read tracker state from current.yaml (D-198: consolidated) ---
current_file="$state_dir/current.yaml"
[[ ! -f "$current_file" ]] && exit 0

subtask_mode=$(grep '^subtask_mode:' "$current_file" 2>/dev/null | sed 's/^subtask_mode:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true

# Per-subtask state: check ALL active subtask files for pending flags
review_pending="false"
test_pending="false"
if [[ "$subtask_mode" == "true" ]]; then
  for sub_file in "$state_dir"/subtasks/*.yaml; do
    [[ -f "$sub_file" ]] || continue
    sub_review=$(grep '^review_pending:' "$sub_file" 2>/dev/null | sed 's/^review_pending:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    sub_test=$(grep '^test_pending:' "$sub_file" 2>/dev/null | sed 's/^test_pending:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    [[ "$sub_review" == "true" ]] && review_pending="true"
    [[ "$sub_test" == "true" ]] && test_pending="true"
  done
else
  review_pending=$(grep '^review_pending:' "$current_file" 2>/dev/null | sed 's/^review_pending:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  test_pending=$(grep '^test_pending:' "$current_file" 2>/dev/null | sed 's/^test_pending:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

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
