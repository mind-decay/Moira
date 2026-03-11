#!/usr/bin/env bash
# test-rules-assembly.sh — Tier 1 tests for Moira rules assembly system
# Tests rule loading, conflict detection, instruction file assembly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"

# Create temp directory for functional tests
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Source rules library (which sources knowledge.sh and yaml-utils.sh)
source "$MOIRA_HOME/lib/rules.sh"

BASE_FILE="$MOIRA_HOME/core/rules/base.yaml"
MATRIX_FILE="$MOIRA_HOME/core/knowledge-access-matrix.yaml"

# ── 1. Layer loading ─────────────────────────────────────────────────

# L1 loads from base.yaml: contains inviolable rules
result=$(moira_rules_load_layer 1 "$BASE_FILE")
if echo "$result" | grep -q "INV"; then
  pass "L1 load: contains inviolable rule references"
fi
if echo "$result" | grep -q "fabricat"; then
  pass "L1 load: contains fabrication prohibition"
else
  fail "L1 load: missing fabrication prohibition"
fi
if echo "$result" | grep -q "OVERRIDABLE"; then
  pass "L1 load: contains overridable section"
else
  fail "L1 load: missing overridable section"
fi

# L2 loads from role yaml: contains identity, never constraints
ROLE_FILE="$MOIRA_HOME/core/rules/roles/hephaestus.yaml"
result=$(moira_rules_load_layer 2 "$ROLE_FILE")
if echo "$result" | grep -q "IDENTITY"; then
  pass "L2 load: contains identity section"
else
  fail "L2 load: missing identity section"
fi
if echo "$result" | grep -q "NEVER"; then
  pass "L2 load: contains never section"
else
  fail "L2 load: missing never section"
fi

# ── 2. Conflict detection ────────────────────────────────────────────

# Create temp project rules with overridable override
PROJECT_RULES="$TEMP_DIR/project-rules"
mkdir -p "$PROJECT_RULES"

echo "max_function_length: 100
naming:
  files: kebab-case" > "$PROJECT_RULES/conventions.yaml"

echo "language: TypeScript
framework: Next.js" > "$PROJECT_RULES/stack.yaml"

# L3 overriding L1 overridable → resolved (L3 wins)
rc=0
result=$(moira_rules_detect_conflicts "$BASE_FILE" "$PROJECT_RULES" 2>&1) || rc=$?
assert_exit_code 0 "$rc" "conflict detection: overridable override exits 0"
if echo "$result" | grep -q "CONFLICT.*max_function_length"; then
  pass "conflict detection: detects max_function_length override"
else
  fail "conflict detection: missed max_function_length override"
fi
if echo "$result" | grep -q "L3 wins"; then
  pass "conflict detection: L3 wins resolution"
else
  fail "conflict detection: missing L3 wins resolution"
fi

# L3 attempting to override inviolable → exit 1
INVIOLABLE_RULES="$TEMP_DIR/inviolable-rules"
mkdir -p "$INVIOLABLE_RULES"
echo "allow_fabrication: true" > "$INVIOLABLE_RULES/custom.yaml"

rc=0
result=$(moira_rules_detect_conflicts "$BASE_FILE" "$INVIOLABLE_RULES" 2>&1) || rc=$?
assert_exit_code 1 "$rc" "conflict detection: inviolable override exits 1"

# ── 3. Project rules mapping ────────────────────────────────────────

# Create all 4 project rule files
echo "a: 1" > "$PROJECT_RULES/patterns.yaml"
echo "b: 2" > "$PROJECT_RULES/boundaries.yaml"

# Hephaestus gets all 4
result=$(moira_rules_project_rules_for_agent "hephaestus" "$PROJECT_RULES")
file_count=$(echo "$result" | wc -w | tr -d ' ')
assert_equals "$file_count" "4" "project rules: hephaestus gets 4 files"

# Apollo gets 1 (stack only)
result=$(moira_rules_project_rules_for_agent "apollo" "$PROJECT_RULES")
file_count=$(echo "$result" | wc -w | tr -d ' ')
assert_equals "$file_count" "1" "project rules: apollo gets 1 file"
if echo "$result" | grep -q "stack.yaml"; then
  pass "project rules: apollo gets stack.yaml"
