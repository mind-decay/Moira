# Phase 9: MCP Integration

## Goal

Implement managed MCP tool allocation — MCP tools are treated as managed resources allocated by the orchestration system to specific agents for specific purposes. After Phase 9: MCP servers are discovered and cataloged at `/moira init`, Planner explicitly authorizes MCP usage per step with justification and budget impact, agents receive MCP usage rules in their instructions, Reviewer verifies MCP calls were appropriate, and Reflector tracks repeated calls for cache recommendations.

**Why now:** The pipeline is fully operational (Phases 1-8). Agents already reference MCP in their rules (Daedalus allocates MCP per step, Hephaestus uses authorized MCP tools, Themis verifies MCP usage). Budget system tracks MCP estimates (D-059). Config schema has `mcp.enabled` and `mcp.registry_path`. What's missing is the actual registry generation, the allocation/instruction mechanism, the review checklist items, and the knowledge caching system.

## Risk Classification

**YELLOW (overall)** — New shell library, new scanner template, updates to existing agent rules and dispatch logic. No pipeline gate changes. No agent role boundary changes. Needs regression check + impact analysis.

**Per-deliverable:**

| Deliverable | Risk | Rationale |
|-------------|------|-----------|
| D1: MCP Registry Schema | GREEN | New schema file, additive |
| D2: MCP Discovery Scanner | YELLOW | New scanner template, dispatched during init |
| D3: MCP Library (mcp.sh) | YELLOW | New shell library with registry parsing |
| D4: Bootstrap Integration | YELLOW | Modifies bootstrap flow, new init step |
| D5: Planner MCP Allocation | YELLOW | Updates dispatch.md and instruction assembly |
| D6: Agent MCP Instructions | YELLOW | Updates agent prompt construction |
| D7: Reviewer MCP Checklist | GREEN | Adds items to existing q4-correctness.yaml |
| D8: Knowledge Caching Structure | GREEN | New knowledge template, additive |
| D9: Refresh Command Update | GREEN | Adds MCP re-scan to existing command |
| D10: Tier 1 Tests | GREEN | New test file, additive |

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/subsystems/mcp.md` | Complete MCP integration design: registry format, allocation in plans, agent instructions, usage review, budget tracking, knowledge caching, server discovery |
| `design/CONSTITUTION.md` | Art 1.1 (orchestrator purity — MCP tools used by agents, not orchestrator), Art 1.2 (agent single responsibility — Planner allocates, Implementer uses, Reviewer checks), Art 2.3 (no implicit decisions — MCP usage must be explicitly authorized), Art 3.2 (budget visibility — MCP budget impact reported), Art 4.1 (no fabrication — agents must not fabricate MCP results) |
| `design/architecture/agents.md` | Daedalus allocates MCP per step, Hephaestus uses authorized MCP only, Themis verifies MCP usage |
| `design/subsystems/context-budget.md` | MCP Budget Impact section — MCP calls affect budget, Planner includes MCP estimates |
| `design/architecture/overview.md` | File structure showing `config/mcp-registry.yaml` in project layer, `knowledge/libraries/` for cached MCP docs |
| `design/decisions/log.md` | D-059 (config-driven MCP token estimates) |

## Prerequisites (from Phase 1-8)

- **Phase 1:** State management, scaffold, directory structure with `config/` directory
- **Phase 2:** Agent role definitions (Daedalus already mentions MCP allocation, Hephaestus mentions authorized MCP, Themis mentions MCP verification)
- **Phase 3:** Orchestrator skill, pipeline engine, dispatch module
- **Phase 4:** Rules assembly, knowledge system (knowledge level access, templates)
- **Phase 5:** Bootstrap engine, scanner dispatch, config generation
- **Phase 7:** Budget library with `mcp_tokens` parameter in estimation, `mcp_estimates` in budgets.yaml

## Existing Infrastructure Audit

### Already Implemented (no changes needed)

1. **Config schema MCP fields**: `mcp.enabled` (default: false), `mcp.registry_path` (default: `config/mcp-registry.yaml`) — already in `config.schema.yaml`
2. **Default config generation**: `bootstrap.sh` generates `mcp: enabled: false, registry_path: config/mcp-registry.yaml` in config
3. **Budget MCP estimates**: `budgets.yaml.tmpl` has `mcp_estimates: context7_query: 14000, default_call: 5000`
4. **Budget estimation function**: `moira_budget_estimate_agent` accepts optional `mcp_tokens` parameter
5. **Daedalus role rules**: Already mentions MCP allocation per step with justification, MCP budget in output format
6. **Hephaestus role rules**: Already mentions "Use authorized MCP tools only"
7. **Themis role rules**: Already mentions "Verify MCP calls were used correctly"
8. **Knowledge directory structure**: `knowledge/` directory with level-based access (L0/L1/L2)
9. **Scaffold**: Creates `config/` directory in project layer

### Not Yet Implemented (Phase 9 scope)

1. **MCP registry schema**: No `mcp-registry.schema.yaml` exists
2. **MCP discovery scanner**: No scanner template for discovering MCP servers
3. **MCP shell library**: No `mcp.sh` for registry reading/parsing
4. **Registry generation at init**: Bootstrap doesn't scan MCP servers or generate registry
5. **MCP allocation in dispatch**: Dispatch.md doesn't include MCP rules in agent prompts
6. **MCP review checklist items**: q4-correctness.yaml doesn't have MCP-specific items
7. **Knowledge caching templates**: No `knowledge/libraries/` template structure
8. **Refresh MCP re-scan**: `/moira:refresh` doesn't update MCP registry

## Deliverables

### D1: MCP Registry Schema (`src/schemas/mcp-registry.schema.yaml`)

Schema definition for the MCP registry file that lives at `.moira/config/mcp-registry.yaml`.

**Schema fields:**

```yaml
servers:
  type: map
  description: "Map of MCP server names to their configuration"
  value_schema:
    type:
      type: enum
      enum: [documentation, design, code, search, communication, other]
      required: true
    tools:
      type: map
      description: "Map of tool names to their metadata"
      value_schema:
        purpose:
          type: string
          required: true
        cost:
          type: enum
          enum: [low, medium, medium-high, high]
          required: true
        reliability:
          type: enum
          enum: [low, medium, high]
          required: true
        when_to_use:
          type: string
          required: true
        when_NOT_to_use:
          type: string
          required: true
        budget_impact:
          type: string
          required: false
          description: "Approximate token impact per call"
        token_estimate:
          type: number
          required: false
          description: "Estimated tokens per call for budget calculations"
