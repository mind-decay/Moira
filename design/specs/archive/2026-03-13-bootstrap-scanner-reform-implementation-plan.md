# Bootstrap Scanner Reform — Implementation Plan

**Spec:** `design/specs/2026-03-13-bootstrap-scanner-reform.md`
**Risk:** ORANGE — design doc updates first, then source changes
**Dependencies:** Phase 5 complete (all files exist)

---

## Chunk 1: Design Doc Updates

**Why first:** ORANGE risk requires design docs updated before source changes (D-018).

### Task 1.1: Decision Log — D-060

**File:** `design/decisions/log.md`
**Change:** Append D-060 after D-059

**Key points:**
- Title: "Remove Stack Presets, Frontmatter Scanner Output, Directory Conventions in Structure Scanner"
- Context: presets harm unknown stacks, bash markdown parsing is fragile, directory conventions lost without presets
- Decision: remove presets, scanners write YAML frontmatter, structure scanner detects `dir_*` file placement patterns
- Alternatives rejected: (1) add more presets — doesn't scale, (2) keep presets + fix parsing — two-system complexity, (3) dedicated architecture scanner — future enhancement (noted as follow-up)
- Note: architecture scanner may take over `dir_*` responsibility in future

**Commit:** `moira(design): add D-060 — remove presets, frontmatter scanner output`

### Task 1.2: Phase 5 Spec Update

**File:** `design/specs/2026-03-12-phase5-bootstrap-engine.md`
**Change:** Mark preset-related sections as superseded

**Key points:**
- D1 (scanner templates): add note that Output Format now includes frontmatter block (per reform spec)
- D2 (stack presets): mark section as "SUPERSEDED by bootstrap-scanner-reform spec" — presets removed
- D3 (config generator): add note that preset functions deleted, replaced by frontmatter parser
- Do NOT rewrite the entire spec — add supersession notes only

### Task 1.3: Architecture Docs Update

**Files:**
- `design/architecture/distribution.md`
- `design/architecture/overview.md`
- `design/architecture/rules.md`
- `design/IMPLEMENTATION-GUIDE.md`

**Changes:**
- `distribution.md` lines 242-251: remove `stack-presets/` subtree from global layer file tree. Lines 304-307: remove Step 4 "MATCH: Find closest stack preset" from init flow
- `overview.md` lines 122-125: remove `stack-presets/` subtree from global layer tree
- `rules.md` lines 114-122: add note that `conventions.yaml` `structure:` section is populated from structure scanner `dir_*` fields (not presets)
- `IMPLEMENTATION-GUIDE.md` lines 148-157: replace paragraph about "stack presets are starting points" with: scanners detect everything directly via frontmatter, no preset layer

### Task 1.4: Roadmap and Historical Specs Update

**Files:**
- `design/IMPLEMENTATION-ROADMAP.md`
- `design/specs/2026-03-12-phase6-quality-gates.md`
- `design/specs/2026-03-11-phase1-foundation-design.md`
- `design/specs/2026-03-11-phase1-implementation-plan.md`
- `design/decisions/2026-03-11-blocker-resolution-design.md`

**Changes:**
- `IMPLEMENTATION-ROADMAP.md` line 108: update Phase 5 description — change "Config generator (config.yaml from scan results + stack preset)" to "Config generator (config.yaml from scan frontmatter)"
- `phase6-quality-gates.md`:
  - Line 34: update "Phase 5: presets" reference
  - Line 426: update "matching existing preset" reference
  - Line 452: remove `moira_init_preset` from fixture format example
- `phase1-foundation-design.md`:
  - Line 51: `stack: string # preset ID (nextjs|...)` → add supersession note: `# (was enum, now free-form string — see bootstrap-scanner-reform spec)`
  - Lines 379-383: `stack-presets/` in tree → add supersession note
- `phase1-implementation-plan.md`:
  - Line 67: remove `stack-presets/` from dirs to create
  - Line 83: update enum reference
  - Lines 233, 466: add supersession notes for `stack-presets/` references
- `blocker-resolution-design.md` line 28: add supersession note for `stack-presets/` reference

**Commit:** `moira(design): update architecture docs for preset removal and frontmatter reform`

---

## Chunk 2: Schema and Scanner Templates

**Depends on:** Chunk 1 (design docs updated)

### Task 2.1: Config Schema

**File:** `src/schemas/config.schema.yaml`
**Change:** Lines 22-24

**Before:**
```yaml
  project.stack:
    type: enum
    required: true
    enum: [nextjs, react-vite, express, fastapi, go-api, vue, python, rust, java, generic]
    default: generic
```

