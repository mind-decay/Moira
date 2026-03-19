#!/usr/bin/env bash
# test-yaml-schemas.sh — Verify YAML schema operations
# Tests moira_yaml_init, moira_yaml_validate, moira_yaml_get, moira_yaml_set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"

# Derive schema dir: schemas live alongside global/ in source tree
if [[ -d "$MOIRA_HOME/lib" && ! -d "$MOIRA_HOME/schemas" && -d "$(dirname "$MOIRA_HOME")/schemas" ]]; then
  export MOIRA_SCHEMA_DIR="$(dirname "$MOIRA_HOME")/schemas"
else
  export MOIRA_SCHEMA_DIR="$MOIRA_HOME/schemas"
fi

# Source yaml-utils from installed location
source "$MOIRA_HOME/lib/yaml-utils.sh"

# Create temp directory for test files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Test: init + validate round-trip for each schema ──────────────────
schemas=(config current status manifest queue locks)
for schema in "${schemas[@]}"; do
  target="$TMPDIR/${schema}.yaml"
  if moira_yaml_init "$schema" "$target" 2>/dev/null; then
    pass "moira_yaml_init $schema creates file"
  else
    fail "moira_yaml_init $schema failed"
    continue
  fi

  if moira_yaml_validate "$target" "$schema" 2>/dev/null; then
    pass "moira_yaml_validate $schema passes on defaults"
  else
    fail "moira_yaml_validate $schema fails on defaults"
  fi
done

# ── Test: moira_yaml_get reads correct defaults from config ───────────
config_file="$TMPDIR/config.yaml"
moira_yaml_init "config" "$config_file" 2>/dev/null

# 1-level get
val=$(moira_yaml_get "$config_file" "version" 2>/dev/null) || true
assert_equals "$val" "1.0" "get version returns 1.0"

# 2-level get
val=$(moira_yaml_get "$config_file" "project.stack" 2>/dev/null) || true
assert_equals "$val" "generic" "get project.stack returns generic"

# 3-level get
val=$(moira_yaml_get "$config_file" "budgets.per_agent.classifier" 2>/dev/null) || true
assert_equals "$val" "20000" "get budgets.per_agent.classifier returns 20000"

# ── Test: moira_yaml_set changes a value ──────────────────────────────
moira_yaml_set "$config_file" "project.stack" "nextjs"
val=$(moira_yaml_get "$config_file" "project.stack" 2>/dev/null) || true
assert_equals "$val" "nextjs" "set+get project.stack roundtrip"

# 3-level set
moira_yaml_set "$config_file" "budgets.per_agent.classifier" "30000"
val=$(moira_yaml_get "$config_file" "budgets.per_agent.classifier" 2>/dev/null) || true
assert_equals "$val" "30000" "set+get 3-level dot-path roundtrip"

# ── Test: validate rejects missing required field ─────────────────────
bad_file="$TMPDIR/bad-config.yaml"
cp "$config_file" "$bad_file"
# Remove version line (required field)
sed -i.bak '/^version:/d' "$bad_file"
if moira_yaml_validate "$bad_file" "config" 2>/dev/null; then
  fail "validate should reject missing required field 'version'"
else
  pass "validate rejects missing required field 'version'"
fi

# ── Test: validate rejects invalid enum ───────────────────────────────
bad_enum_file="$TMPDIR/bad-enum.yaml"
cp "$config_file" "$bad_enum_file"
moira_yaml_set "$bad_enum_file" "quality.mode" "invalid_value"
if moira_yaml_validate "$bad_enum_file" "config" 2>/dev/null; then
  fail "validate should reject invalid enum for quality.mode"
else
  pass "validate rejects invalid enum for quality.mode"
fi

# ── Test: array field read ────────────────────────────────────────────
# Config doesn't have inline arrays by default, so create a temp file with one
array_file="$TMPDIR/array-test.yaml"
cat > "$array_file" <<'ARRAYEOF'
top_level_array: [alpha, beta, gamma]
nested:
  items: [one, two, three]
ARRAYEOF
val=$(moira_yaml_get "$array_file" "top_level_array" 2>/dev/null) || true
if [[ "$val" == *"alpha"* && "$val" == *"gamma"* ]]; then
  pass "array field read: inline array parsed correctly"
else
  fail "array field read: got '$val'"
fi

# ── Test: telemetry schema has mcp_calls section (Phase 10) ──────────
if [[ -f "$MOIRA_SCHEMA_DIR/telemetry.schema.yaml" ]]; then
  if grep -q "mcp_calls:" "$MOIRA_SCHEMA_DIR/telemetry.schema.yaml" 2>/dev/null; then
    pass "telemetry schema has mcp_calls section"
  else
    fail "telemetry schema missing mcp_calls section"
  fi
fi

test_summary