```

### D2: MCP Discovery Scanner (`src/global/templates/scanners/mcp-scan.md`)

Scanner template dispatched during `/moira init` to discover available MCP servers and classify their tools.

**Scanner responsibilities:**
1. Read the current MCP configuration (from Claude Code's settings / environment)
2. List all available MCP servers and their tools
3. Classify each server by type (documentation, design, code, search, etc.)
4. For each tool: determine purpose, cost, reliability, usage guidelines
5. Estimate token budget impact per tool call
6. Output structured frontmatter for registry generation

**Scanner output format (frontmatter):**
```yaml
---
mcp_servers:
  context7:
    type: documentation
    tools:
      resolve-library-id:
        purpose: "Find library identifier for doc lookup"
        cost: low
        reliability: high
        when_to_use: "When agent needs docs for a specific library"
        when_NOT_to_use: "For internal project code, for general knowledge"
        token_estimate: 2000
      query-docs:
        purpose: "Fetch documentation for a library"
        cost: medium-high
        reliability: high
        when_to_use: "When implementation requires specific API knowledge"
        when_NOT_to_use: "For exploratory browsing, when project has local docs"
        budget_impact: "~5-20k tokens per query"
        token_estimate: 14000
---
```

**Scanner dispatch:**
- Dispatched via Agent tool (Hermes/explorer with Layer 4 MCP-scan instructions)
- Runs as part of init, AFTER tech scan (the scanner needs to know the project stack to make good MCP classification decisions)
- Quick scan only — deep MCP analysis is not needed (tools are self-describing)

**Design note:** The scanner reads MCP configuration that Claude Code already knows about. It doesn't install or configure MCP servers — just catalogs what's available and classifies each tool's purpose, cost, and guidelines.

### D3: MCP Library (`src/global/lib/mcp.sh`)

Shell library for reading and querying the MCP registry.

#### `moira_mcp_registry_exists <project_root>`

Check if MCP registry exists and is non-empty.
- Returns 0 if registry exists and has content
- Returns 1 otherwise

#### `moira_mcp_is_enabled <project_root>`

Check if MCP is enabled in project config.
- Reads `config.yaml` → `mcp.enabled`
- Returns 0 if enabled, 1 if disabled

#### `moira_mcp_list_servers <project_root>`

List all registered MCP server names.
- Parses `mcp-registry.yaml` top-level keys under `servers:`
- Outputs one server name per line

#### `moira_mcp_get_tool_info <project_root> <server> <tool>`

Get metadata for a specific MCP tool.
- Outputs: purpose, cost, when_to_use, when_NOT_to_use, token_estimate
- Returns 1 if server/tool not found

#### `moira_mcp_get_token_estimate <project_root> <server> <tool>`

Get token estimate for a specific MCP tool call.
- Falls back to `budgets.yaml` → `mcp_estimates.{server}_{tool}` if registry has no estimate
- Falls back to `mcp_estimates.default_call` (5000) as final fallback
- Outputs: integer token count

#### `moira_mcp_generate_registry <project_root> <scan_results_dir>`

Generate `mcp-registry.yaml` from scanner output frontmatter.
- Reads MCP scan results (frontmatter from scan output)
- Writes to `config/mcp-registry.yaml`
- Sets `mcp.enabled: true` in config.yaml if servers found

### D4: Bootstrap Integration — MCP Discovery in `/moira:init`

Wire MCP discovery into the bootstrap flow.

#### D4a: Update `bootstrap.sh`

Add new function `moira_bootstrap_scan_mcp`:
1. Check if MCP servers are available (check environment / settings)
2. If no MCP servers detected: set `mcp.enabled: false`, skip scan, log "No MCP servers detected"
3. If MCP servers available: dispatch MCP discovery scanner
4. Parse scanner results, generate `mcp-registry.yaml` via `moira_mcp_generate_registry`
5. Set `mcp.enabled: true` in config.yaml
6. Log result: "MCP registry: {N} servers, {M} tools cataloged"

#### D4b: Update `init.md` command

Insert MCP discovery as a new step in the init flow:
- Placed AFTER scanner steps (tech/structure/convention/pattern) and config generation
- Placed BEFORE knowledge generation (MCP might inform knowledge setup)
- Display MCP status in init gate summary:
  ```
  Configured:
  ├─ ...existing items...
  └─ MCP: {N} servers registered ({server1}, {server2}, ...)
  ```
  or:
  ```
  └─ MCP: no servers detected (can add later with /moira:refresh)
  ```

#### D4c: Update `scaffold.sh`

Ensure the `knowledge/libraries/` directory is created during scaffold (for future MCP knowledge caching).

### D5: Planner MCP Allocation — Dispatch Integration

Wire MCP allocation into the agent instruction assembly process.

#### D5a: Update `dispatch.md` — MCP Section in Prompt Template

Add an MCP section to the prompt template used by simplified assembly. **Update (D-115):** Infrastructure MCP (Ariadne) is now injected into ALL agent prompts in ALL pipelines via dispatch step 4c. Pre-planning agents DO get infrastructure MCP. External MCP: post-planning agents get it from instruction files; Quick Pipeline agents get it from registry-based guidelines.

For Daedalus (planner), add MCP context to the simplified assembly prompt:

```
## Available MCP Tools

