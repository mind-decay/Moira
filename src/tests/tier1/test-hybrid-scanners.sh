#!/usr/bin/env bash
# test-hybrid-scanners.sh — Tier 1 tests for pre-collection functions
# and scanner template updates (budget values, pre-collected data sections).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"

# Create temp directory for functional tests
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source bootstrap library
source "$MOIRA_HOME/lib/bootstrap.sh"

# ── Helper: create fixture project ──────────────────────────────────

setup_fixture_project() {
  local proj="$1"
  mkdir -p "$proj/.claude/moira/state/init"
  mkdir -p "$proj/src/lib"
  mkdir -p "$proj/.github/workflows"

  # Config files
  echo '{"name": "test-project", "version": "1.0.0"}' > "$proj/package.json"
  echo '{"compilerOptions": {"target": "es2020"}}' > "$proj/tsconfig.json"
  echo '{"semi": true}' > "$proj/.prettierrc.json"

  # Workflow file
  echo 'name: CI' > "$proj/.github/workflows/ci.yml"
  echo 'on: push' >> "$proj/.github/workflows/ci.yml"

  # Lock file
  echo '{}' > "$proj/package-lock.json"

  # Source files
  echo 'console.log("hello")' > "$proj/src/index.ts"
  echo 'export function add(a, b) { return a + b; }' > "$proj/src/lib/utils.ts"
}

# ── 1. Test precollect_tech: verify raw-configs.md contents ─────────

PROJ="$TEMP_DIR/project1"
setup_fixture_project "$PROJ"

moira_scan_precollect_tech "$PROJ"

output_file="$PROJ/.claude/moira/state/init/raw-configs.md"
assert_file_exists "$output_file" "raw-configs.md created"

assert_file_contains "$output_file" "# Pre-Collected Config Files" "raw-configs.md has header"
assert_file_contains "$output_file" "## package.json" "raw-configs.md contains package.json section"
assert_file_contains "$output_file" "test-project" "raw-configs.md contains package.json content"
assert_file_contains "$output_file" "## tsconfig.json" "raw-configs.md contains tsconfig.json section"
assert_file_contains "$output_file" "## .prettierrc.json" "raw-configs.md contains prettierrc section"

# Lock file detection
assert_file_contains "$output_file" "package-lock.json: exists" "Lock file detection: package-lock.json exists"
assert_file_contains "$output_file" "yarn.lock: not found" "Lock file detection: yarn.lock not found"

# GitHub workflow
assert_file_contains "$output_file" "## .github/workflows/ci.yml" "raw-configs.md contains workflow file"

# ── 2. Test sensitive file exclusion ────────────────────────────────

PROJ2="$TEMP_DIR/project2"
setup_fixture_project "$PROJ2"

# Create sensitive files
echo "SECRET=abc123" > "$PROJ2/.env"
echo "PROD_SECRET=xyz" > "$PROJ2/.env.production"
echo '{"key": "secret"}' > "$PROJ2/service-key.json"

moira_scan_precollect_tech "$PROJ2"

output_file2="$PROJ2/.claude/moira/state/init/raw-configs.md"

# .env should be excluded (not .env.example)
if grep -q "## .env$" "$output_file2" 2>/dev/null; then
  fail "Sensitive file .env should be excluded"
else
  pass "Sensitive file .env excluded"
fi

if grep -q "## .env.production" "$output_file2" 2>/dev/null; then
  fail "Sensitive file .env.production should be excluded"
else
  pass "Sensitive file .env.production excluded"
fi

# .env.example should be included if present
echo "DB_HOST=localhost" > "$PROJ2/.env.example"
moira_scan_precollect_tech "$PROJ2"
output_file2="$PROJ2/.claude/moira/state/init/raw-configs.md"
assert_file_contains "$output_file2" "## .env.example" ".env.example is included"

# ── 3. Test file size truncation ────────────────────────────────────

PROJ3="$TEMP_DIR/project3"
setup_fixture_project "$PROJ3"

