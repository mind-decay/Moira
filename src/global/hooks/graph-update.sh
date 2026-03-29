#!/usr/bin/env bash
# Graph Update — PostToolUse hook (matcher: Write|Edit)
# Runs `ariadne update` after every file write/edit to keep the graph fresh.
# Ariadne update is incremental and runs in milliseconds.
#
# Fires: PostToolUse (matcher: Write|Edit)
# Reads: tool_input.file_path from stdin JSON
# Side effect: updates .ariadne/graph/ in-place
#
# MUST NOT fail — exits 0 silently on any error.
# MUST be fast — ariadne update is ~ms.

input=$(cat 2>/dev/null) || exit 0

# --- Check ariadne binary ---
command -v ariadne &>/dev/null || exit 0

# --- Find project root (has .ariadne/) ---
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

# --- Skip non-project files (e.g. .claude/moira/ state writes) ---
file_path=""
if command -v jq &>/dev/null; then
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true
else
  file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || true
fi

# Skip if file is inside .claude/ or .ariadne/ (not project source)
case "$file_path" in
  *".claude/"*|*".ariadne/"*) exit 0 ;;
esac

# --- Run incremental update ---
ariadne update "$project_root" >/dev/null 2>&1 || true

exit 0