{If MCP is enabled and registry exists:}
The following MCP servers and tools are available for allocation to agents:

{For each server in registry:}
### {server_name} ({type})
{For each tool:}
- **{tool_name}**: {purpose}
  - Cost: {cost}, Reliability: {reliability}
  - Use when: {when_to_use}
  - Do NOT use when: {when_NOT_to_use}
  - Token estimate: ~{token_estimate} tokens

When creating plan steps, explicitly AUTHORIZE or PROHIBIT MCP tools per step:
- AUTHORIZE with justification and budget impact
- PROHIBIT with reason (e.g., "design already extracted", "agent should know this")
- Include MCP token estimates in step budget calculations

{If MCP is disabled:}
MCP tools are not configured for this project. Do not allocate MCP tools in plan steps.
```

#### D5b: Update `dispatch.md` — Agent MCP Rules

For post-planning agents (Hephaestus, Themis, Aletheia), Daedalus already writes instruction files. Add documentation that Daedalus MUST include MCP authorization section in instruction files:

```
## MCP Usage Rules for This Step

{If step has authorized MCP tools:}
You MAY use:
- {server}:{tool} for "{specific query}" — {justification}

You MUST NOT use:
- Any other MCP tool
- {server}:{tool} for {reason it's prohibited}

Before calling any MCP tool, verify:
1. Do I actually need this to write correct code?
2. Is this available in project files I was given?
3. Will the response fit within my context budget?

If (1) is no or (2) is yes → DO NOT call.

{If step has no MCP authorization:}
No MCP tools are authorized for this step. Do not use any MCP tools.
```

This section is already part of the Planner's output format in `daedalus.yaml` — Phase 9 provides the registry data that makes it actionable.

#### D5c: Update Daedalus role rules

The current `daedalus.yaml` already mentions MCP allocation. Add explicit capability: "Read MCP registry to determine available tools and their costs for allocation."

Add to identity section: "When MCP is enabled, you read the MCP registry to determine available tools and their token costs. You include MCP authorization sections in each agent's instruction file."

### D6: Agent MCP Instruction Templates

Define the MCP instruction patterns that get included in agent prompts.

#### D6a: MCP Rules for Hephaestus (implementer)

Hephaestus already has "Use authorized MCP tools only" in role rules. Add a verification checklist to the identity section:

```
Before using any MCP tool:
1. Verify it is listed in your "MCP Usage Rules" section as authorized
2. Use the specific query pattern authorized in the plan
3. If MCP response exceeds expected token budget: note in your status summary
4. If MCP call fails: continue without it, note the failure, do NOT fabricate the information
```

#### D6b: MCP Verification for Themis (reviewer)

Themis already has "Verify MCP calls were used correctly" in role rules. Add explicit verification steps:

```
MCP Usage Review:
- All MCP calls were authorized in the plan
- No unauthorized MCP calls were made
- MCP responses were actually used (not fetched and ignored)
- No MCP calls for information available locally
- Results from MCP were applied correctly (not misinterpreted)
- MCP token usage was within estimated budget
```

### D7: Reviewer MCP Checklist Items

Add MCP-specific section to `q4-correctness.yaml` quality checklist. Uses existing item format (`id`, `check`, `required`). Items use `required: false` because they only apply when MCP tools were used in the step — reviewer skips with `na` justification when no MCP usage.

**New section to add:**

```yaml
  mcp_usage:
    items:
      - id: Q4-M01
        check: "All MCP tool calls were authorized in the plan"
        required: false
      - id: Q4-M02
        check: "No unauthorized MCP calls were made"
        required: false
      - id: Q4-M03
        check: "No MCP calls for information available in project files"
        required: false
      - id: Q4-M04
        check: "MCP responses were actually used (not fetched and ignored)"
        required: false
      - id: Q4-M05
        check: "MCP results were applied correctly (not misinterpreted)"
        required: false
```

This matches the 5-item checklist from `mcp.md` design doc. The additional "MCP token usage was within estimated budget" item from D6b is left as a Themis behavioral instruction (D6b), not a formal checklist item — budget tracking is already covered by the budget system.

### D8: Knowledge Caching Structure

Set up the knowledge caching infrastructure for frequently-used MCP documentation.

#### D8a: Knowledge template (`src/global/templates/knowledge/libraries/`)

Create template files:

- `index.md` — L0: list of cached libraries with last-updated timestamps
- `summary.md` — L1: key API facts per library (one-line summaries)

**Template format for `index.md`:**
```markdown
# Cached Library Documentation

Libraries cached from MCP documentation calls to avoid repeated lookups.

| Library | Last Updated | Source |
|---------|-------------|--------|
```

**Template format for individual library files** (created by Reflector in Phase 10, not Phase 9):
```markdown
# {library-name} — Cached API Reference

**Source:** {mcp_server}:{tool}("{query}")
**Cached:** {date}
**Tokens saved per use:** ~{N}k

## Key APIs

{essential API reference extracted from MCP responses}
```

#### D8b: Update scaffold

Ensure `knowledge/libraries/` is created during scaffold. (Already covered in D4c.)

**Phase 9 scope for caching:** Phase 9 creates the STRUCTURE for knowledge caching (directories, templates). The actual caching logic (detecting repeated MCP calls, proposing cache entries, managing freshness) is Phase 10 (Reflector) scope. Phase 9 ensures the Reflector will have somewhere to write when it implements caching.

### D9: Refresh Command — MCP Re-scan

Update `/moira:refresh` to support MCP registry updates.

#### D9a: Update `refresh.md`

Add MCP re-scan capability:
- When user runs `/moira:refresh`, include MCP re-discovery as part of the refresh
- Re-dispatch MCP scanner
- Merge new results with existing registry (new servers added, removed servers flagged)
- Preserve any user customizations to existing tool entries (don't overwrite if user edited)

**Display:**
```
MCP Registry: updated
├─ Servers: {N} ({+added}, {-removed})
└─ Tools: {M} total
```

### D10: Tier 1 Tests (`src/tests/tier1/test-mcp-system.sh`)

New test file for MCP system structural verification.

**Schema tests:**
- `mcp-registry.schema.yaml` exists in `schemas/`
- Schema has `servers` as top-level key

**Library tests:**
- `mcp.sh` exists in `lib/`
- `mcp.sh` has valid bash syntax (`bash -n`)
- Functions exist: `moira_mcp_registry_exists`, `moira_mcp_is_enabled`, `moira_mcp_list_servers`, `moira_mcp_get_tool_info`, `moira_mcp_get_token_estimate`, `moira_mcp_generate_registry`

**Scanner tests:**
- `mcp-scan.md` exists in `templates/scanners/`
- Scanner contains frontmatter extraction markers (scanner output format)

**Integration tests:**
- `config.schema.yaml` has `mcp.enabled` and `mcp.registry_path` fields (already present — verify unchanged)
- `budgets.yaml.tmpl` has `mcp_estimates` section (already present — verify unchanged)
- `daedalus.yaml` mentions MCP allocation (already present — verify unchanged)
- `hephaestus.yaml` mentions MCP authorization (already present — verify unchanged)
- `themis.yaml` mentions MCP verification (already present — verify unchanged)
- `q4-correctness.yaml` has MCP-related checklist items (`Q4-M0*`)

**Knowledge template tests:**
- `templates/knowledge/libraries/index.md` exists
- `templates/knowledge/libraries/summary.md` exists

## Ripple Effect Updates (files affected by Phase 9 changes)

These are existing files that must be updated for correctness. They are NOT new deliverables — they are integration points discovered during impact analysis.

1. **`install.sh` lib verify list** — Add `mcp.sh` to the hardcoded lib file verification loop (currently lists 11 files, `mcp.sh` makes 12)
2. **`install.sh` verify thresholds** — Bump scanner count check from `>=4` to `>=5`, knowledge template count from `>=17` to `>=19`
3. **`test-file-structure.sh` lib checks** — Add `mcp.sh` to the lib existence/syntax check list
4. **`init.md` step renumbering** — MCP discovery inserts between current Steps 5 (Config) and 6 (Knowledge). Steps 6-11 shift to 7-12. Spec must specify new numbering.

## Design Doc Corrections (incidental fixes during Phase 9)

1. **`design/architecture/overview.md`** — `lib/` section should list `mcp.sh`; `schemas/` section should list `mcp-registry.schema.yaml`
2. **`design/subsystems/mcp.md`** — Registry `tools` format should use YAML map (not list-of-maps) per D-078 decision

## Non-Deliverables (explicitly deferred)

- **Automatic MCP knowledge caching** (Phase 10): Reflector tracks repeated MCP calls and proposes caching. Phase 9 provides the structure; Phase 10 provides the automation.
- **MCP call telemetry/tracking** (Phase 11): Phase 9's "tracking" means explicit allocation by Planner + behavioral verification by Reviewer, not runtime call recording. MCP usage metrics aggregation across tasks is Phase 11 scope.
- **MCP server installation/configuration**: Moira catalogs existing MCP servers, it doesn't install or configure them. Users manage MCP servers through Claude Code's native mechanism.
- **Runtime MCP call interception**: Moira cannot intercept or block MCP calls at runtime. Authorization is via instruction prompting (agent rules), not enforcement.
- **MCP tool versioning**: Registry doesn't track MCP tool versions. If tools change, `/moira:refresh` re-scans.
- **`knowledge.sh` libraries type** (Phase 10): `_MOIRA_KNOWLEDGE_TYPES` in `knowledge.sh` currently lists 6 types (project-model, conventions, decisions, patterns, failures, quality-map). Adding `libraries` to this list is deferred to Phase 10 when the Reflector implements actual caching logic. Phase 9 creates the directory structure and templates; Phase 10 wires them into the knowledge system. The same applies to `knowledge-access-matrix.yaml` — the `libraries` dimension will be added when agents need to read cached library knowledge.

## Architectural Decisions

**Note:** All AD entries below must be added to `design/decisions/log.md` as D-078 through D-084 before implementation begins (per D-018 / Art 6.2).

### AD-1 (→ D-078): MCP Authorization via Prompting (Not Enforcement)

MCP tool authorization is enforced via agent instructions (prompting), not via `allowed-tools` or hooks. Agents receive explicit lists of authorized and prohibited MCP tools.

**Rationale:**
1. Claude Code's `allowed-tools` cannot selectively allow MCP tools per step — it's session-wide
2. MCP tools are available to all agents by default (they're in the environment)
3. Prompting-based authorization matches how we handle other agent constraints (NEVER rules)
4. Reviewer (Themis) provides behavioral verification that MCP rules were followed
5. This is consistent with D-031's defense-in-depth: prompting is Layer 3, behavioral review is additional validation

### AD-2 (→ D-079): MCP Scanner as Hermes (Explorer) Dispatch

MCP discovery uses the same Explorer agent pattern as other bootstrap scanners (tech, structure, convention, pattern). The scanner is a Layer 4 instruction template.

**Rationale:**
1. Consistent with existing scanner architecture (D-032)
2. Explorer is the only agent that reads system state — MCP configuration is system state
3. Layer 4 instructions customize the Explorer for the specific scan type
4. No new agent type needed — follows Art 1.3 (no god components)

### AD-3 (→ D-080): Registry in Config (Committed), Not State (Gitignored)

MCP registry lives in `.moira/config/mcp-registry.yaml` (committed) — same as `budgets.yaml` and `locks.yaml`.

**Rationale:**
1. Registry is project configuration, not ephemeral state
2. Team members share the same MCP tool classifications
3. User customizations (editing when_to_use, adjusting token_estimates) should persist
4. Already defined this way in `overview.md` file structure and `config.schema.yaml`

### AD-4 (→ D-081): MCP Caching Structure Now, Logic Later

Phase 9 creates `knowledge/libraries/` directory and templates. Phase 10 (Reflector) implements the actual caching logic (repeated call detection, cache proposal, freshness management).

**Rationale:**
1. Reflector doesn't exist until Phase 10 — it's the agent that tracks patterns across tasks
2. Creating structure now means Phase 10 has somewhere to write
3. Clean separation: Phase 9 = infrastructure, Phase 10 = intelligence

### AD-5 (→ D-082): Registry `tools` as Map (Not List-of-Maps)

The design doc (`mcp.md`) shows registry tools as a YAML list-of-maps. We use a YAML map instead (tool name as key, metadata as value) for natural key-based lookups.

**Rationale:**
1. Map format enables direct key lookup: `servers.context7.tools.query-docs`
2. Tool names are unique within a server — natural keys
3. Consistent with how `config.yaml` and `budgets.yaml` use map structures
4. Simpler parsing in shell scripts (grep for `tool_name:` indent level)

### AD-6 (→ D-083): `token_estimate` Numeric Field in Registry

The registry schema adds a `token_estimate` (number) field per tool, extending the design doc's `budget_impact` (string) field. Both fields coexist: `budget_impact` for human display, `token_estimate` for budget calculations.

**Rationale:**
1. D-059 specifies config-driven MCP token estimates — numeric field bridges registry with budget system
2. `budget_impact` is a descriptive string ("~5-20k tokens per query") — not machine-readable
3. `token_estimate` provides the machine-readable number that `moira_budget_estimate_agent` needs
4. Fallback chain: registry `token_estimate` → `budgets.yaml` `mcp_estimates` → default 5000

### AD-7 (→ D-084): Registry Merge Strategy on Refresh

When `/moira:refresh` re-scans MCP servers, the merge strategy is: add new servers, flag removed servers, preserve user customizations to existing tool entries.

**Rationale:**
1. Users may edit `when_to_use`, `token_estimate`, etc. — overwriting loses their tuning
2. Removed servers should be flagged (not silently deleted) — user may have intentionally configured them
3. New servers are always added — no reason to exclude available tools
4. This is consistent with how `/moira:refresh` handles knowledge updates (additive, not destructive)

## Success Criteria

1. **MCP registry schema exists and is valid:** `mcp-registry.schema.yaml` defines server/tool structure
2. **MCP scanner template exists:** `mcp-scan.md` can be dispatched during init
3. **MCP library functions work:** `mcp.sh` can read/query registry
4. **Bootstrap generates registry:** `/moira init` on a project with MCP servers produces `mcp-registry.yaml`
5. **Bootstrap handles no-MCP gracefully:** `/moira init` without MCP servers sets `mcp.enabled: false` and skips
6. **Planner receives MCP context:** When MCP is enabled, Daedalus gets the registry in dispatch prompt
7. **Agent instructions include MCP rules:** Instruction files contain MCP authorization/prohibition sections
8. **Reviewer checks MCP usage:** q4-correctness has MCP-specific checklist items
9. **Knowledge caching structure exists:** `knowledge/libraries/` directory and templates ready for Phase 10
10. **Refresh updates registry:** `/moira:refresh` re-scans MCP servers
11. **Tier 1 tests pass:** All existing + new Phase 9 structural tests pass
12. **Constitutional compliance:** All 19 invariants satisfied

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Orchestrator does not use MCP tools directly. MCP tools are
         allocated to agents via Planner instructions. Orchestrator only
         reads registry metadata (in .moira/ — within scope).
[✓] 1.2 — Agent roles maintained: Planner allocates MCP, Implementer uses
         MCP, Reviewer verifies MCP. No agent crosses boundaries.
[✓] 1.3 — MCP library is a focused utility (registry read/query). Scanner
         is a Layer 4 instruction template, not a new agent type.

ARTICLE 2: Determinism
[✓] 2.1 — MCP availability does not affect pipeline selection. Same
         classification = same pipeline, with or without MCP.
[✓] 2.2 — MCP does not affect gate definitions. No new gates added.
[✓] 2.3 — MCP authorization is explicit in plan steps. Agents receive
         specific lists of authorized/prohibited tools — no "judgment."

ARTICLE 3: Transparency
[✓] 3.1 — MCP allocations are in plan artifacts (traceable). MCP usage
         recorded in agent output files.
[✓] 3.2 — MCP token estimates included in budget calculations. Budget
         report shows MCP impact.
[✓] 3.3 — MCP failures reported by agents (not silently ignored).
         Agents must note MCP failures in status summary.

ARTICLE 4: Safety
[✓] 4.1 — If MCP call fails, agent must NOT fabricate the information.
         Must report failure and continue without or block.
[✓] 4.2 — MCP doesn't bypass gates. User still approves all decisions.
[✓] 4.3 — MCP doesn't affect rollback. Code changes are git-backed
         regardless of whether MCP was used.
[✓] 4.4 — N/A (MCP doesn't interact with bypass mechanism)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — Cached MCP knowledge (Phase 10) will require evidence
         (MCP call results from actual tasks).
[✓] 5.2 — MCP caching requires 3+ calls (Phase 10 Reflector logic).
[✓] 5.3 — N/A for Phase 9 (no knowledge writes, only structure)

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation (D-018)
[✓] 6.3 — Tier 1 tests validate MCP system artifacts
```
