#!/usr/bin/env bash
# Budget tracking hook — PostToolUse per-tool-call token usage logging
# Logs tool activity for post-task budget analysis (Art 3.2).
# MUST NOT fail — any error exits 0 silently.
# MUST be fast — no library sourcing, minimal forks.

# Read hook input from stdin
input=$(cat 2>/dev/null) || exit 0

# --- Parse JSON fields ---
if command -v jq &>/dev/null; then
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
  if [[ -z "$file_path" ]]; then
    file_path=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || file_path=""
  fi
else
  tool_name=$(echo "$input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || tool_name=""
  file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || file_path=""
  if [[ -z "$file_path" ]]; then
    file_path=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || file_path=""
  fi
fi

[[ -z "$tool_name" ]] && exit 0

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

# --- Config check: hooks.budget_tracking_enabled ---
config_file="${state_dir%/state}/config.yaml"
if [[ -f "$config_file" ]]; then
  budget_val=$(grep 'budget_tracking_enabled' "$config_file" 2>/dev/null | head -1) || true
  if [[ "$budget_val" == *"false"* ]]; then
    exit 0
  fi
fi

# --- Timestamp ---
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp="unknown"

# --- Determine file size ---
file_size=0
case "$tool_name" in
  Read|Write|Edit)
    if [[ -n "$file_path" && -f "$file_path" ]]; then
      file_size=$(wc -c < "$file_path" 2>/dev/null | tr -d ' ') || file_size=0
    fi
    ;;
  Agent)
    file_path="agent"
    ;;
esac

# --- Log to budget-tool-usage.log ---
echo "$timestamp $tool_name ${file_path:--} ${file_size:-0}" >> "$state_dir/budget-tool-usage.log" 2>/dev/null || true

exit 0