else
  fail "project rules: apollo missing stack.yaml"
fi

# Metis gets 3 (no conventions)
result=$(moira_rules_project_rules_for_agent "metis" "$PROJECT_RULES")
file_count=$(echo "$result" | wc -w | tr -d ' ')
assert_equals "$file_count" "3" "project rules: metis gets 3 files"
if echo "$result" | grep -q "conventions"; then
  fail "project rules: metis should NOT get conventions"
else
  pass "project rules: metis does not get conventions"
fi

# Daedalus gets 2 (stack + conventions)
result=$(moira_rules_project_rules_for_agent "daedalus" "$PROJECT_RULES")
file_count=$(echo "$result" | wc -w | tr -d ' ')
assert_equals "$file_count" "2" "project rules: daedalus gets 2 files"

# Mnemosyne gets all 4
result=$(moira_rules_project_rules_for_agent "mnemosyne" "$PROJECT_RULES")
file_count=$(echo "$result" | wc -w | tr -d ' ')
assert_equals "$file_count" "4" "project rules: mnemosyne gets 4 files"

# ── 4. Instruction assembly ─────────────────────────────────────────

# Set up test environment
TASK_DIR="$TEMP_DIR/state/tasks/test-001"
INSTR_DIR="$TASK_DIR/instructions"
mkdir -p "$INSTR_DIR"

# Create task context file
echo "Implement the FooBar component per the plan." > "$TEMP_DIR/task-context.md"

# Create test knowledge
KNOW_DIR="$TEMP_DIR/test-knowledge"
for ktype in project-model conventions decisions patterns failures quality-map; do
  mkdir -p "$KNOW_DIR/$ktype"
done
echo "Project is a web app" > "$KNOW_DIR/project-model/index.md"
echo "Project summary" > "$KNOW_DIR/project-model/summary.md"
echo "Conventions full" > "$KNOW_DIR/conventions/full.md"
echo "Patterns summary" > "$KNOW_DIR/patterns/summary.md"
echo "Failures full" > "$KNOW_DIR/failures/full.md"
echo "Quality map full" > "$KNOW_DIR/quality-map/full.md"

# Assemble for hephaestus (implementer)
output_file="$INSTR_DIR/hephaestus.md"
moira_rules_assemble_instruction \
  "$output_file" \
  "hephaestus" \
  "$BASE_FILE" \
  "$MOIRA_HOME/core/rules/roles/hephaestus.yaml" \
  "$PROJECT_RULES" \
  "$KNOW_DIR" \
  "$TEMP_DIR/task-context.md" \
  "$MATRIX_FILE"

assert_file_exists "$output_file" "assembly: instruction file created"

# Verify required sections
assert_file_contains "$output_file" "## Identity" "assembly: has Identity section"
assert_file_contains "$output_file" "## Rules" "assembly: has Rules section"
assert_file_contains "$output_file" "### Inviolable" "assembly: has Inviolable section"
assert_file_contains "$output_file" "### Role Constraints" "assembly: has Role Constraints section"
assert_file_contains "$output_file" "## Response Contract" "assembly: has Response Contract section"
assert_file_contains "$output_file" "## Task" "assembly: has Task section"
assert_file_contains "$output_file" "## Output" "assembly: has Output section"

# Verify Knowledge section (hephaestus has knowledge access)
assert_file_contains "$output_file" "## Knowledge" "assembly: has Knowledge section"

# Hephaestus has quality_checklist: null, so Quality Checklist should be absent
if grep -q "## Quality Checklist" "$output_file" 2>/dev/null; then
  fail "assembly: hephaestus should NOT have Quality Checklist (quality_checklist: null)"
else
  pass "assembly: hephaestus correctly omits Quality Checklist (null)"
fi

# Verify inviolable rules are present
assert_file_contains "$output_file" "fabricat" "assembly: contains fabrication prohibition"