**After:**
```yaml
  project.stack:
    type: string
    required: true
    default: generic
```

Remove `enum` line entirely. Keep `default: generic` for `moira_yaml_init` generation.

### Task 2.2: Tech Scanner Template

**File:** `src/global/templates/scanners/tech-scan.md`
**Change:** Replace Output Format section

**Key points:**
- Add frontmatter contract before markdown format
- Frontmatter fields: `language`, `language_version`, `framework`, `framework_version`, `framework_type`, `runtime`, `package_manager`, `build_tool`, `styling`, `orm`, `testing`, `ci`, `deployment`
- Keep existing markdown format as the body after `---`
- Add instruction: "Start output with frontmatter block between `---` delimiters. Fields you cannot determine — omit entirely. After second `---`, write the detailed markdown report."
- Add to Constraints: "Do NOT write `Not detected` or `unknown` in frontmatter — omit the field"

### Task 2.3: Structure Scanner Template

**File:** `src/global/templates/scanners/structure-scan.md`
**Change:** Add frontmatter contract + directory convention detection

**Key points:**
- Frontmatter fields: `layout_pattern`, `source_root`, `entry_points` (list), `test_pattern`, `test_roots` (list), `test_naming`, `do_not_modify` (list), `modify_with_caution` (list), `dir_components`, `dir_pages`, `dir_api`, `dir_services`, `dir_types`, `dir_utils`
- `dir_*` fields: add to Scan Strategy section — "After mapping directory roles, identify recurring file placement patterns. If 3+ files of the same type exist in a directory, record as `dir_{role}: {path}/`"
- `dir_*` keys are generic labels; scanner uses whichever are relevant to the project
- Additional `dir_*` keys beyond the standard set are allowed (e.g., `dir_hooks`, `dir_stores`, `dir_middleware`)
- Keep existing markdown format as body

### Task 2.4: Convention Scanner Template

**File:** `src/global/templates/scanners/convention-scan.md`
**Change:** Add frontmatter contract

**Key points:**
- Frontmatter fields: `naming_files`, `naming_functions`, `naming_components`, `naming_constants`, `naming_types`, `indent`, `quotes`, `semicolons`, `max_line_length`, `import_style`, `export_style`
- Keep existing markdown format as body

### Task 2.5: Pattern Scanner Template

**File:** `src/global/templates/scanners/pattern-scan.md`
**Change:** Add frontmatter contract

**Key points:**
- Frontmatter fields: `component_structure`, `component_state`, `component_styling`, `api_style`, `api_handler_structure`, `api_validation`, `api_response_format`, `data_fetching`, `error_handling`, `client_state`, `server_state`
- Keep existing markdown format as body

**Commit:** `moira(bootstrap): add frontmatter contracts to scanner templates and schema`

---

## Chunk 3: Bootstrap Library Refactor

**Depends on:** Chunk 2 (scanner templates and schema ready)

This is the largest chunk — the core refactor of `bootstrap.sh`.

### Task 3.1: Add Frontmatter Parser Functions

**File:** `src/global/lib/bootstrap.sh`
**Change:** Add two new functions near top of file (after sourcing dependencies)

**`_moira_parse_frontmatter <file> <field>`:**
- Read file line by line
- Skip until first `---` line
- For each subsequent line until second `---`:
  - If line matches `^<field>: (.*)` → print captured value, return 0
- If second `---` reached without match → return empty, exit 0
- Edge cases: file doesn't exist → return empty; no frontmatter → return empty

**`_moira_parse_frontmatter_list <file> <field>`:**
- Read file line by line
- Skip until first `---` line
- Find line matching `^<field>:` (value portion should be empty or whitespace only)
- Read subsequent lines matching `^  - (.*)` → print captured value (one per line)
- Stop on line that doesn't match `^  - ` or on second `---`
- Edge cases: same as scalar parser

### Task 3.2: Delete Preset and Parsing Functions

**File:** `src/global/lib/bootstrap.sh`
**Change:** Delete these functions entirely:

1. `moira_bootstrap_match_preset` (lines 20-97)
2. `_extract_preset_field` (lines 490-531)
3. `_extract_scan_value` (lines 533-567)
4. `_extract_table_value` (lines 569-586)
5. `_extract_section` (lines 725-748)

Also update file header comment (line 3): remove "Preset matching" from description.

### Task 3.3: Rewrite `moira_bootstrap_generate_config`

**File:** `src/global/lib/bootstrap.sh`
**Change:** Rewrite function (currently lines 99-215)

**New signature:** `moira_bootstrap_generate_config <project_root> <tech_scan_path>`
(drops `preset_path` parameter)

