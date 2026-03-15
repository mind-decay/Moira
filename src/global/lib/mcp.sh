#!/usr/bin/env bash
# mcp.sh — MCP registry reading and querying for Moira
# Parses mcp-registry.yaml, provides tool metadata lookups,
# generates registry from scanner output.
#
# Responsibilities: MCP registry logic ONLY
# Does NOT handle state transitions (that's state.sh)
# Does NOT read project files (Art 1.1) — only .claude/moira/ config

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_MCP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_MCP_LIB_DIR}/yaml-utils.sh"

# Default token estimate when nothing else is available
_MOIRA_MCP_DEFAULT_TOKEN_ESTIMATE=5000

# ── moira_mcp_registry_exists <project_root> ──────────────────────────
# Check if MCP registry exists and is non-empty.
# Returns 0 if registry exists and has content, 1 otherwise.
moira_mcp_registry_exists() {
  local project_root="$1"
  local registry="${project_root}/.claude/moira/config/mcp-registry.yaml"

  if [[ -f "$registry" && -s "$registry" ]]; then
    return 0
  fi
  return 1
}

# ── moira_mcp_is_enabled <project_root> ───────────────────────────────
# Check if MCP is enabled in project config.
# Returns 0 if enabled, 1 if disabled.
moira_mcp_is_enabled() {
  local project_root="$1"
  local config="${project_root}/.claude/moira/config.yaml"

  if [[ ! -f "$config" ]]; then
    return 1
  fi

  local enabled
  enabled=$(moira_yaml_get "$config" "mcp.enabled" 2>/dev/null) || true

  if [[ "$enabled" == "true" ]]; then
    return 0
  fi
  return 1
}

# ── moira_mcp_list_servers <project_root> ─────────────────────────────
# List all registered MCP server names (one per line).
moira_mcp_list_servers() {
  local project_root="$1"
  local registry="${project_root}/.claude/moira/config/mcp-registry.yaml"

  if [[ ! -f "$registry" ]]; then
    return 1
  fi

  # Parse top-level keys under servers: (indent=2, not starting with -)
  awk '
  BEGIN { in_servers=0 }
  /^servers:/ { in_servers=1; next }
  in_servers && /^[^ ]/ { exit }
  in_servers && /^  [a-zA-Z_]/ {
    line = $0
    gsub(/^  /, "", line)
    gsub(/:.*/, "", line)
    print line
  }
  ' "$registry"
}

