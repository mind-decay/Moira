# Phase 9: MCP Integration — Implementation Plan

**Spec:** `design/specs/2026-03-14-phase9-mcp-integration.md`
**Date:** 2026-03-14

## Overview

10 deliverables + ripple effect updates, organized into 6 chunks with explicit dependencies. 17 tasks, 7 commits.

---

## Chunk 1: Decision Log + Design Doc Updates (prerequisite)

No code changes. Updates design docs per Art 6.2 — design docs must be authoritative before implementation.

### Task 1.1: Add D-078 through D-084 to decision log
- **File:** `design/decisions/log.md`
- **Source:** Spec section "Architectural Decisions" (AD-1 through AD-7)
- **What:** Add 7 new decision entries in standard format (Context, Decision, Alternatives rejected, Reasoning)
  - D-078: MCP Authorization via Prompting (Not Enforcement)
  - D-079: MCP Scanner as Hermes (Explorer) Dispatch
  - D-080: Registry in Config (Committed), Not State (Gitignored)
  - D-081: MCP Caching Structure Now, Logic Later
  - D-082: Registry `tools` as Map (Not List-of-Maps)
  - D-083: `token_estimate` Numeric Field in Registry
  - D-084: Registry Merge Strategy on Refresh
- **Commit:** `moira(design): add D-078 through D-084 MCP integration decisions`

### Task 1.2: Update design docs
- **Files:**
  - `design/architecture/overview.md` — add `mcp.sh` to lib/ list, add `mcp-registry.schema.yaml` to schemas/ list
  - `design/subsystems/mcp.md` — update registry tools format from list-of-maps to map per D-082
- **Source:** Spec section "Design Doc Corrections"
- **Commit:** `moira(design): update overview.md and mcp.md for phase 9`

**Dependency:** None. Must complete before all other chunks.

---

## Chunk 2: Schema + Library + Templates (foundation)

Creates the new files that other chunks depend on. No modifications to existing files.

### Task 2.1: Create MCP registry schema
- **File:** `src/schemas/mcp-registry.schema.yaml` (NEW)
- **Source:** Spec D1
- **What:** YAML schema with `servers` top-level map. Each server has: `type` (enum: documentation/design/code/search/communication/other), `tools` map. Each tool has: `purpose` (string, required), `cost` (enum: low/medium/medium-high/high, required), `reliability` (enum: low/medium/high, required), `when_to_use` (string, required), `when_NOT_to_use` (string, required), `budget_impact` (string, optional), `token_estimate` (number, optional)
- **Key point:** Follow existing schema format (see `config.schema.yaml` for reference)

### Task 2.2: Create MCP shell library
- **File:** `src/global/lib/mcp.sh` (NEW)
- **Source:** Spec D3
- **What:** 6 functions:
  - `moira_mcp_registry_exists <project_root>` — check `config/mcp-registry.yaml` exists and non-empty
  - `moira_mcp_is_enabled <project_root>` — read `config.yaml` → `mcp.enabled` via `moira_yaml_get`
  - `moira_mcp_list_servers <project_root>` — parse registry top-level keys under `servers:`
  - `moira_mcp_get_tool_info <project_root> <server> <tool>` — extract tool metadata
  - `moira_mcp_get_token_estimate <project_root> <server> <tool>` — fallback chain: registry → budgets.yaml → default 5000
  - `moira_mcp_generate_registry <project_root> <scan_results_dir>` — parse scanner frontmatter, write `config/mcp-registry.yaml`, set `mcp.enabled: true` in config
- **Key points:**
  - Source `yaml-utils.sh` for YAML parsing (same pattern as other libs)
  - `moira_mcp_get_token_estimate` fallback: registry field → `budgets.yaml` `mcp_estimates.{server}_{tool}` (via awk) → `mcp_estimates.default_call` → hardcoded 5000
  - `moira_mcp_generate_registry` reads scan output frontmatter (between `---` markers), extracts `mcp_servers:` section, writes to `config/mcp-registry.yaml`
  - Follow naming convention: all functions prefixed `moira_mcp_`

