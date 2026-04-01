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

  # The full Moira hook + permissions configuration to inject
  local moira_hooks_json
  moira_hooks_json=$(cat <<'HOOKJSON'
{
  "permissions": {
    "allow": [
      "Read(/.claude/moira/**)",
      "Write(/.claude/moira/**)",
      "Edit(/.claude/moira/**)",
      "Glob(/.claude/moira/**)",
      "Grep(/.claude/moira/**)",
      "Bash(mkdir */.claude/moira/*)",
      "Bash(mkdir -p */.claude/moira/*)",
      "Bash(cp */.claude/moira/*)",
      "Bash(mv */.claude/moira/*)",
      "Bash(rm */.claude/moira/*)",
      "Bash(chmod */.claude/moira/*)",
      "Bash(cat */.claude/moira/*)",
      "Bash(ls */.claude/moira/*)",
      "Bash(bash */.claude/moira/*)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/task-submit.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/gate-context.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/pipeline-dispatch.sh"
          }
        ]
      },
      {
        "matcher": "Read|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/guard-prevent.sh"
          }
        ]
      }
    ],
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
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/graph-update.sh"
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/pipeline-tracker.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/pipeline-stop-guard.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/compact-reinject.sh"
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/agent-inject.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/agent-output-validate.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/artifact-validate.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/agent-done.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/graph-validate.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/session-cleanup.sh"
          }
        ]
      }
    ]
  }
}
HOOKJSON
)

  # Check if ALL Moira hooks + permissions are already registered (idempotent)
  # If any hook or permission is missing, re-merge (handles upgrades from older installations)
  if [[ -f "$settings_file" ]] && \
     grep -q 'moira/hooks/task-submit.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/guard.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/guard-prevent.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/pipeline-dispatch.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/pipeline-tracker.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/pipeline-stop-guard.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/compact-reinject.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/agent-inject.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/agent-output-validate.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/artifact-validate.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/agent-done.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/graph-update.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/graph-validate.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/session-cleanup.sh' "$settings_file" 2>/dev/null && \
     grep -q 'moira/hooks/gate-context.sh' "$settings_file" 2>/dev/null && \
     grep -q 'Write(/.claude/moira/' "$settings_file" 2>/dev/null && \
     grep -q 'Glob(/.claude/moira/' "$settings_file" 2>/dev/null && \
     grep -q 'Bash(mkdir' "$settings_file" 2>/dev/null; then
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

  if [[ ! -f "$settings_file" ]] || [[ ! -s "$settings_file" ]]; then
    # No existing file — write the full hooks JSON
    echo "$moira_hooks_json" | jq '.' > "$settings_file"
    return 0
  fi

  # File exists — remove any existing Moira hooks, then add the full set
  local tmpfile
  tmpfile=$(mktemp)

  jq --argjson new_hooks "$(echo "$moira_hooks_json" | jq '.hooks')" \
     --argjson new_perms "$(echo "$moira_hooks_json" | jq '.permissions')" '
    # Remove existing Moira entries from all hook event types
    def remove_moira:
      if . then [.[] | .hooks = [.hooks[] | select(.command | contains("moira/hooks/") | not)] | select(.hooks | length > 0)] else [] end;

    # Remove existing Moira permission entries
    def remove_moira_perms:
      if . then [.[] | select(contains(".claude/moira/") | not)] else [] end;

    # Merge permissions (additive, deduplicated)
    .permissions = (.permissions // {}) |
    .permissions.allow = ((.permissions.allow | remove_moira_perms) + ($new_perms.allow // []) | unique) |

    .hooks = (.hooks // {}) |
    .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit | remove_moira) |
    .hooks.PreToolUse = (.hooks.PreToolUse | remove_moira) |
    .hooks.PostToolUse = (.hooks.PostToolUse | remove_moira) |
    .hooks.Stop = (.hooks.Stop | remove_moira) |
    .hooks.SessionStart = (.hooks.SessionStart | remove_moira) |
    .hooks.SubagentStart = (.hooks.SubagentStart | remove_moira) |
    .hooks.SubagentStop = (.hooks.SubagentStop | remove_moira) |
    .hooks.TaskCompleted = (.hooks.TaskCompleted | remove_moira) |
    .hooks.SessionEnd = (.hooks.SessionEnd | remove_moira) |

    # Add Moira hook entries
    .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit + ($new_hooks.UserPromptSubmit // [])) |
    .hooks.PreToolUse = (.hooks.PreToolUse + ($new_hooks.PreToolUse // [])) |
    .hooks.PostToolUse = (.hooks.PostToolUse + ($new_hooks.PostToolUse // [])) |
    .hooks.Stop = (.hooks.Stop + ($new_hooks.Stop // [])) |
    .hooks.SessionStart = (.hooks.SessionStart + ($new_hooks.SessionStart // [])) |
    .hooks.SubagentStart = (.hooks.SubagentStart + ($new_hooks.SubagentStart // [])) |
    .hooks.SubagentStop = (.hooks.SubagentStop + ($new_hooks.SubagentStop // [])) |
    .hooks.TaskCompleted = (.hooks.TaskCompleted + ($new_hooks.TaskCompleted // [])) |
    .hooks.SessionEnd = (.hooks.SessionEnd + ($new_hooks.SessionEnd // []))
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
  if grep -q '"hooks"' "$settings_file" 2>/dev/null; then
    # Existing hooks — too complex to merge safely without jq
    echo "Warning: Cannot safely merge Moira hooks into existing settings.json without jq" >&2
    echo "Please install jq and re-run install, or add hooks manually." >&2
    echo "Required hooks: guard.sh, budget-track.sh, pipeline-dispatch.sh, pipeline-tracker.sh, pipeline-stop-guard.sh" >&2
    return 1
  fi

  # No hooks section — insert before the final closing brace
  local tmpfile
  tmpfile=$(mktemp)

  local content
  content=$(cat "$settings_file")

  # Strip trailing } and any trailing whitespace
  local trimmed
  trimmed=$(echo "$content" | sed '$ s/}[[:space:]]*$//')

  {
    echo "$trimmed,"
    cat <<'HOOKS'
  "permissions": {
    "allow": [
      "Read(/.claude/moira/**)",
      "Write(/.claude/moira/**)",
      "Edit(/.claude/moira/**)",
      "Glob(/.claude/moira/**)",
      "Grep(/.claude/moira/**)",
      "Bash(mkdir */.claude/moira/*)",
      "Bash(mkdir -p */.claude/moira/*)",
      "Bash(cp */.claude/moira/*)",
      "Bash(mv */.claude/moira/*)",
      "Bash(rm */.claude/moira/*)",
      "Bash(chmod */.claude/moira/*)",
      "Bash(cat */.claude/moira/*)",
      "Bash(ls */.claude/moira/*)",
      "Bash(bash */.claude/moira/*)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/task-submit.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/gate-context.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/pipeline-dispatch.sh"
          }
        ]
      },
      {
        "matcher": "Read|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/guard-prevent.sh"
          }
        ]
      }
    ],
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
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/graph-update.sh"
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/pipeline-tracker.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/pipeline-stop-guard.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/compact-reinject.sh"
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/agent-inject.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/agent-output-validate.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/artifact-validate.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/agent-done.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/graph-validate.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/session-cleanup.sh"
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

# ── moira_settings_register_global_permissions ───────────────────────
# Register global read permissions for ~/.claude/moira/ in user-level
# ~/.claude/settings.json. Subagents need to read role files, templates,
# pipelines, and rules from the global install without permission prompts.
# Idempotent — safe to re-run.
moira_settings_register_global_permissions() {
  local settings_file="$HOME/.claude/settings.json"

  mkdir -p "$HOME/.claude"

  # Already registered?
  if [[ -f "$settings_file" ]] && grep -q 'Read(~/.claude/moira/' "$settings_file" 2>/dev/null; then
    return 0
  fi

  local perm_entry='Read(~/.claude/moira/**)'

  if command -v jq &>/dev/null; then
    if [[ ! -f "$settings_file" ]] || [[ ! -s "$settings_file" ]]; then
      jq -n --arg perm "$perm_entry" '{ permissions: { allow: [$perm] } }' > "$settings_file"
    else
      local tmpfile
      tmpfile=$(mktemp)
      jq --arg perm "$perm_entry" '
        .permissions = (.permissions // {}) |
        .permissions.allow = ((.permissions.allow // []) + [$perm] | unique)
      ' "$settings_file" > "$tmpfile" 2>/dev/null
      if [[ $? -eq 0 ]] && [[ -s "$tmpfile" ]]; then
        mv "$tmpfile" "$settings_file"
      else
        rm -f "$tmpfile"
        echo "Warning: Could not register global permissions — please add manually to ~/.claude/settings.json:" >&2
        echo '  "permissions": { "allow": ["Read(~/.claude/moira/**"] }' >&2
        return 1
      fi
    fi
  else
    echo "Warning: jq not found — please add global permissions to ~/.claude/settings.json manually:" >&2
    echo '  "permissions": { "allow": ["Read(~/.claude/moira/**"] }' >&2
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
      # Helper: remove Moira hook entries from a hook event array
      def remove_moira:
        if . then
          [.[] |
            .hooks = [.hooks[] | select(.command | contains("moira/hooks/") | not)] |
            select(.hooks | length > 0)
          ]
        else [] end;

      # Remove from all event types
      (if .hooks.UserPromptSubmit then .hooks.UserPromptSubmit |= remove_moira else . end) |
      (if .hooks.PreToolUse then .hooks.PreToolUse |= remove_moira else . end) |
      (if .hooks.PostToolUse then .hooks.PostToolUse |= remove_moira else . end) |
      (if .hooks.Stop then .hooks.Stop |= remove_moira else . end) |
      (if .hooks.SessionStart then .hooks.SessionStart |= remove_moira else . end) |
      (if .hooks.SubagentStart then .hooks.SubagentStart |= remove_moira else . end) |
      (if .hooks.SubagentStop then .hooks.SubagentStop |= remove_moira else . end) |
      (if .hooks.TaskCompleted then .hooks.TaskCompleted |= remove_moira else . end) |
      (if .hooks.SessionEnd then .hooks.SessionEnd |= remove_moira else . end) |

      # Remove Moira permissions
      (if .permissions.allow then .permissions.allow |= [.[] | select(contains(".claude/moira/") | not)] else . end) |
      (if .permissions.allow and (.permissions.allow | length) == 0 then del(.permissions.allow) else . end) |
      (if .permissions and (.permissions | length) == 0 then del(.permissions) else . end) |

      # Clean up empty arrays and objects
      (if .hooks.UserPromptSubmit and (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end) |
      (if .hooks.PreToolUse and (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end) |
      (if .hooks.PostToolUse and (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end) |
      (if .hooks.Stop and (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end) |
      (if .hooks.SessionStart and (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end) |
      (if .hooks.SubagentStart and (.hooks.SubagentStart | length) == 0 then del(.hooks.SubagentStart) else . end) |
      (if .hooks.SubagentStop and (.hooks.SubagentStop | length) == 0 then del(.hooks.SubagentStop) else . end) |
      (if .hooks.TaskCompleted and (.hooks.TaskCompleted | length) == 0 then del(.hooks.TaskCompleted) else . end) |
      (if .hooks.SessionEnd and (.hooks.SessionEnd | length) == 0 then del(.hooks.SessionEnd) else . end) |
      (if .hooks and (.hooks | length) == 0 then del(.hooks) else . end)
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
    echo "Remove all entries containing 'moira/hooks/'" >&2
    return 1
  fi
}
