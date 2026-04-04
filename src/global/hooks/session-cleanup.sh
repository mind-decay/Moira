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
    if [[ -d "$dir/.moira/state" ]]; then
      echo "$dir/.moira/state"
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
  completed)
    # Read task_id BEFORE deleting current.yaml (needed for cleanup references)
    task_id=""
    if [[ -f "$state_dir/current.yaml" ]]; then
      task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
    fi

    # Clean exit — remove all session artifacts
    rm -f "$state_dir/.session-lock" 2>/dev/null || true
    rm -f "$state_dir/.guard-active" 2>/dev/null || true
    rm -rf "$state_dir/subtasks" 2>/dev/null || true
    rm -f "$state_dir/.guard-stale" 2>/dev/null || true
    # Legacy cleanup (D-198: pipeline-tracker.state removed)
    rm -f "$state_dir/pipeline-tracker.state" 2>/dev/null || true
    rm -f "$state_dir/pipeline-tracker-sub-*.state" 2>/dev/null || true

    # Task cleanup + metrics retention (D-219, D-222)
    # Triggered from deterministic hook, not LLM-dispatched completion.sh
    _moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
    if [[ -f "$_moira_home/lib/completion.sh" ]]; then
      # shellcheck source=../lib/completion.sh
      source "$_moira_home/lib/completion.sh" 2>/dev/null || true

      # Read retention config
      _config_file="${state_dir}/../config.yaml"
      _retention_days=30
      _retention_months=12
      if [[ -f "$_config_file" ]]; then
        _rd=$(awk '/task_retention_days:/{print $2;exit}' "$_config_file" 2>/dev/null | tr -d '"' 2>/dev/null) || true
        [[ -n "$_rd" && "$_rd" =~ ^[0-9]+$ ]] && _retention_days="$_rd"
        _rm=$(awk '/metrics_retention_months:/{print $2;exit}' "$_config_file" 2>/dev/null | tr -d '"' 2>/dev/null) || true
        [[ -n "$_rm" && "$_rm" =~ ^[0-9]+$ ]] && _retention_months="$_rm"
      fi

      # Task cleanup
      if type moira_task_cleanup &>/dev/null; then
        moira_task_cleanup "$state_dir" "$_retention_days" 2>/dev/null || true
      fi

      # Metrics retention
      if type moira_metrics_retention &>/dev/null; then
        moira_metrics_retention "$state_dir/metrics" "$_retention_months" 2>/dev/null || true
      fi
    fi

    # Delete current.yaml last (after all reads)
    rm -f "$state_dir/current.yaml" 2>/dev/null || true
    ;;
  checkpointed)
    # Checkpointed exit — clean session artifacts only, preserve state for resume
    rm -f "$state_dir/.session-lock" 2>/dev/null || true
    rm -f "$state_dir/.guard-active" 2>/dev/null || true
    rm -rf "$state_dir/subtasks" 2>/dev/null || true
    rm -f "$state_dir/current.yaml" 2>/dev/null || true
    rm -f "$state_dir/.guard-stale" 2>/dev/null || true
    # Legacy cleanup
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