### Task 2.3: Create MCP scanner template
- **File:** `src/global/templates/scanners/mcp-scan.md` (NEW)
- **Source:** Spec D2
- **What:** Layer 4 instruction template for Explorer agent. Instructions to:
  1. Discover available MCP servers (by checking what MCP tools are available in the environment)
  2. For each server: identify type, list tools with purpose/cost/reliability/usage guidelines
  3. Estimate token budget per tool call
  4. Output structured frontmatter (between `---` markers) with `mcp_servers:` section
- **Key points:**
  - Follow existing scanner template format (see `tech-scan.md` for reference)
  - Output path: `.claude/moira/state/init/mcp-scan.md`
  - Scanner should instruct the agent to check what MCP tools are available, NOT to try calling them

### Task 2.4: Create knowledge caching templates
- **Files:**
  - `src/global/templates/knowledge/libraries/index.md` (NEW)
  - `src/global/templates/knowledge/libraries/summary.md` (NEW)
- **Source:** Spec D8a
- **What:**
  - `index.md` — L0 template: table with Library/Last Updated/Source columns
  - `summary.md` — L1 template: placeholder for key API facts per library
- **Key point:** Follow existing knowledge template format (see `templates/knowledge/project-model/` for reference)

**Commit:** `moira(mcp): add MCP registry schema, library, scanner template, knowledge templates`

**Dependency:** Chunk 1 must be complete (design docs updated).

---

## Chunk 3: Bootstrap Integration (wiring)

Connects the new files into the bootstrap flow.

### Task 3.1: Update scaffold.sh — add `knowledge/libraries/` directory
- **File:** `src/global/lib/scaffold.sh`
- **Source:** Spec D4c
- **What:** Add `mkdir -p "$base"/knowledge/libraries` after the existing knowledge directory creation block (after line 68, `mkdir -p "$base"/knowledge/quality-map`)

### Task 3.2: Update bootstrap.sh — add MCP scan function
- **File:** `src/global/lib/bootstrap.sh`
- **Source:** Spec D4a
- **What:** Add function `moira_bootstrap_scan_mcp <project_root> <scan_results_dir>`:
  1. Source `mcp.sh` from lib directory
  2. Check if MCP scan results exist at `$scan_results_dir/mcp-scan.md`
  3. If exists: call `moira_mcp_generate_registry "$project_root" "$scan_results_dir"`, log result
  4. If not exists: set `mcp.enabled: false` in config via `moira_yaml_set`, log "No MCP servers detected"
- **Key point:** This function processes scan results only. Scanner dispatch is handled by init.md (same as other scanners).

### Task 3.3: Update init.md — add MCP discovery step
- **File:** `src/commands/moira/init.md`
- **Source:** Spec D4b, D2
- **What:**
  1. Step 4 (scanners) — NO CHANGE to existing parallel dispatch. Keep 4 scanners in parallel.
  2. After Step 5 (Generate Config), add **Step 6: MCP Discovery**:
     - Dispatch MCP scanner agent SEQUENTIALLY (not in parallel with Step 4 scanners — spec D2 says "AFTER tech scan" because MCP classification needs project stack context)
     - Read `~/.claude/moira/templates/scanners/mcp-scan.md` and dispatch single Explorer agent
     - After scanner returns, call `moira_bootstrap_scan_mcp` to generate registry
     - If no MCP servers available in environment: skip scan, set `mcp.enabled: false`
  3. Renumber: old Step 6 (Knowledge) → Step 7, old Step 7 (CLAUDE.md) → Step 8, old Step 8 (Gitignore) → Step 9, old Step 9 (Hooks) → Step 10, old Step 10 (Review Gate) → Step 11, old Step 11 (Onboarding) → Step 12
  4. Update Step 11 (Review Gate) display to include MCP status line
  5. Update `--force` mode section: "Steps 7-9" → "Steps 8-10" (CLAUDE.md, gitignore, hooks), and add Step 6 MCP re-scan
  6. Update all references to "4 Explorer agents" / "4 Agent tool calls" / "ALL 4 agents" in Step 4 text (multiple occurrences)
