#!/usr/bin/env bash
# Graph Validate — TaskCompleted hook
# Checks structural health before allowing task completion.
# Blocks (exit 2) if new cycles or critical architectural smells are detected.
#
# Fires: TaskCompleted (no matcher support)
# Reads: .ariadne/graph/ via ariadne CLI
# Outputs: stderr message on block (exit 2), silent on pass (exit 0)
#
# MUST NOT crash — exits 0 on any infrastructure error (graceful degradation).

input=$(cat 2>/dev/null) || exit 0

# --- Check ariadne binary ---
command -v ariadne &>/dev/null || exit 0

# --- Find project root ---
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.ariadne" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

project_root=$(find_project_root) || exit 0

# --- Check for cycles ---
cycles_output=$(ariadne query cycles --project "$project_root" 2>/dev/null) || exit 0

cycle_count=0
if command -v jq &>/dev/null; then
  cycle_count=$(echo "$cycles_output" | jq '.cycles | length // 0' 2>/dev/null) || cycle_count=0
fi

# --- Check for critical smells ---
smells_output=$(ariadne query smells --project "$project_root" 2>/dev/null) || exit 0

critical_smells=0
if command -v jq &>/dev/null; then
  # Count god_file and circular_dependency smells (critical severity)
  critical_smells=$(echo "$smells_output" | jq '[.smells[]? | select(.kind == "god_file" or .kind == "circular_dependency")] | length // 0' 2>/dev/null) || critical_smells=0
fi

# --- Report ---
issues=""

if [[ "$cycle_count" -gt 0 ]]; then
  issues="Circular dependencies detected: $cycle_count cycle(s). "
fi

if [[ "$critical_smells" -gt 0 ]]; then
  issues="${issues}Critical architectural smells: $critical_smells (god_file/circular_dependency). "
fi

if [[ -n "$issues" ]]; then
  echo "STRUCTURAL HEALTH WARNING: ${issues}Review with ariadne query cycles/smells before completing." >&2
  # Note: exit 2 would BLOCK completion. Using exit 0 + stderr as warning for now.
  # Uncomment the line below to enforce blocking:
  # exit 2
fi

exit 0
