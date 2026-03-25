#!/usr/bin/env bash
# test-xref-manifest.sh — Tier 1: Cross-reference manifest validation
# Verifies xref-manifest.yaml entries against actual file content.
# Source: Phase 11 spec D9

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Resolve source root (2 levels up from tests/tier1/ → src/)
SRC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Resolve repo root (3 levels up from tests/tier1/ → moira/)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Manifest location (source, not installed)
MANIFEST="$SRC_ROOT/global/core/xref-manifest.yaml"

echo "=== Xref Manifest Validation ==="

# ── Test: manifest exists ─────────────────────────────────────────────
assert_file_exists "$MANIFEST" "xref-manifest.yaml exists"

# ── Test: manifest has entries ────────────────────────────────────────
assert_file_contains "$MANIFEST" "^entries:" "manifest has entries section"

# ── Test: each entry has required fields ──────────────────────────────
entry_count=$(grep -c "^  - id:" "$MANIFEST" 2>/dev/null || echo 0)
if [[ "$entry_count" -ge 1 ]]; then
  pass "manifest has $entry_count entries"
else
  fail "manifest has no entries"
fi

# Check required fields for each entry
for field in "id:" "description:" "canonical_source:" "dependents:"; do
  count=$(grep -c "$field" "$MANIFEST" 2>/dev/null || echo 0)
  if [[ "$count" -ge "$entry_count" ]]; then
    pass "all entries have '$field' field"
  else
    fail "not all entries have '$field' field (found $count, expected >= $entry_count)"
  fi
done

# Helper: check if a path (possibly with wildcards) resolves to real files
_check_path_exists() {
  local base="$1"
  local rel_path="$2"
  local label="$3"

  if [[ "$rel_path" == *"*"* ]]; then
    # Wildcard: use compgen to resolve
    local matches
    matches=$(compgen -G "$base/$rel_path" 2>/dev/null | head -1) || true
    if [[ -n "$matches" ]]; then
      pass "$label (wildcard): $rel_path"
    else
      fail "$label not found (wildcard): $rel_path"
    fi
  else
    if [[ -f "$base/$rel_path" ]]; then
      pass "$label: $rel_path"
    else
      fail "$label not found: $rel_path"
    fi
  fi
}

# ── Test: canonical source files exist ────────────────────────────────
while IFS= read -r line; do
  if [[ "$line" =~ canonical_source:\ \"(.+)\" ]]; then
    _check_path_exists "$REPO_ROOT" "${BASH_REMATCH[1]}" "canonical source exists"
  fi
done < "$MANIFEST"

# ── Test: dependent files exist ───────────────────────────────────────
while IFS= read -r line; do
  if [[ "$line" =~ file:\ \"(.+)\" ]]; then
    _check_path_exists "$REPO_ROOT" "${BASH_REMATCH[1]}" "dependent exists"
  fi
done < "$MANIFEST"

# ── Test: xref-001 value_must_match spot-check ───────────────────────
# Budget defaults: budgets.schema.yaml classifier=20000 should match budget.sh
classifier_schema=$(grep "default: 20000" "$REPO_ROOT/src/schemas/budgets.schema.yaml" 2>/dev/null | head -1)
classifier_budget=$(grep "_MOIRA_BUDGET_DEFAULTS_classifier=20000" "$REPO_ROOT/src/global/lib/budget.sh" 2>/dev/null | head -1)
if [[ -n "$classifier_schema" && -n "$classifier_budget" ]]; then
  pass "xref-001: classifier budget 20000 matches between schema and budget.sh"
else
  fail "xref-001: classifier budget value mismatch"
fi

# ── Test: xref-002 enum_must_match spot-check ─────────────────────────
# Pipeline step "classification" should appear in state.sh valid_steps
if grep -q "classification" "$REPO_ROOT/src/global/lib/state.sh" 2>/dev/null; then
  pass "xref-002: 'classification' step found in state.sh valid_steps"
else
  fail "xref-002: 'classification' step not found in state.sh"
fi
# And in current.schema.yaml step enum
if grep -q "classification" "$REPO_ROOT/src/schemas/current.schema.yaml" 2>/dev/null; then
  pass "xref-002: 'classification' step found in current.schema.yaml"
else
  fail "xref-002: 'classification' step not found in current.schema.yaml"
fi

# ── Test: xref-003 names_must_match spot-check ───────────────────────
# Agent name "apollo" should be in knowledge-access-matrix keys
if grep -q "apollo:" "$REPO_ROOT/src/global/core/knowledge-access-matrix.yaml" 2>/dev/null; then
  pass "xref-003: 'apollo' found in knowledge-access-matrix"
else
  fail "xref-003: 'apollo' not found in knowledge-access-matrix"
fi
# And in telemetry role enum
if grep -q "classifier" "$REPO_ROOT/src/schemas/telemetry.schema.yaml" 2>/dev/null; then
  pass "xref-003: 'classifier' role found in telemetry.schema.yaml"
else
  fail "xref-003: 'classifier' role not found in telemetry.schema.yaml"
fi
# Role file exists
if [[ -f "$REPO_ROOT/src/global/core/rules/roles/apollo.yaml" ]]; then
  pass "xref-003: apollo.yaml role file exists"
else
  fail "xref-003: apollo.yaml role file not found"
fi

# ── Test: xref-017 exists and references mcp.sh ─────────────────────
if grep -q "xref-017" "$MANIFEST" 2>/dev/null; then
  pass "xref-017: entry exists in manifest"
else
  fail "xref-017: entry not found in manifest"
fi

# xref-017 canonical source should be mcp.sh
xref017_block=$(sed -n '/id: xref-017/,/^  - id:/p' "$MANIFEST" 2>/dev/null)
if echo "$xref017_block" | grep -q "mcp.sh"; then
  pass "xref-017: references mcp.sh as canonical source"
else
  fail "xref-017: missing mcp.sh canonical source"
fi

# xref-017 should track 15 tools
if echo "$xref017_block" | grep -q "15 Ariadne"; then
  pass "xref-017: tracks 15 Ariadne tools"
else
  fail "xref-017: missing 15 Ariadne tool count in values_tracked"
fi

test_summary
