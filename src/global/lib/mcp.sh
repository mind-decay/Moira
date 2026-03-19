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
# Also merges infrastructure MCP entries (e.g., Ariadne) if present.
moira_mcp_generate_registry() {
  local project_root="$1"
  local scan_results_dir="$2"
  local moira_dir="${project_root}/.claude/moira"
  local registry="${moira_dir}/config/mcp-registry.yaml"
  local scan_file="${scan_results_dir}/mcp-scan.md"

  mkdir -p "$(dirname "$registry")"

  # Start with header
  echo "# MCP Tools Registry" > "$registry"
  echo "# Generated by /moira:init — edit to customize tool guidelines" >> "$registry"
  echo "" >> "$registry"
  echo "servers:" >> "$registry"

  local server_count=0
  local tool_count=0

  # ── Phase 1: Add infrastructure MCP (Ariadne) if available (D-108) ──
  if command -v ariadne >/dev/null 2>&1; then
    if ariadne serve --help >/dev/null 2>&1; then
      cat >> "$registry" << 'ARIADNE_EOF'
  ariadne:
    type: graph
    infrastructure: true
    tools:
      blast-radius:
        purpose: "Find files affected by changing a given file"
        cost: low
        reliability: high
        when_to_use: "Before modifying a file to understand impact"
        when_NOT_to_use: "Never — always useful for impact analysis"
        token_estimate: 500
      dependencies:
        purpose: "List direct dependencies of a file"
        cost: low
        reliability: high
        when_to_use: "When exploring what a file imports/depends on"
        when_NOT_to_use: "When you already have the file open and can see imports"
        token_estimate: 300
      dependents:
        purpose: "List files that depend on a given file"
        cost: low
        reliability: high
        when_to_use: "When assessing who uses a module before changing its API"
        when_NOT_to_use: "For broad exploration — use blast-radius instead"
        token_estimate: 300
      cycles:
        purpose: "Detect circular dependencies involving a file or cluster"
        cost: low
        reliability: high
        when_to_use: "When reviewing architecture or checking for circular imports"
        when_NOT_to_use: "For unrelated tasks — cycles are a structural concern"
        token_estimate: 400
      cluster:
        purpose: "Get files and metrics for a specific cluster"
        cost: low
        reliability: high
        when_to_use: "When exploring a module/domain to understand its scope"
        when_NOT_to_use: "When you already have the cluster view from static views"
        token_estimate: 500
      smells:
        purpose: "Detect architectural anti-patterns (god files, bottlenecks)"
        cost: low
        reliability: high
        when_to_use: "During architecture review or when reviewing large changes"
        when_NOT_to_use: "For small, localized changes"
        token_estimate: 400
ARIADNE_EOF
      server_count=$((server_count + 1))
      tool_count=$((tool_count + 6))
    fi
  fi

  # ── Phase 2: Add external MCP servers from scanner output ──
  if [[ -f "$scan_file" ]]; then
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

    if [[ -n "$frontmatter" ]]; then
      # Extract the mcp_servers block content (everything under mcp_servers:)
      # Handles variable indentation: detects indent of first child and normalizes
      local servers_content
      servers_content=$(echo "$frontmatter" | awk '
      BEGIN { in_mcp=0; base_indent=-1 }
      /^[[:space:]]*mcp_servers[[:space:]]*:/ { in_mcp=1; next }
      in_mcp {
        # Detect end: a non-blank, non-comment line at root indent (no leading space)
        if (/^[^[:space:]#]/) { exit }
        # Detect base indent from first content line
        if (base_indent < 0 && /^[[:space:]]+[a-zA-Z_]/) {
          match($0, /^[[:space:]]+/)
          base_indent = RLENGTH
        }
        # Output line re-indented: strip base_indent, add 2 spaces (for servers: child)
        if (base_indent > 0 && length($0) >= base_indent) {
          printf "  %s\n", substr($0, base_indent + 1)
        } else {
          print $0
        }
      }
      ')

      if [[ -n "$servers_content" ]]; then
        echo "$servers_content" >> "$registry"

        # Count external servers (lines at indent 2 starting with letter)
        local ext_servers
        ext_servers=$(echo "$servers_content" | grep -c '^  [a-zA-Z_]' 2>/dev/null) || true
        server_count=$((server_count + ${ext_servers:-0}))

        # Count external tools (lines at indent 6 starting with letter)
        local ext_tools
        ext_tools=$(echo "$servers_content" | grep -c '^      [a-zA-Z_]' 2>/dev/null) || true
        tool_count=$((tool_count + ${ext_tools:-0}))
      fi
    fi
  fi

  # Enable/disable MCP in config based on results
  local config="${moira_dir}/config.yaml"
  if [[ $server_count -gt 0 ]]; then
    if [[ -f "$config" ]]; then
      moira_yaml_set "$config" "mcp.enabled" "true"
    fi
  else
    # No servers at all — clean up empty registry
    if [[ -f "$config" ]]; then
      moira_yaml_set "$config" "mcp.enabled" "false"
    fi
  fi

  echo "MCP registry: ${server_count} servers, ${tool_count} tools cataloged"
}

# ── moira_mcp_has_infrastructure <project_root> ─────────────────────────
# Check if registry contains any infrastructure MCP servers.
# Returns 0 if at least one infrastructure server exists, 1 otherwise.
moira_mcp_has_infrastructure() {
  local project_root="$1"
  local registry="${project_root}/.claude/moira/config/mcp-registry.yaml"

  if [[ ! -f "$registry" ]]; then
    return 1
  fi

  grep -q 'infrastructure: true' "$registry" 2>/dev/null
}

# ── moira_mcp_list_infrastructure <project_root> ────────────────────────
# List infrastructure MCP server names (one per line).
moira_mcp_list_infrastructure() {
  local project_root="$1"
  local registry="${project_root}/.claude/moira/config/mcp-registry.yaml"

  if [[ ! -f "$registry" ]]; then
    return 1
  fi

  awk '
  BEGIN { in_servers=0; current_server="" }
  /^servers:/ { in_servers=1; next }
  in_servers && /^[^ ]/ { exit }
  in_servers && /^  [a-zA-Z_]/ {
    line = $0; gsub(/^  /, "", line); gsub(/:.*/, "", line)
    current_server = line
  }
  in_servers && /^    infrastructure:[[:space:]]*true/ {
    if (current_server != "") print current_server
  }
  ' "$registry"
}

# ── moira_mcp_format_infrastructure_section <project_root> ──────────────
# Format the "## Infrastructure Tools (Always Available)" prompt section
# for injection into agent instructions (D-115).
# Outputs the formatted markdown section to stdout.
# Returns 1 if no infrastructure servers found or MCP disabled.
moira_mcp_format_infrastructure_section() {
  local project_root="$1"
  local registry="${project_root}/.claude/moira/config/mcp-registry.yaml"

  # Check MCP enabled
  local config="${project_root}/.claude/moira/config.yaml"
  if [[ -f "$config" ]]; then
    local mcp_enabled
    mcp_enabled=$(moira_yaml_get "$config" "mcp.enabled" 2>/dev/null || echo "false")
    if [[ "$mcp_enabled" != "true" ]]; then
      return 1
    fi
  else
    return 1
  fi

  if ! moira_mcp_has_infrastructure "$project_root"; then
    return 1
  fi

  echo "## Infrastructure Tools (Always Available)"
  echo ""
  echo "The following tools are always available — use them freely for structural queries:"
  echo ""

  # Parse infrastructure servers and their tools from registry
  awk '
  BEGIN { in_servers=0; in_infra=0; current_server=""; in_tools=0 }
  /^servers:/ { in_servers=1; next }
  in_servers && /^[^ ]/ { exit }
  in_servers && /^  [a-zA-Z_]/ {
    line = $0; gsub(/^  /, "", line); gsub(/:.*/, "", line)
    current_server = line
    in_infra = 0; in_tools = 0
  }
  in_servers && /^    infrastructure:[[:space:]]*true/ { in_infra = 1 }
  in_servers && in_infra && /^    tools:/ { in_tools = 1; next }
  in_servers && in_infra && in_tools && /^      [a-zA-Z_]/ {
    tool = $0; gsub(/^      /, "", tool); gsub(/:.*/, "", tool)
    current_tool = tool
  }
  in_servers && in_infra && in_tools && /purpose:/ {
    purpose = $0; gsub(/.*purpose:[[:space:]]*"?/, "", purpose); gsub(/"[[:space:]]*$/, "", purpose)
    printf "- %s:%s — %s\n", current_server, current_tool, purpose
  }
  ' "$registry"

  echo ""
}
