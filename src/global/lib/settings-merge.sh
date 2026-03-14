#!/usr/bin/env bash
# settings-merge.sh — Merge Moira hook configuration into .claude/settings.json
# Compatible with bash 3.2+ (macOS default).
#
# No Moira library dependencies (does not source yaml-utils.sh or others).

set -euo pipefail

# ── moira_settings_merge_hooks <project_root> <moira_home> ─────────────
# Inject Moira PostToolUse hooks into .claude/settings.json.
# Additive merge — never overwrites existing hooks.
# Idempotent — safe to re-run.
moira_settings_merge_hooks() {
  local project_root="$1"
  local moira_home="$2"

  local settings_dir="$project_root/.claude"
  local settings_file="$settings_dir/settings.json"

  mkdir -p "$settings_dir"

  # The Moira hook matcher block to inject
  local moira_hooks_json
  moira_hooks_json=$(cat <<'HOOKJSON'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/budget-track.sh"
          }
        ]
      }
    ]
  }
}
HOOKJSON
)

  # Check if Moira hooks are already registered (idempotent)
  if [[ -f "$settings_file" ]] && grep -q 'moira/hooks/guard.sh' "$settings_file" 2>/dev/null; then
    return 0
  fi

  if command -v jq &>/dev/null; then
    _moira_settings_merge_jq "$settings_file" "$moira_hooks_json"
  else
    _moira_settings_merge_fallback "$settings_file" "$moira_hooks_json"
  fi
}

# ── Internal: jq-based merge ──────────────────────────────────────────
_moira_settings_merge_jq() {
  local settings_file="$1"
  local moira_hooks_json="$2"

  local moira_matcher
  moira_matcher=$(cat <<'MATCHER'
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/moira/hooks/guard.sh"
    },
    {
      "type": "command",
      "command": "bash ~/.claude/moira/hooks/budget-track.sh"
    }
  ]
}
MATCHER
)

  if [[ ! -f "$settings_file" ]] || [[ ! -s "$settings_file" ]]; then
    # No existing file — write the full hooks JSON
    echo "$moira_hooks_json" | jq '.' > "$settings_file"
    return 0
  fi

  # File exists — merge
  local tmpfile
  tmpfile=$(mktemp)

  jq --argjson matcher "$moira_matcher" '
    .hooks = (.hooks // {}) |
    .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$matcher])
  ' "$settings_file" > "$tmpfile" 2>/dev/null

  if [[ $? -eq 0 ]] && [[ -s "$tmpfile" ]]; then
    mv "$tmpfile" "$settings_file"
  else
    rm -f "$tmpfile"
    echo "Warning: jq merge failed — falling back to manual merge" >&2
    _moira_settings_merge_fallback "$settings_file" "$moira_hooks_json"
  fi
}

# ── Internal: fallback merge (no jq) ──────────────────────────────────
_moira_settings_merge_fallback() {
  local settings_file="$1"
  local moira_hooks_json="$2"

  if [[ ! -f "$settings_file" ]] || [[ ! -s "$settings_file" ]]; then
    # No existing file — write directly
    echo "$moira_hooks_json" > "$settings_file"
    return 0
  fi

  # File exists — check complexity
  if grep -q '"PostToolUse"' "$settings_file" 2>/dev/null; then
    # Existing PostToolUse hooks — too complex to merge safely without jq
    echo "Warning: Cannot safely merge Moira hooks into existing settings.json without jq" >&2
    echo "Please add the following to your .claude/settings.json manually:" >&2
    echo "" >&2
    echo 'In the "hooks.PostToolUse" array, add:' >&2
    echo '{' >&2
    echo '  "matcher": "",' >&2
    echo '  "hooks": [' >&2
    echo '    { "type": "command", "command": "bash ~/.claude/moira/hooks/guard.sh" },' >&2
    echo '    { "type": "command", "command": "bash ~/.claude/moira/hooks/budget-track.sh" }' >&2
    echo '  ]' >&2
    echo '}' >&2
    return 1
  fi

  # No PostToolUse — insert hooks before the final closing brace
  local tmpfile
  tmpfile=$(mktemp)

  # Remove trailing whitespace/newlines and the final }
  # Then append the hooks section and close
  local content
  content=$(cat "$settings_file")

  # Strip trailing } and any trailing whitespace
  local trimmed
  trimmed=$(echo "$content" | sed '$ s/}[[:space:]]*$//')

  {
    echo "$trimmed,"
    cat <<'HOOKS'
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/budget-track.sh"
          }
        ]
      }
    ]
  }
}
HOOKS
  } > "$tmpfile"

  mv "$tmpfile" "$settings_file"
}

# ── moira_settings_remove_hooks <project_root> ────────────────────────
# Remove Moira hook entries from settings.json.
moira_settings_remove_hooks() {
  local project_root="$1"

  local settings_file="$project_root/.claude/settings.json"

  if [[ ! -f "$settings_file" ]]; then
    return 0
  fi

  if ! grep -q 'moira/hooks/' "$settings_file" 2>/dev/null; then
    return 0
  fi

  if command -v jq &>/dev/null; then
    local tmpfile
    tmpfile=$(mktemp)

    jq '
      if .hooks.PostToolUse then
        .hooks.PostToolUse = [
          .hooks.PostToolUse[] |
          .hooks = [.hooks[] | select(.command | contains("moira/hooks/") | not)] |
          select(.hooks | length > 0)
        ] |
        if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end |
        if (.hooks | length) == 0 then del(.hooks) else . end
      else .
      end
    ' "$settings_file" > "$tmpfile" 2>/dev/null

    if [[ $? -eq 0 ]] && [[ -s "$tmpfile" ]]; then
      mv "$tmpfile" "$settings_file"
    else
      rm -f "$tmpfile"
      echo "Warning: Cannot safely remove Moira hooks without working jq — please edit manually" >&2
      return 1
    fi
  else
    echo "Warning: Cannot safely remove Moira hooks without jq — please edit .claude/settings.json manually" >&2
    echo "Remove entries containing 'moira/hooks/guard.sh' and 'moira/hooks/budget-track.sh'" >&2
    return 1
  fi
}