- **Key points:**
  - MCP scanner is SEQUENTIAL, dispatched after Step 5 config generation (spec D2: "AFTER tech scan")
  - Step 4 remains unchanged (4 parallel scanners)
  - Keep step numbering consistent across the document

**Commit:** `moira(pipeline): integrate MCP discovery into bootstrap flow`

**Dependency:** Chunk 2 (schema, library, scanner template must exist).

---

## Chunk 4: Agent Rules + Dispatch Updates (allocation mechanism)

Updates agent rules and dispatch to support MCP allocation in pipelines.

### Task 4.1: Update daedalus.yaml — MCP registry reading capability
- **File:** `src/global/core/rules/roles/daedalus.yaml`
- **Source:** Spec D5c
- **What:**
  - Add to identity: "When MCP is enabled, you read the MCP registry (`config/mcp-registry.yaml`) to determine available tools and their token costs. You include MCP authorization sections in each agent's instruction file."
  - Add to capabilities: "Read MCP registry to determine available tools and their costs for allocation"

### Task 4.2: Update hephaestus.yaml — MCP verification checklist
- **File:** `src/global/core/rules/roles/hephaestus.yaml`
- **Source:** Spec D6a
- **What:** Add to identity section, after existing MCP mention:
  ```
  Before using any MCP tool:
  1. Verify it is listed in your "MCP Usage Rules" section as authorized
  2. Use the specific query pattern authorized in the plan
  3. If MCP response exceeds expected token budget: note in your status summary
  4. If MCP call fails: continue without it, note the failure, do NOT fabricate the information
  ```

### Task 4.3: Update themis.yaml — MCP verification steps
- **File:** `src/global/core/rules/roles/themis.yaml`
- **Source:** Spec D6b
- **What:** Add to capabilities, expanding the existing "Verify MCP calls were used correctly" item:
  ```
  MCP Usage Review (when MCP tools were used):
  - All MCP calls were authorized in the plan
  - No unauthorized MCP calls were made
  - MCP responses were actually used (not fetched and ignored)
  - No MCP calls for information available locally
  - Results from MCP were applied correctly (not misinterpreted)
  - MCP token usage was within estimated budget
  ```

### Task 4.4: Update dispatch.md — MCP section in prompt template
- **File:** `src/global/skills/dispatch.md`
- **Source:** Spec D5a, D5b
- **What:** Add new section "## MCP Tool Allocation" after the "Quality Mode Communication" section:
  1. **For Daedalus (simplified assembly):** When MCP is enabled, read `config/mcp-registry.yaml` and include "Available MCP Tools" section listing all servers/tools with metadata. Include instructions for AUTHORIZE/PROHIBIT per step. When MCP disabled: include note "MCP tools are not configured."
  2. **For post-planning agents:** Document that Daedalus MUST include "MCP Usage Rules for This Step" section in instruction files with authorized/prohibited tools and the 3-point verification checklist.
  3. **Condition check:** Add note that orchestrator should check `moira_mcp_is_enabled` (by reading `config.yaml` → `mcp.enabled`) before injecting MCP context. If false, skip MCP section entirely.

### Task 4.5: Update q4-correctness.yaml — MCP checklist section
- **File:** `src/global/core/rules/quality/q4-correctness.yaml`
- **Source:** Spec D7
- **What:** Add new `mcp_usage:` section after `project_conventions:` with 5 items:
  - Q4-M01: "All MCP tool calls were authorized in the plan" (required: false)
  - Q4-M02: "No unauthorized MCP calls were made" (required: false)
  - Q4-M03: "No MCP calls for information available in project files" (required: false)
  - Q4-M04: "MCP responses were actually used (not fetched and ignored)" (required: false)
  - Q4-M05: "MCP results were applied correctly (not misinterpreted)" (required: false)
