#!/usr/bin/env bash
# test-fn-mcp.sh — Functional tests for mcp.sh
# Tests registry check, server listing, tool info, token estimates.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: mcp.sh (functional)"

source "$SRC_LIB_DIR/mcp.sh"
set +e

# ── Setup: create MCP registry ───────────────────────────────────────

mcp_root="$TEMP_DIR/mcp-project"
mkdir -p "$mcp_root/.moira/config"

# has_infrastructure greps for literal 'infrastructure: true'
cat > "$mcp_root/.moira/config/mcp-registry.yaml" << 'EOF'
servers:
  ariadne:
    infrastructure: true
    tools:
      ariadne_overview:
        purpose: "Get project dependency graph overview"
        cost: low
        reliability: high
        token_estimate: 2000
      ariadne_hotspots:
        purpose: "Find code hotspots"
        cost: medium
        reliability: high
        token_estimate: 5000
  external-api:
    infrastructure: false
    tools:
      fetch_data:
        purpose: "Fetch external data"
        cost: high
        reliability: medium
        token_estimate: 10000
EOF

# Config at project root level for mcp_is_enabled
cat > "$mcp_root/.moira/config.yaml" << 'EOF'
version: 1.0
mcp:
  enabled: true
EOF
cat > "$mcp_root/.moira/config/config.yaml" << 'EOF'
version: 1.0
mcp:
  enabled: true
EOF

# ── moira_mcp_registry_exists: exists ────────────────────────────────

run_fn moira_mcp_registry_exists "$mcp_root"
assert_exit_zero "registry_exists: exists → exit 0"

# ── moira_mcp_registry_exists: missing ───────────────────────────────

run_fn moira_mcp_registry_exists "$TEMP_DIR/no-project"
assert_exit_nonzero "registry_exists: missing → exit 1"

# ── moira_mcp_is_enabled: enabled ────────────────────────────────────

run_fn moira_mcp_is_enabled "$mcp_root"
assert_exit_zero "is_enabled: true → exit 0"

# ── moira_mcp_is_enabled: disabled ───────────────────────────────────

disabled_root="$TEMP_DIR/mcp-disabled"
mkdir -p "$disabled_root/.moira/config"
cat > "$disabled_root/.moira/config.yaml" << 'EOF'
mcp:
  enabled: false
EOF
cat > "$disabled_root/.moira/config/config.yaml" << 'EOF'
mcp:
  enabled: false
EOF

run_fn moira_mcp_is_enabled "$disabled_root"
assert_exit_nonzero "is_enabled: false → exit 1"

# ── moira_mcp_list_servers: lists all servers ────────────────────────

run_fn moira_mcp_list_servers "$mcp_root"
assert_exit_zero "list_servers: exit 0"
assert_output_contains "$FN_STDOUT" "ariadne" "list_servers: includes ariadne"
assert_output_contains "$FN_STDOUT" "external-api" "list_servers: includes external-api"

# ── moira_mcp_list_servers: missing registry → error ─────────────────

run_fn moira_mcp_list_servers "$TEMP_DIR/no-project"
assert_exit_nonzero "list_servers: no registry → exit 1"

# ── moira_mcp_get_tool_info: returns metadata ────────────────────────

run_fn moira_mcp_get_tool_info "$mcp_root" "ariadne" "ariadne_overview"
assert_exit_zero "get_tool_info: exit 0"
assert_output_contains "$FN_STDOUT" "purpose:" "get_tool_info: includes purpose"
assert_output_contains "$FN_STDOUT" "token_estimate:" "get_tool_info: includes token_estimate"

# ── moira_mcp_get_tool_info: missing tool → error ────────────────────

run_fn moira_mcp_get_tool_info "$mcp_root" "ariadne" "nonexistent_tool"
assert_exit_nonzero "get_tool_info: missing tool → exit 1"

# ── moira_mcp_get_token_estimate: from registry ──────────────────────

run_fn moira_mcp_get_token_estimate "$mcp_root" "ariadne" "ariadne_overview"
assert_output_equals "$FN_STDOUT" "2000" "get_token_estimate: ariadne_overview → 2000"

run_fn moira_mcp_get_token_estimate "$mcp_root" "ariadne" "ariadne_hotspots"
assert_output_equals "$FN_STDOUT" "5000" "get_token_estimate: ariadne_hotspots → 5000"

# ── moira_mcp_get_token_estimate: missing → default 5000 ────────────

run_fn moira_mcp_get_token_estimate "$mcp_root" "ariadne" "unknown_tool"
assert_output_equals "$FN_STDOUT" "5000" "get_token_estimate: missing → default 5000"

# ── moira_mcp_has_infrastructure: has infra ──────────────────────────

run_fn moira_mcp_has_infrastructure "$mcp_root"
assert_exit_zero "has_infrastructure: greps 'infrastructure: true' → found"

# ── moira_mcp_list_infrastructure: lists infra servers ───────────────

run_fn moira_mcp_list_infrastructure "$mcp_root"
assert_exit_zero "list_infrastructure: exit 0"
assert_output_contains "$FN_STDOUT" "ariadne" "list_infrastructure: includes ariadne"
assert_output_not_contains "$FN_STDOUT" "external-api" "list_infrastructure: excludes non-infrastructure"

test_summary
