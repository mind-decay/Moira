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

# ── moira_settings_register_statusline <moira_home> ───────────────────
# Register statusline script in user-level ~/.claude/settings.json.
# Idempotent — safe to re-run.
moira_settings_register_statusline() {
  local moira_home="$1"
  local settings_file="$HOME/.claude/settings.json"

  mkdir -p "$HOME/.claude"

  # Already registered?
  if [[ -f "$settings_file" ]] && grep -q 'moira/statusline/context-status.sh' "$settings_file" 2>/dev/null; then
    return 0
  fi

  local statusline_cmd="bash ${moira_home}/statusline/context-status.sh"

  if command -v jq &>/dev/null; then
    if [[ ! -f "$settings_file" ]] || [[ ! -s "$settings_file" ]]; then
      jq -n --arg cmd "$statusline_cmd" '{ statusLine: { type: "command", command: $cmd } }' > "$settings_file"
    else
      local tmpfile
      tmpfile=$(mktemp)
      jq --arg cmd "$statusline_cmd" '.statusLine = { type: "command", command: $cmd }' "$settings_file" > "$tmpfile" 2>/dev/null
      if [[ $? -eq 0 ]] && [[ -s "$tmpfile" ]]; then
        mv "$tmpfile" "$settings_file"
      else
        rm -f "$tmpfile"
        echo "Warning: Could not register statusLine — please add manually to ~/.claude/settings.json:" >&2
        echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_cmd\" }" >&2
        return 1
      fi
    fi
  else
    echo "Warning: jq not found — please add statusLine to ~/.claude/settings.json manually:" >&2
    echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_cmd\" }" >&2
    return 1
  fi
}

# ── moira_settings_merge_mcp <project_root> ───────────────────────────
# Register MCP servers in .mcp.json (project root).
# Claude Code reads MCP server definitions from .mcp.json, NOT from
# .claude/settings.json (D-120).
# Additive merge — never overwrites existing mcpServers entries.
# Idempotent — safe to re-run.
moira_settings_merge_mcp() {
  local project_root="$1"
  local server_name="$2"
  local server_command="$3"
  shift 3
  local server_args=("$@")

  local mcp_file="$project_root/.mcp.json"

  # Already registered?
  if [[ -f "$mcp_file" ]] && grep -q "\"$server_name\"" "$mcp_file" 2>/dev/null; then
    return 0
  fi

  # Build args JSON array
  local args_json="["
  local first=true
  for arg in "${server_args[@]}"; do
    if $first; then first=false; else args_json+=", "; fi
    args_json+="\"$arg\""
  done
  args_json+="]"

  if command -v jq &>/dev/null; then
    _moira_mcp_merge_jq "$mcp_file" "$server_name" "$server_command" "$args_json"
  else
    _moira_mcp_merge_fallback "$mcp_file" "$server_name" "$server_command" "$args_json"
  fi
}

# ── Internal: jq-based MCP merge ─────────────────────────────────────
_moira_mcp_merge_jq() {
  local mcp_file="$1"
  local name="$2"
  local cmd="$3"
  local args_json="$4"

  if [[ ! -f "$mcp_file" ]] || [[ ! -s "$mcp_file" ]]; then
    jq -n --arg name "$name" --arg cmd "$cmd" --argjson args "$args_json" \
      '{ mcpServers: { ($name): { command: $cmd, args: $args } } }' > "$mcp_file"
    return 0
  fi

  local tmpfile
  tmpfile=$(mktemp)

  jq --arg name "$name" --arg cmd "$cmd" --argjson args "$args_json" \
    '.mcpServers[$name] = { command: $cmd, args: $args }' "$mcp_file" > "$tmpfile" 2>/dev/null

  if [[ $? -eq 0 ]] && [[ -s "$tmpfile" ]]; then
    mv "$tmpfile" "$mcp_file"
  else
    rm -f "$tmpfile"
    echo "Warning: jq merge failed for .mcp.json — falling back to manual merge" >&2
    _moira_mcp_merge_fallback "$mcp_file" "$name" "$cmd" "$args_json"
  fi
}

# ── Internal: fallback MCP merge (no jq) ─────────────────────────────
_moira_mcp_merge_fallback() {
  local mcp_file="$1"
  local name="$2"
  local cmd="$3"
  local args_json="$4"

  if [[ ! -f "$mcp_file" ]] || [[ ! -s "$mcp_file" ]]; then
    cat > "$mcp_file" << MCPEOF
{
  "mcpServers": {
    "$name": {
      "command": "$cmd",
      "args": $args_json
    }
  }
}
MCPEOF
    return 0
  fi

  echo "Warning: Cannot safely merge into existing .mcp.json without jq" >&2
  echo "Please add the following to your .mcp.json manually:" >&2
  echo "  \"$name\": { \"command\": \"$cmd\", \"args\": $args_json }" >&2
  return 1
}

# ── moira_settings_remove_mcp <project_root> <server_name> ───────────
# Remove an MCP server entry from .mcp.json.
moira_settings_remove_mcp() {
  local project_root="$1"
  local server_name="$2"
  local mcp_file="$project_root/.mcp.json"

  if [[ ! -f "$mcp_file" ]]; then
    return 0
  fi

  if ! grep -q "\"$server_name\"" "$mcp_file" 2>/dev/null; then
    return 0
  fi

  if command -v jq &>/dev/null; then
    local tmpfile
    tmpfile=$(mktemp)

    jq --arg name "$server_name" 'del(.mcpServers[$name])' "$mcp_file" > "$tmpfile" 2>/dev/null

    if [[ $? -eq 0 ]] && [[ -s "$tmpfile" ]]; then
      mv "$tmpfile" "$mcp_file"
    else
      rm -f "$tmpfile"
      echo "Warning: Cannot safely remove MCP server from .mcp.json without working jq" >&2
      return 1
    fi
  else
    echo "Warning: Cannot safely remove MCP server from .mcp.json without jq — please edit manually" >&2
    return 1
  fi
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