- **Key point:** `required: false` because items only apply when MCP was used. Reviewer marks as `na` when no MCP usage. ID format: uppercase `Q4-M0x` matching existing convention.

**Commit:** `moira(agents): add MCP allocation rules and dispatch integration`

**Dependency:** Chunk 2 (mcp.sh must exist for dispatch to reference).

---

## Chunk 5: Refresh Command + Ripple Effect Updates (integration)

### Task 5.1: Update refresh.md — MCP re-scan
- **File:** `src/commands/moira/refresh.md`
- **Source:** Spec D9
- **What:** Update the stub to include MCP re-scan capability. The refresh command should:
  1. Re-dispatch MCP scanner (single Explorer agent, sequential)
  2. Merge new MCP results with existing registry per D-084 (add new servers, flag removed, preserve user customizations)
  3. Display MCP registry update summary
- **Key points:**
  - Scope limited to MCP re-scan per spec D9. Full project re-scan (all scanners) is NOT Phase 9 scope.
  - The stub currently says "will be implemented in Phase 5" — replace the stub text but keep the command structure (frontmatter, allowed-tools)
  - Merge strategy: compare new scan against existing registry. New servers → add. Existing servers with unchanged tools → preserve user edits. Removed servers → mark as `removed: true` (don't delete)

### Task 5.2: Update install.sh — add mcp.sh to verify list
- **File:** `src/install.sh`
- **Source:** Spec "Ripple Effect Updates" item 1
- **What:**
  - Line 169: Add `mcp.sh` to the lib verify loop: `for lib_file in state.sh yaml-utils.sh scaffold.sh task-id.sh knowledge.sh rules.sh bootstrap.sh quality.sh bench.sh budget.sh settings-merge.sh mcp.sh; do`
  - Line 288: Change knowledge template threshold from `>=17` to `>=19` (adding 2 library templates)
  - Line 298: Change scanner template threshold from `>=4` to `>=5` (adding mcp-scan.md)

### Task 5.3: Update test-file-structure.sh — add mcp.sh checks
- **File:** `src/tests/tier1/test-file-structure.sh`
- **Source:** Spec "Ripple Effect Updates" item 3
- **What:** Add `mcp.sh` to the lib file existence and syntax check. Also update:
  - Scanner count threshold from `>=4` to `>=5` (line 89)

### Task 5.4: Update test-knowledge-system.sh — template count
- **File:** `src/tests/tier1/test-knowledge-system.sh`
- **Source:** Impact analysis
- **What:** Line 29: Change `assert_equals "$template_count" "17" "17 knowledge template files exist"` — update both the expected value from `"17"` to `"19"` AND the assertion message text to match. Note: this is an exact equality check, not a threshold.

### Task 5.5: Update test-install.sh — template and scanner counts
- **File:** `src/tests/tier1/test-install.sh`
- **Source:** Impact analysis
- **What:**
  - Line 49-52: Change knowledge template threshold from `>=17` to `>=19`
  - Line 65-68: Change scanner template threshold from `>=4` to `>=5`

### Task 5.6: Update test-bootstrap.sh — step count, scanner list, function check
- **File:** `src/tests/tier1/test-bootstrap.sh`
- **Source:** Impact analysis (cross-reference ripple effects)
- **What:**
  - Step count loop (line 106): Change from `1..11` to `1..12` (init.md now has 12 steps)
  - Scanner template loop (line 17): Add `mcp-scan` to the scanner list alongside `tech-scan structure-scan convention-scan pattern-scan`
  - Function existence check (lines 47-56): Add `moira_bootstrap_scan_mcp` to the list of bootstrap functions verified

**Commit:** `moira(mcp): update refresh command and ripple effect files`

**Dependency:** Chunks 2 and 3 (files must exist for verify to pass).

---

## Chunk 6: Tier 1 Tests (verification)

### Task 6.1: Create MCP system test
- **File:** `src/tests/tier1/test-mcp-system.sh` (NEW)
- **Source:** Spec D10
- **What:** New test file following existing test pattern (see `test-hooks-system.sh` for reference). Test groups:

  **Schema tests:**
  - `mcp-registry.schema.yaml` exists in `$MOIRA_HOME/schemas/`
  - Schema contains `servers` top-level key

  **Library tests:**
  - `mcp.sh` exists in `$MOIRA_HOME/lib/`
  - `mcp.sh` has valid bash syntax (`bash -n`)
  - Functions exist (grep for function name): `moira_mcp_registry_exists`, `moira_mcp_is_enabled`, `moira_mcp_list_servers`, `moira_mcp_get_tool_info`, `moira_mcp_get_token_estimate`, `moira_mcp_generate_registry`

  **Scanner tests:**
  - `mcp-scan.md` exists in `$MOIRA_HOME/templates/scanners/`
  - Scanner contains `mcp_servers:` (frontmatter output key)

  **Integration tests:**
  - `config.schema.yaml` contains `mcp.enabled`
  - `config.schema.yaml` contains `mcp.registry_path`
  - `budgets.yaml.tmpl` contains `mcp_estimates`
  - `daedalus.yaml` contains `MCP` (allocation reference)
  - `hephaestus.yaml` contains `MCP` (authorization reference)
  - `themis.yaml` contains `MCP` (verification reference)
  - `q4-correctness.yaml` contains `Q4-M0` (MCP checklist items)
  - `dispatch.md` contains `MCP` (dispatch integration)

  **Knowledge template tests:**
  - `templates/knowledge/libraries/index.md` exists
  - `templates/knowledge/libraries/summary.md` exists

- **Key points:**
  - Source `test-helpers.sh` for `pass`/`fail`/`assert_*` functions
  - Auto-discovered by `run-all.sh` (glob pattern `test-*.sh`)
  - Must be executable: `chmod +x`

**Commit:** `moira(mcp): add tier 1 MCP system tests`

**Dependency:** All previous chunks (tests verify everything exists).

---

## Final Verification

After all chunks complete:
1. Run `src/tests/tier1/run-all.sh` — all tests must pass
2. Verify no constitutional violations introduced
3. Verify spec success criteria 1-12

**Final commit (if verification passes):** `moira(mcp): phase 9 MCP integration complete`

---

## Dependency Graph

```
Chunk 1 (decisions + design docs)
  │
  ▼
Chunk 2 (schema + lib + templates)
  │
  ├──────────────┐
  ▼              ▼
Chunk 3        Chunk 4
(bootstrap)    (agent rules + dispatch)
  │              │
  ├──────────────┘
  ▼
Chunk 5 (refresh + ripple effects)
  │
  ▼
Chunk 6 (tests)
```

Chunks 3 and 4 are INDEPENDENT and can be implemented in parallel.

---

## Task Summary

| Chunk | Tasks | Files Created | Files Modified | Risk |
|-------|-------|---------------|----------------|------|
| 1 | 1.1-1.2 | 0 | 2 design docs | GREEN |
| 2 | 2.1-2.4 | 5 new files | 0 | YELLOW |
| 3 | 3.1-3.3 | 0 | 3 (scaffold, bootstrap, init.md) | YELLOW |
| 4 | 4.1-4.5 | 0 | 5 (3 agent rules, dispatch.md, q4-correctness) | YELLOW |
| 5 | 5.1-5.6 | 0 | 6 (refresh.md, install.sh, 4 test files) | YELLOW |
| 6 | 6.1 | 1 new file | 0 | GREEN |
| **Total** | **17 tasks** | **6 new files** | **16 modified** | |