# ── moira_mcp_get_tool_info <project_root> <server> <tool> ────────────
# Get metadata for a specific MCP tool.
# Outputs key: value pairs for purpose, cost, reliability, when_to_use,
# when_NOT_to_use, token_estimate.
# Returns 1 if server/tool not found.
moira_mcp_get_tool_info() {
  local project_root="$1"
  local server="$2"
  local tool="$3"
  local registry="${project_root}/.claude/moira/config/mcp-registry.yaml"

  if [[ ! -f "$registry" ]]; then
    return 1
  fi

  local result
  result=$(awk -v srv="$server" -v tl="$tool" '
  BEGIN { in_servers=0; in_server=0; in_tools=0; in_tool=0; found=0 }
  /^servers:/ { in_servers=1; next }
  in_servers && /^[^ ]/ { exit }

  # Match server name at indent 2
  in_servers && /^  [a-zA-Z_]/ {
    line = $0; gsub(/^  /, "", line); gsub(/:.*/, "", line)
    if (line == srv) { in_server=1 } else { in_server=0 }
    in_tools=0; in_tool=0
    next
  }

  # Match tools: at indent 4
  in_server && /^    tools:/ { in_tools=1; next }
  in_server && /^    [a-zA-Z]/ && !/^    tools:/ { in_tools=0; in_tool=0 }

  # Match tool name at indent 6
  in_tools && /^      [a-zA-Z_]/ {
    line = $0; gsub(/^      /, "", line); gsub(/:.*/, "", line)
    if (line == tl) { in_tool=1; found=1 } else if (in_tool) { exit }
    next
  }

  # Collect tool metadata at indent 8
  in_tool && /^        [a-zA-Z_]/ {
    line = $0; gsub(/^        /, "", line)
    print line
  }

  END { if (!found) exit 1 }
  ' "$registry" 2>/dev/null)

  local rc=$?
  if [[ $rc -ne 0 ]]; then
    return 1
  fi

  echo "$result"
}

# ── moira_mcp_get_token_estimate <project_root> <server> <tool> ───────
# Get token estimate for a specific MCP tool call.
# Fallback chain: registry token_estimate → budgets.yaml mcp_estimates → default 5000
moira_mcp_get_token_estimate() {
  local project_root="$1"
  local server="$2"
  local tool="$3"
  local moira_dir="${project_root}/.claude/moira"

  # Try registry first
  local info
  info=$(moira_mcp_get_tool_info "$project_root" "$server" "$tool" 2>/dev/null) || true
  if [[ -n "$info" ]]; then
    local estimate
    estimate=$(echo "$info" | awk -F': ' '/^token_estimate:/ { print $2 }')
    if [[ -n "$estimate" && "$estimate" != "null" ]]; then
      echo "$estimate"
      return 0
    fi
  fi

  # Try budgets.yaml: mcp_estimates.{server}_{tool}
  local budgets="${moira_dir}/config/budgets.yaml"
  if [[ -f "$budgets" ]]; then
    local budget_key="${server}_${tool}"
    # Use awk to find mcp_estimates.{key}
    local budget_est
    budget_est=$(awk -v key="$budget_key" '
    BEGIN { in_mcp=0 }
    /^mcp_estimates:/ { in_mcp=1; next }
    in_mcp && /^[^ ]/ { exit }
    in_mcp && $0 ~ "^  " key ":" {
      line = $0
      sub(/^[^:]+:[[:space:]]*/, "", line)
      print line
    }
    ' "$budgets" 2>/dev/null)

    if [[ -n "$budget_est" ]]; then
      echo "$budget_est"
      return 0
    fi

    # Try default_call
    local default_est
    default_est=$(awk '
    BEGIN { in_mcp=0 }
    /^mcp_estimates:/ { in_mcp=1; next }
    in_mcp && /^[^ ]/ { exit }
    in_mcp && /^  default_call:/ {
      line = $0
      sub(/^[^:]+:[[:space:]]*/, "", line)
      print line
    }
    ' "$budgets" 2>/dev/null)

    if [[ -n "$default_est" ]]; then
      echo "$default_est"
      return 0
    fi
  fi

  # Final fallback
  echo "$_MOIRA_MCP_DEFAULT_TOKEN_ESTIMATE"
}

# ── moira_mcp_generate_registry <project_root> <scan_results_dir> ─────
# Generate mcp-registry.yaml from scanner output frontmatter.
# Reads MCP scan results, writes to config/mcp-registry.yaml,
# sets mcp.enabled: true in config.yaml if servers found.
moira_mcp_generate_registry() {
  local project_root="$1"
  local scan_results_dir="$2"
  local moira_dir="${project_root}/.claude/moira"
  local registry="${moira_dir}/config/mcp-registry.yaml"
  local scan_file="${scan_results_dir}/mcp-scan.md"

  if [[ ! -f "$scan_file" ]]; then
    echo "Warning: MCP scan results not found: $scan_file" >&2
    return 1
  fi

  # Extract frontmatter between --- markers
  local frontmatter
  frontmatter=$(awk '
  BEGIN { in_fm=0; started=0 }
  /^---[[:space:]]*$/ {
    if (!started) { started=1; in_fm=1; next }
    else { exit }
  }
  in_fm { print }
  ' "$scan_file")

  if [[ -z "$frontmatter" ]]; then
    echo "Warning: no frontmatter found in MCP scan results" >&2
    return 1
  fi

  # Extract mcp_servers section and convert to registry format
  # The scanner outputs under mcp_servers: key, registry uses servers: key
  local servers_yaml
  servers_yaml=$(echo "$frontmatter" | awk '
  BEGIN { in_mcp=0; depth=0 }
  /^mcp_servers:/ { in_mcp=1; print "servers:"; next }
  in_mcp { print }
  ')

  if [[ -z "$servers_yaml" || "$servers_yaml" == "servers:" ]]; then
    echo "Warning: no MCP servers found in scan results" >&2
    return 1
  fi

  # Write registry
  mkdir -p "$(dirname "$registry")"
  echo "# MCP Tools Registry" > "$registry"
  echo "# Generated by /moira:init — edit to customize tool guidelines" >> "$registry"
  echo "" >> "$registry"
  echo "$servers_yaml" >> "$registry"

  # Count servers
  local server_count
  server_count=$(echo "$servers_yaml" | grep -c '^  [a-zA-Z]' 2>/dev/null) || true

  # Count tools
  local tool_count
  tool_count=$(echo "$servers_yaml" | grep -c '^      [a-zA-Z]' 2>/dev/null) || true

  # Enable MCP in config
  local config="${moira_dir}/config.yaml"
  if [[ -f "$config" ]]; then
    moira_yaml_set "$config" "mcp.enabled" "true"
  fi

  echo "MCP registry: ${server_count:-0} servers, ${tool_count:-0} tools cataloged"
}