**Key points:**
- `stack` value: `_moira_parse_frontmatter "$tech_scan_path" "framework"` — use framework as stack identifier (free-form string)
- If framework not detected: fall back to `_moira_parse_frontmatter "$tech_scan_path" "language"`, then `"generic"`
- Project name extraction: unchanged (package.json / go.mod / pyproject.toml / dirname)
- All other config fields: unchanged (pipelines, budgets, quality, etc.)
- Remove comment referencing preset

### Task 3.4: Rewrite `moira_bootstrap_generate_project_rules`

**File:** `src/global/lib/bootstrap.sh`
**Change:** Rewrite function (currently lines 217-238)

**New signature:** `moira_bootstrap_generate_project_rules <project_root> <scan_results_dir>`
(drops `preset_path` parameter)

**Key points:**
- Calls 4 `_gen_*` functions with scan paths only (no preset path)
- `_gen_conventions` also receives structure-scan path for `dir_*` fields

### Task 3.5: Rewrite `_moira_bootstrap_gen_stack`

**File:** `src/global/lib/bootstrap.sh`
**Change:** Rewrite function (currently lines 240-298)

**New signature:** `_moira_bootstrap_gen_stack <tech_scan> <output>`
(drops `preset_path`)

**Key points:**
- All fields from frontmatter: `language`, `framework`, `runtime`, `styling`, `orm`, `testing`, `ci`
- Each field: `_moira_parse_frontmatter "$tech_scan" "<field>"`
- If value is empty: omit from output (don't write `unknown`)
- Output comment: remove reference to preset

### Task 3.6: Rewrite `_moira_bootstrap_gen_conventions`

**File:** `src/global/lib/bootstrap.sh`
**Change:** Rewrite function (currently lines 300-357)

**New signature:** `_moira_bootstrap_gen_conventions <convention_scan> <structure_scan> <output>`
(drops `preset_path`, adds `structure_scan`)

**Key points:**
- Naming fields from convention-scan frontmatter: `naming_files`, `naming_functions`, `naming_components`, `naming_constants`, `naming_types`
- Formatting fields from convention-scan frontmatter: `indent`, `quotes`, `semicolons`, `max_line_length`
- Structure fields from structure-scan frontmatter: all `dir_*` fields
- For `dir_*` extraction: parse frontmatter, grep for lines starting with `dir_`, extract key suffix and value
- If any `dir_*` fields exist: write `structure:` section mapping `dir_components → components`, `dir_pages → pages`, etc.
- If no `dir_*` fields: omit `structure:` section entirely
- Output comment: remove reference to preset

### Task 3.7: Rewrite `_moira_bootstrap_gen_patterns`

**File:** `src/global/lib/bootstrap.sh`
**Change:** Rewrite function (currently lines 359-391)

**New signature:** `_moira_bootstrap_gen_patterns <pattern_scan> <output>`
(drops `preset_path`)

**Key points:**
- All fields from frontmatter: `data_fetching`, `error_handling`, `api_style`, `api_validation`, `component_structure`, `component_state`, `component_styling`, `client_state`, `server_state`
- If value is empty: omit from output (don't write `unknown`)
- Output comment: remove reference to preset

### Task 3.8: Rewrite `_moira_bootstrap_gen_boundaries`

**File:** `src/global/lib/bootstrap.sh`
**Change:** Rewrite function (currently lines 393-488)

**New signature:** `_moira_bootstrap_gen_boundaries <structure_scan> <output>`
(drops `preset_path`)

**Key points:**
- `do_not_modify` list: `_moira_parse_frontmatter_list "$structure_scan" "do_not_modify"`
- `modify_with_caution` list: `_moira_parse_frontmatter_list "$structure_scan" "modify_with_caution"`
- Write YAML list directly from function output
- If list is empty: write `# none detected` comment
- Output comment: remove reference to preset

**Commit:** `moira(bootstrap): refactor bootstrap.sh — frontmatter parser, remove presets`

---

## Chunk 4: BUG-1 Fix (zsh BASH_SOURCE)

**Depends on:** None (independent of Chunks 1-3, but logically part of bootstrap work)

### Task 4.1: Fix BASH_SOURCE in lib files

**Files:**
- `src/global/lib/bootstrap.sh` line 14
- `src/global/lib/yaml-utils.sh` line 20
- `src/global/lib/knowledge.sh` line 11

**Change in each:** Replace `${BASH_SOURCE[0]}` with `${BASH_SOURCE[0]:-${(%):-%x}}`

**Verify:** `scaffold.sh` does NOT use `BASH_SOURCE` — no change needed.

**Commit:** `moira(bootstrap): fix BUG-1 — add zsh BASH_SOURCE fallback`

---

## Chunk 5: Scaffold, Install, Init Command

**Depends on:** Chunk 3 (bootstrap.sh refactored — function signatures changed)

### Task 5.1: Remove stack-presets from scaffold

**File:** `src/global/lib/scaffold.sh`
**Change:** Line 27 — remove `mkdir -p "$target_dir"/templates/stack-presets`

### Task 5.2: Remove stack-presets from install

**File:** `src/install.sh`
**Changes:**
- Lines 83-85: remove the `if ls ... stack-presets ... cp` block
- Lines 307-313 (in `verify()` function): remove the check for `generic.yaml` stack preset

### Task 5.3: Update init.md

**File:** `src/commands/moira/init.md`
**Changes:**
- Delete Step 5 (Match Stack Preset) entirely — lines 99-108
- Renumber remaining steps: old 6→5, 7→6, 8→7, 9→8, 10→9, 11→10
- Step 5 (was 6): update bash code blocks — remove `$PRESET` variable, remove preset path from function calls:
  ```bash
  source ~/.claude/moira/lib/bootstrap.sh
  moira_bootstrap_generate_config "{project_root}" ".claude/moira/state/init/tech-scan.md"
  moira_bootstrap_generate_project_rules "{project_root}" ".claude/moira/state/init"
  ```
- Step 4 (scanner dispatch): update failure options — remove "skip (use preset defaults only)" option, replace with "skip (fields will be empty)"

### Task 5.4: Delete preset files

**Delete entire directory:** `src/global/templates/stack-presets/`

Files: `nextjs.yaml`, `react-vite.yaml`, `express.yaml`, `fastapi.yaml`, `go-api.yaml`, `generic.yaml`, `.gitkeep`

**Commit:** `moira(bootstrap): remove preset system from scaffold, install, init`

---

## Chunk 6: Tests

**Depends on:** Chunks 3, 5 (bootstrap.sh refactored, presets deleted)

### Task 6.1: Update test-bootstrap.sh

**File:** `src/tests/tier1/test-bootstrap.sh`

**Delete:**
- Lines 34-68: all preset tests (existence, section checks, stack_id checks, uniqueness)
- Line 83: remove `moira_bootstrap_match_preset` from function existence check list
- Lines 232-262: preset matching functional tests (nextjs match, unknown stack fallback)

**Add (after scanner template tests, before bootstrap library tests):**

```bash
# ═══════════════════════════════════════════════════════════════════════
# Frontmatter parser tests
# ═══════════════════════════════════════════════════════════════════════

# Create test frontmatter file
FM_TEST="$TEST_DIR/fm-test.md"
cat > "$FM_TEST" << 'EOF'
---
language: TypeScript
framework: SvelteKit
runtime: Node.js
max_line_length: 100
entry_points:
  - src/app.html
  - src/hooks.server.ts
do_not_modify:
  - node_modules/
  - .svelte-kit/
---

## Body Content
framework: This should not be parsed
EOF

# Source bootstrap for testing
source "$MOIRA_HOME/lib/bootstrap.sh"

# Scalar: existing field
result=$(_moira_parse_frontmatter "$FM_TEST" "language")
if [[ "$result" == "TypeScript" ]]; then
  pass "frontmatter: scalar field extraction"
else
  fail "frontmatter: expected 'TypeScript', got '$result'"
fi

# Scalar: numeric value
result=$(_moira_parse_frontmatter "$FM_TEST" "max_line_length")
if [[ "$result" == "100" ]]; then
  pass "frontmatter: numeric value as string"
else
  fail "frontmatter: expected '100', got '$result'"
fi

# Scalar: missing field
result=$(_moira_parse_frontmatter "$FM_TEST" "nonexistent")
if [[ -z "$result" ]]; then
  pass "frontmatter: missing field returns empty"
else
  fail "frontmatter: expected empty, got '$result'"
fi

# Scalar: ignores body content
result=$(_moira_parse_frontmatter "$FM_TEST" "framework")
if [[ "$result" == "SvelteKit" ]]; then
  pass "frontmatter: returns frontmatter value, ignores body"
else
  fail "frontmatter: expected 'SvelteKit', got '$result'"
fi

# List: extraction
result=$(_moira_parse_frontmatter_list "$FM_TEST" "entry_points")
expected="src/app.html
src/hooks.server.ts"
if [[ "$result" == "$expected" ]]; then
  pass "frontmatter: list extraction"
else
  fail "frontmatter: list mismatch, got '$result'"
fi

# List: missing field
result=$(_moira_parse_frontmatter_list "$FM_TEST" "nonexistent")
if [[ -z "$result" ]]; then
  pass "frontmatter: missing list returns empty"
else
  fail "frontmatter: expected empty list, got '$result'"
fi
```

**Update function existence checks:**

```bash
# Updated function list
for func in moira_bootstrap_generate_config moira_bootstrap_generate_project_rules \
            moira_bootstrap_populate_knowledge moira_bootstrap_inject_claude_md \
            moira_bootstrap_setup_gitignore _moira_parse_frontmatter \
            _moira_parse_frontmatter_list; do
  # ... existing check pattern
done

# Verify deleted functions are gone
for func in moira_bootstrap_match_preset _extract_scan_value \
            _extract_table_value _extract_preset_field; do
  if grep -q "^${func}()" "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
    fail "bootstrap.sh: deleted function $func still exists"
  else
    pass "bootstrap.sh: function $func correctly removed"
  fi
done
```

### Task 6.2: Update test-file-structure.sh

**File:** `src/tests/tier1/test-file-structure.sh`

**Delete:**
- Line 42: `assert_dir_exists "$MOIRA_HOME/templates/stack-presets" "templates/stack-presets/ exists"`
- Line 96: `assert_file_exists "$MOIRA_HOME/templates/stack-presets/generic.yaml" "stack-presets/generic.yaml exists"`

### Task 6.3: Update test-install.sh

**File:** `src/tests/tier1/test-install.sh`

**Delete:**
- Lines 71-72: `assert_file_exists "$MOIRA_HOME/templates/stack-presets/generic.yaml" "clean install: generic.yaml preset exists"`

### Task 6.4: Update bench fixture manifests

**Files:**
- `src/tests/bench/fixtures/greenfield-webapp/.moira-fixture.yaml`
- `src/tests/bench/fixtures/mature-webapp/.moira-fixture.yaml`
- `src/tests/bench/fixtures/legacy-webapp/.moira-fixture.yaml`

**Change:** Remove `moira_init_preset: express` line from each file.

### Task 6.5: Run Tier 1 tests

Run `src/tests/tier1/test-bootstrap.sh` and verify all tests pass.
Run `src/tests/tier1/test-file-structure.sh` and verify all tests pass.
Run `src/tests/tier1/test-install.sh` and verify all tests pass.
Run full Tier 1 suite to check for regressions.

**Commit:** `moira(bootstrap): update tests for frontmatter parser and preset removal`

---

## Dependency Graph

```
Chunk 1 (Design docs)
  │
  ▼
Chunk 2 (Schema + scanner templates)
  │
  ▼
Chunk 3 (Bootstrap library refactor)    Chunk 4 (BUG-1 zsh fix) [independent]
  │
  ▼
Chunk 5 (Scaffold, install, init)
  │
  ▼
Chunk 6 (Tests + verification)
```

Chunk 4 is independent and can be committed at any point. All other chunks are sequential.

## Verification Checklist

After all chunks complete:

- [ ] `bash -n src/global/lib/bootstrap.sh` — no syntax errors
- [ ] `bash -n src/global/lib/scaffold.sh` — no syntax errors
- [ ] `bash -n src/install.sh` — no syntax errors
- [ ] `src/tests/tier1/test-bootstrap.sh` — all tests pass
- [ ] Full Tier 1 suite — no regressions
- [ ] `grep -r 'stack-presets' src/` — zero results (no stale references in source)
- [ ] `grep -r 'stack.presets\|stack-presets\|moira_init_preset' src/tests/` — zero results (no stale test references)
- [ ] `grep -r '_extract_scan_value\|_extract_table_value\|_extract_preset_field\|match_preset' src/global/lib/bootstrap.sh` — zero results (all deleted)
- [ ] `grep -r 'preset_path\|preset_file\|preset_name' src/global/lib/bootstrap.sh` — zero results
- [ ] `src/global/templates/scanners/tech-scan.md` contains `---` frontmatter markers
- [ ] `src/global/templates/scanners/structure-scan.md` contains `dir_` fields
- [ ] `src/global/templates/scanners/convention-scan.md` contains `---` frontmatter markers
- [ ] `src/global/templates/scanners/pattern-scan.md` contains `---` frontmatter markers
- [ ] `src/schemas/config.schema.yaml` — `project.stack` is `type: string`, no `enum` line
- [ ] `src/commands/moira/init.md` — no "Step 5: Match Stack Preset", no preset path references
- [ ] `src/global/lib/scaffold.sh` — no `stack-presets` in mkdir
- [ ] `design/decisions/log.md` — contains D-060
