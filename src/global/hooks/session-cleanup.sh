#!/usr/bin/env bash
# Session Cleanup — SessionEnd hook
# Cleans up session lock, guard-active, and tracker state on session exit.
# Part of State Automation (D-178).
#
# Fires: SessionEnd (no matcher — always fires)
# Reads: current.yaml step_status
# Deletes: .session-lock, .guard-active, pipeline-tracker.state (on clean exit)
#
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Find Moira state directory ---
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.claude/moira/state" ]]; then
      echo "$dir/.claude/moira/state"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

state_dir=$(find_state_dir) || exit 0

# Only clean up if guard was active (pipeline was running)
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

# --- Read pipeline state ---
step_status=""
if [[ -f "$state_dir/current.yaml" ]]; then
  step_status=$(grep '^step_status:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^step_status:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

case "$step_status" in
  completed|checkpointed)
    # Clean exit — remove all session artifacts
    rm -f "$state_dir/.session-lock" 2>/dev/null || true
    rm -f "$state_dir/.guard-active" 2>/dev/null || true
    rm -f "$state_dir/pipeline-tracker.state" 2>/dev/null || true
    rm -f "$state_dir/pipeline-tracker-sub-*.state" 2>/dev/null || true
    ;;
  *)
    # Abnormal exit (in_progress, pending, failed, etc.)
    # Mark session lock as stale for next session detection
    if [[ -f "$state_dir/.session-lock" ]]; then
      # Set TTL to 0 to mark as expired
      sed -i.bak 's/^ttl:.*/ttl: 0/' "$state_dir/.session-lock" 2>/dev/null || true
      rm -f "$state_dir/.session-lock.bak" 2>/dev/null || true
    fi
    # Leave .guard-active and tracker for /moira:resume
    # Write stale marker so non-resume sessions can detect and clean up
    echo "stale_since=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" > "$state_dir/.guard-stale" 2>/dev/null || true
    ;;
esac

exit 0
