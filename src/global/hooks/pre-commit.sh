#!/usr/bin/env bash
# Pre-commit hook — Constitutional invariant verification (Art 6.3, D-142)
# Installed to .git/hooks/pre-commit by moira init.
# Fail closed on verification failures. Fail open on internal errors.

set -uo pipefail

# --- Locate Moira installation ---
MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find project root (walk up from .git/hooks/ to project root)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Internal error handler: fail open ---
internal_error() {
  echo "WARNING [moira pre-commit]: $1 — allowing commit (fail open on internal error)" >&2
  exit 0
}

# --- Verification failure handler: fail closed ---
verification_failure() {
  echo "ERROR [moira pre-commit]: $1" >&2
  echo "Commit blocked by constitutional verification (Art 6.3)." >&2
  echo "Fix the issue above and try again, or use --no-verify to bypass (not recommended)." >&2
  exit 1
}

# --- Check 1: Constitution.md unmodified ---
# Verify Constitution.md has not been modified in this commit
# (Only the user may edit Constitution directly — CLAUDE.md rule)
if git diff --cached --name-only 2>/dev/null | grep -q "design/CONSTITUTION.md"; then
  # Constitution is being modified — this is allowed (user action), but flag it
  echo "NOTE [moira pre-commit]: design/CONSTITUTION.md is being modified in this commit." >&2
fi

# --- Check 2: Pipeline gate integrity ---
# Verify all pipeline YAMLs have required gate structure
check_pipeline_gates() {
  local pipeline_dir="$PROJECT_ROOT/src/global/core/pipelines"
  [[ -d "$pipeline_dir" ]] || return 0  # No pipelines dir = skip (partial install)

  local failed=0
  for yaml_file in "$pipeline_dir"/*.yaml; do
    [[ -f "$yaml_file" ]] || continue
    local basename
    basename=$(basename "$yaml_file")

    # Every pipeline must have a gates section
    if ! grep -q '^gates:' "$yaml_file" 2>/dev/null; then
      echo "  FAIL: $basename has no gate definitions" >&2
      failed=1
    fi
  done

  return $failed
}

if ! check_pipeline_gates 2>/dev/null; then
  verification_failure "Pipeline gate integrity check failed"
fi

# --- Check 3: xref-manifest validation ---
# Run existing Tier 1 xref test if available
XREF_TEST="$PROJECT_ROOT/src/tests/tier1/test-xref-manifest.sh"
if [[ -f "$XREF_TEST" ]]; then
  if command -v timeout &>/dev/null; then
    test_result=$(timeout 30 bash "$XREF_TEST" 2>/dev/null; echo $?)
  elif command -v gtimeout &>/dev/null; then
    test_result=$(gtimeout 30 bash "$XREF_TEST" 2>/dev/null; echo $?)
  else
    test_result=$(bash "$XREF_TEST" 2>/dev/null; echo $?)
  fi
  if [[ "${test_result##*$'\n'}" != "0" ]]; then
    verification_failure "xref-manifest validation failed (test-xref-manifest.sh)"
  fi
else
  # Test script not found — fail open (partial install)
  echo "WARNING [moira pre-commit]: test-xref-manifest.sh not found, skipping xref validation" >&2
fi

# --- Check 4: xref-manifest file references ---
# Verify xref-manifest entries reference files that exist
XREF_MANIFEST="$PROJECT_ROOT/src/global/core/xref-manifest.yaml"
if [[ -f "$XREF_MANIFEST" ]]; then
  # Extract canonical_source file paths and check they exist
  while IFS= read -r source_file; do
    # Skip glob patterns (contain *)
    [[ "$source_file" == *"*"* ]] && continue
    if [[ ! -f "$PROJECT_ROOT/$source_file" && ! -d "$PROJECT_ROOT/$source_file" ]]; then
      verification_failure "xref-manifest references non-existent file: $source_file"
    fi
  done < <(grep -E 'canonical_source:|file:' "$XREF_MANIFEST" 2>/dev/null | sed 's/.*canonical_source:[[:space:]]*//' | sed 's/.*file:[[:space:]]*//' | tr -d '"' | tr -d "'" | grep -v '^$')
fi

echo "moira pre-commit: all checks passed" >&2
exit 0
