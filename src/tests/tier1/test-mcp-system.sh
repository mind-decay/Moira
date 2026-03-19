#!/usr/bin/env bash
# test-mcp-system.sh — Verify Phase 9 MCP integration artifacts
# Tests registry schema, shell library, scanner template, agent rules,
# dispatch integration, quality checklist, and knowledge templates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Derive SCHEMA_DIR: schemas live alongside global/ in source tree
if [[ -d "$MOIRA_HOME/lib" && ! -d "$MOIRA_HOME/schemas" && -d "$SRC_DIR/schemas" ]]; then
  SCHEMA_DIR="$SRC_DIR/schemas"
else
  SCHEMA_DIR="$MOIRA_HOME/schemas"
fi

# ═══════════════════════════════════════════════════════════════════════
# Schema tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$SCHEMA_DIR/mcp-registry.schema.yaml" "mcp-registry.schema.yaml exists"

if [[ -f "$SCHEMA_DIR/mcp-registry.schema.yaml" ]]; then
  assert_file_contains "$SCHEMA_DIR/mcp-registry.schema.yaml" "servers" "schema: has servers top-level key"
fi

# ═══════════════════════════════════════════════════════════════════════
# Library tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/lib/mcp.sh" "mcp.sh exists"

if [[ -f "$MOIRA_HOME/lib/mcp.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/mcp.sh" 2>/dev/null; then
    pass "mcp.sh syntax valid"
  else
    fail "mcp.sh has syntax errors"
  fi

  for func in moira_mcp_registry_exists moira_mcp_is_enabled moira_mcp_list_servers \
              moira_mcp_get_tool_info moira_mcp_get_token_estimate moira_mcp_generate_registry; do
    if grep -q "$func" "$MOIRA_HOME/lib/mcp.sh" 2>/dev/null; then
      pass "mcp.sh: function $func declared"
    else
      fail "mcp.sh: function $func not found"
    fi
  done
fi

# ═══════════════════════════════════════════════════════════════════════
# Scanner tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/templates/scanners/mcp-scan.md" "mcp-scan.md exists"

if [[ -f "$MOIRA_HOME/templates/scanners/mcp-scan.md" ]]; then
  assert_file_contains "$MOIRA_HOME/templates/scanners/mcp-scan.md" "mcp_servers" "mcp-scan: has mcp_servers frontmatter key"
fi

# ═══════════════════════════════════════════════════════════════════════
# Integration tests (verify existing files still have MCP references)
# ═══════════════════════════════════════════════════════════════════════

assert_file_contains "$SCHEMA_DIR/config.schema.yaml" "mcp.enabled" "config.schema: has mcp.enabled"
assert_file_contains "$SCHEMA_DIR/config.schema.yaml" "mcp.registry_path" "config.schema: has mcp.registry_path"
assert_file_contains "$MOIRA_HOME/templates/budgets.yaml.tmpl" "mcp_estimates" "budgets.yaml.tmpl: has mcp_estimates"
assert_file_contains "$MOIRA_HOME/core/rules/roles/daedalus.yaml" "MCP" "daedalus.yaml: mentions MCP"
assert_file_contains "$MOIRA_HOME/core/rules/roles/hephaestus.yaml" "MCP" "hephaestus.yaml: mentions MCP"
assert_file_contains "$MOIRA_HOME/core/rules/roles/themis.yaml" "MCP" "themis.yaml: mentions MCP"
assert_file_contains "$MOIRA_HOME/core/rules/quality/q4-correctness.yaml" "Q4-M0" "q4-correctness: has MCP checklist items"
assert_file_contains "$MOIRA_HOME/skills/dispatch.md" "MCP" "dispatch.md: mentions MCP"

# ═══════════════════════════════════════════════════════════════════════
# Knowledge template tests
# ═══════════════════════════════════════════════════════════════════════

assert_file_exists "$MOIRA_HOME/templates/knowledge/libraries/index.md" "knowledge libraries index.md exists"
assert_file_exists "$MOIRA_HOME/templates/knowledge/libraries/summary.md" "knowledge libraries summary.md exists"