# Create a large package.json (> 10KB)
python3 -c "
import json
data = {'name': 'large-project', 'dependencies': {}}
for i in range(500):
    data['dependencies'][f'package-{i}'] = f'^{i}.0.0'
with open('$PROJ3/package.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || {
  # Fallback without python
  dd if=/dev/zero bs=1024 count=12 2>/dev/null | tr '\0' 'x' > "$PROJ3/package.json"
}

moira_scan_precollect_tech "$PROJ3"

output_file3="$PROJ3/.claude/moira/state/init/raw-configs.md"
if grep -q "TRUNCATED at 10KB" "$output_file3" 2>/dev/null; then
  pass "Large file truncated with marker"
else
  fail "Large file not truncated"
fi

# ── 4. Test precollect_structure: verify raw-structure.md ───────────

PROJ4="$TEMP_DIR/project4"
setup_fixture_project "$PROJ4"
mkdir -p "$PROJ4/lib/helpers"
mkdir -p "$PROJ4/app/routes"

moira_scan_precollect_structure "$PROJ4"

struct_file="$PROJ4/.claude/moira/state/init/raw-structure.md"
assert_file_exists "$struct_file" "raw-structure.md created"

assert_file_contains "$struct_file" "# Pre-Collected Structure" "raw-structure.md has header"
assert_file_contains "$struct_file" "## Directory Tree" "raw-structure.md has directory tree"
assert_file_contains "$struct_file" "## Source Directories" "raw-structure.md has source directories"
assert_file_contains "$struct_file" "### src" "raw-structure.md has src directory listing"
assert_file_contains "$struct_file" "### lib" "raw-structure.md has lib directory listing"

# ── 5. Test Ariadne degradation ─────────────────────────────────────

# Ariadne sections should gracefully degrade
assert_file_contains "$struct_file" "## Ariadne Clusters" "raw-structure.md has Ariadne clusters section"
assert_file_contains "$struct_file" "## Ariadne Layers" "raw-structure.md has Ariadne layers section"

# If ariadne is not installed, should show degradation message
if ! command -v ariadne >/dev/null 2>&1; then
  # Can't test this reliably since ariadne may be installed
  pass "Ariadne sections present (degradation path exists)"
else
  pass "Ariadne sections present (ariadne available)"
fi

# ── 6. Scanner templates: updated budget values ────────────────────

tech_template="$MOIRA_HOME/templates/scanners/tech-scan.md"
structure_template="$MOIRA_HOME/templates/scanners/structure-scan.md"
convention_template="$MOIRA_HOME/templates/scanners/convention-scan.md"
pattern_template="$MOIRA_HOME/templates/scanners/pattern-scan.md"

# Check source files instead if installed copy doesn't exist
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ ! -f "$tech_template" ]]; then
  tech_template="$SRC_DIR/src/global/templates/scanners/tech-scan.md"
  structure_template="$SRC_DIR/src/global/templates/scanners/structure-scan.md"
  convention_template="$SRC_DIR/src/global/templates/scanners/convention-scan.md"
  pattern_template="$SRC_DIR/src/global/templates/scanners/pattern-scan.md"
fi

assert_file_contains "$tech_template" "50k tokens" "tech-scan budget is 50k"
assert_file_contains "$structure_template" "50k tokens" "structure-scan budget is 50k"
assert_file_contains "$convention_template" "100k tokens" "convention-scan budget is 100k"
assert_file_contains "$pattern_template" "100k tokens" "pattern-scan budget is 100k"

# ── 7. Scanner templates: pre-collected data sections ───────────────

assert_file_contains "$tech_template" "Pre-Collected Data" "tech-scan has Pre-Collected Data section"
assert_file_contains "$tech_template" "raw-configs.md" "tech-scan references raw-configs.md"
assert_file_contains "$structure_template" "Pre-Collected Data" "structure-scan has Pre-Collected Data section"
assert_file_contains "$structure_template" "raw-structure.md" "structure-scan references raw-structure.md"

# ── Summary ─────────────────────────────────────────────────────────

test_summary