# Verify task context
assert_file_contains "$output_file" "FooBar" "assembly: contains task context"

# Assemble for themis (reviewer) — has quality_checklist: q4-correctness
themis_instr="$INSTR_DIR/themis.md"
moira_rules_assemble_instruction \
  "$themis_instr" \
  "themis" \
  "$BASE_FILE" \
  "$MOIRA_HOME/core/rules/roles/themis.yaml" \
  "$PROJECT_RULES" \
  "$KNOW_DIR" \
  "$TEMP_DIR/task-context.md" \
  "$MATRIX_FILE"

assert_file_contains "$themis_instr" "## Quality Checklist" "assembly: themis has Quality Checklist section"

# ── 5. Knowledge access enforcement (Art 1.2) ───────────────────────

# Hephaestus: should have conventions (L2), NOT failures or quality-map
assert_file_contains "$output_file" "Conventions full" "enforcement: hephaestus has conventions L2"
if grep -q "Failures full" "$output_file" 2>/dev/null; then
  fail "enforcement: hephaestus should NOT have failures"
else
  pass "enforcement: hephaestus does not have failures"
fi
if grep -q "Quality map full" "$output_file" 2>/dev/null; then
  fail "enforcement: hephaestus should NOT have quality-map"
else
  pass "enforcement: hephaestus does not have quality-map"
fi

# Assemble for hermes (explorer) — minimal knowledge
hermes_file="$INSTR_DIR/hermes.md"
moira_rules_assemble_instruction \
  "$hermes_file" \
  "hermes" \
  "$BASE_FILE" \
  "$MOIRA_HOME/core/rules/roles/hermes.yaml" \
  "$PROJECT_RULES" \
  "$KNOW_DIR" \
  "$TEMP_DIR/task-context.md" \
  "$MATRIX_FILE"

if grep -q "Conventions full" "$hermes_file" 2>/dev/null; then
  fail "enforcement: hermes should NOT have conventions"
else
  pass "enforcement: hermes does not have conventions"
fi
if grep -q "Failures full" "$hermes_file" 2>/dev/null; then
  fail "enforcement: hermes should NOT have failures"
else
  pass "enforcement: hermes does not have failures"
fi

# Assemble for mnemosyne (reflector) — full knowledge
mnemosyne_file="$INSTR_DIR/mnemosyne.md"
moira_rules_assemble_instruction \
  "$mnemosyne_file" \
  "mnemosyne" \
  "$BASE_FILE" \
  "$MOIRA_HOME/core/rules/roles/mnemosyne.yaml" \
  "$PROJECT_RULES" \
  "$KNOW_DIR" \
  "$TEMP_DIR/task-context.md" \
  "$MATRIX_FILE"

assert_file_contains "$mnemosyne_file" "Failures full" "enforcement: mnemosyne has failures L2"
assert_file_contains "$mnemosyne_file" "Quality map full" "enforcement: mnemosyne has quality-map L2"

# Assemble for apollo (classifier) — only project-model L1
apollo_file="$INSTR_DIR/apollo.md"
moira_rules_assemble_instruction \
  "$apollo_file" \
  "apollo" \
  "$BASE_FILE" \
  "$MOIRA_HOME/core/rules/roles/apollo.yaml" \
  "$PROJECT_RULES" \
  "$KNOW_DIR" \
  "$TEMP_DIR/task-context.md" \
  "$MATRIX_FILE"

assert_file_contains "$apollo_file" "Project summary" "enforcement: apollo has project-model L1"
if grep -q "Conventions full" "$apollo_file" 2>/dev/null; then
  fail "enforcement: apollo should NOT have conventions"
else
  pass "enforcement: apollo does not have conventions"
fi
if grep -q "Failures full" "$apollo_file" 2>/dev/null; then
  fail "enforcement: apollo should NOT have failures"
else
  pass "enforcement: apollo does not have failures"
fi
if grep -q "Patterns summary" "$apollo_file" 2>/dev/null; then
  fail "enforcement: apollo should NOT have patterns"
else
  pass "enforcement: apollo does not have patterns"
fi

test_summary
