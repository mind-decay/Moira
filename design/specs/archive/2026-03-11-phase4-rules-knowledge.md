# Phase 4: Rules Assembly & Knowledge System

## Goal

The Planner (Daedalus) can assemble multi-layer rules (L1-L4) into self-contained agent instruction files. The knowledge base can be read at correct levels per agent and written with freshness tracking, consistency validation, and archival rotation.

Phase 4 replaces Phase 3's simplified inline prompt construction (AD-3) with the full rule assembly system described in `design/architecture/rules.md`. It also builds the knowledge infrastructure described in `design/subsystems/knowledge.md` that all subsequent phases depend on (Bootstrap in Phase 5, Reflection in Phase 10, Audit in Phase 11).

## Risk Classification

**ORANGE** — New knowledge structure, rule assembly changes, pipeline flow changes. Needs design doc update first for any deviations.

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/CONSTITUTION.md` | Art 1.2 (agent single responsibility), Art 2.3 (no assumptions), Art 5.1-5.3 (knowledge integrity) |
| `design/architecture/rules.md` | L1-L4 layer system, assembly process, conflict detection |
| `design/subsystems/knowledge.md` | L0/L1/L2 levels, agent access matrix, freshness, archival, consistency |
| `design/architecture/agents.md` | Daedalus capabilities, agent knowledge access per agent |
| `design/architecture/overview.md` | File structure (knowledge/, project/rules/), data flow |
| `design/subsystems/quality.md` | Quality-map structure (Strong/Adequate/Problematic) |
| `design/architecture/naming.md` | Greek names, display conventions |
| `design/IMPLEMENTATION-GUIDE.md` | Rules assembly guidance, knowledge system guidance |
| `design/decisions/log.md` | D-005 (modular rules), D-006 (three-level knowledge), D-032 (scanner = Explorer invocations) |

## Prerequisites (from Phase 1-3)

- **Phase 1:** Directory scaffold (`scaffold.sh`), YAML utilities (`yaml-utils.sh`), state management (`state.sh`), task ID generation
- **Phase 2:** All 10 agent role definitions (`roles/*.yaml`), base rules (`base.yaml`), quality criteria files, response contract, knowledge access matrix (`knowledge-access-matrix.yaml`)
- **Phase 3:** Orchestrator skill (`orchestrator.md`), dispatch module (`dispatch.md`), pipeline definitions, gate system, error handling (E1-E6 full, E7-E8 stubs)

## Deliverables

### D1: Knowledge Shell Library (`src/global/lib/knowledge.sh`)

Shell library providing knowledge read/write/freshness operations. Built on `yaml-utils.sh` patterns (bash 3.2+ compatible, no jq/python dependencies).

**Functions:**

#### `moira_knowledge_read <knowledge_dir> <knowledge_type> <level>`
Read a knowledge file at a specific level.

- `knowledge_type`: `project-model`, `conventions`, `decisions`, `patterns`, `failures`, `quality-map`
- `level`: `L0`, `L1`, `L2`
- Level-to-file mapping:
  - `L0` → `{type}/index.md`
  - `L1` → `{type}/summary.md`
  - `L2` → `{type}/full.md`
- Returns file contents or empty string if file doesn't exist
- Special case: `quality-map` has no L0 (only summary + full per `knowledge.md`)

#### `moira_knowledge_read_for_agent <knowledge_dir> <agent_name>`
Read all knowledge an agent is authorized to access per the knowledge access matrix.

- Reads `knowledge-access-matrix.yaml` for the agent's access levels
- Matrix includes all 6 knowledge dimensions: `project_model`, `conventions`, `decisions`, `patterns`, `quality_map`, `failures`
- For each knowledge type with non-null access: reads the file at the specified level
- Special case: `quality_map` has no L0 file (AD-6). If matrix specifies L0 for quality-map, skip it silently (no error).
- Returns concatenated content with clear section headers:
  ```
  ## Knowledge: Project Model (L1)
  {content of project-model/summary.md}

  ## Knowledge: Conventions (L2)
  {content of conventions/full.md}
  ```
- Skips types where access is `null`

#### `moira_knowledge_write <knowledge_dir> <knowledge_type> <level> <content> <task_id>`
Write content to a knowledge file with freshness marker.

- Prepends freshness tag: `<!-- moira:freshness {task_id} {date} -->`
- Writes to the appropriate level file
- If file exists: replaces content (preserves freshness history by appending old marker to end)
- If file doesn't exist: creates it with header + content

#### `moira_knowledge_freshness <knowledge_dir> <knowledge_type> <current_task_number>`
Check freshness of a knowledge entry.

- Reads first `<!-- moira:freshness ... -->` tag from the file
- Extracts task ID and date
- Calculates task distance: `current_task_number - entry_task_number`
- Returns category:
  - `fresh` (< 10 tasks ago)
  - `aging` (10-20 tasks ago)
  - `stale` (> 20 tasks ago)
  - `unknown` (no freshness tag found)

#### `moira_knowledge_stale_entries <knowledge_dir> <current_task_number>`
List all stale knowledge entries.

- Scans all knowledge files for freshness tags
- Returns list of stale entries with their type and last task ID

#### `moira_knowledge_archive_rotate <knowledge_dir> <knowledge_type> <max_entries>`
Rotate old entries to archive (for decisions and patterns).

- Counts entries in `{type}/full.md` (entries delimited by `## ` headers)
- If count > `max_entries`: moves oldest entries to `{type}/archive/batch-{NNN}.md`
- Updates `{type}/summary.md` to reflect all entries (active + archived)
- Default `max_entries`: 20 (per `knowledge.md`)

#### `moira_knowledge_validate_consistency <knowledge_dir> <knowledge_type> <new_content>`
Check new knowledge against existing for contradictions.

- Reads existing content at L1 level
- Returns one of: `confirm`, `extend`, `conflict`
- Implementation: keyword-based heuristic (looks for contradictory signals — different values for same keys, opposite qualifiers)
- On `conflict`: does NOT write, returns conflict details for agent resolution
- Note: this is a structural check, not semantic. Full semantic consistency validation is deferred to agents (Reflector/Auditor) who can reason about content.

### D2: Rules Assembly Library (`src/global/lib/rules.sh`)

Shell library for rule layer loading, conflict detection, and instruction file generation.

**Functions:**

#### `moira_rules_load_layer <layer_number> <source_path>`
Load a single rule layer from file.

- L1: reads `base.yaml` → extracts `inviolable` and `overridable` sections
- L2: reads `roles/{agent}.yaml` → extracts `identity`, `capabilities`, `never`, `knowledge_access`, `quality_checklist`
- L3: reads `project/rules/*.yaml` → extracts relevant project rules (stack, conventions, patterns, boundaries)
- L4: task-specific — passed as content, not loaded from file

#### `moira_rules_detect_conflicts <base_file> <project_rules_dir>`
Detect conflicts between rule layers.

- `role_file` parameter removed: L2 (role constraints) are behavioral constraints ("never do X"), not key-value overrides — they cannot structurally conflict with L3 project rules. Conflict detection only applies to L1 overridable defaults vs L3 project values.
- Compares overridable defaults from L1 with project rules from L3
- Returns list of conflicts with resolution:
  ```
  CONFLICT: max_function_length
    L1 (base): 50
    L3 (project): 100
    RESOLUTION: L3 wins (project override)
  ```
- Flags if any L3 rule conflicts with L1 inviolable rules (ERROR — inviolable cannot be overridden)
- Returns exit code 1 if inviolable conflict detected

#### `moira_rules_assemble_instruction <output_path> <agent_name> <base_file> <role_file> <project_rules_dir> <knowledge_dir> <task_context_file> <matrix_file>`
Assemble a complete agent instruction file.

- Loads all 4 layers
- Runs conflict detection
- Reads knowledge at agent's authorized levels (per matrix)
- Writes assembled instruction to `output_path` in this format:

```markdown
# Instructions for {AgentDisplayName} ({role})

## Identity
{from L2 role yaml identity field}

## Rules

### Inviolable (NEVER violate — Constitution enforced)
{from L1 base.yaml inviolable list}

### Role Constraints
{from L2 role yaml never list}

### Project Rules
{from L3 — relevant subset per agent role:
  - Implementer/Reviewer/Tester: stack + conventions + patterns + boundaries
  - Architect: stack + patterns + boundaries
  - Planner: stack + conventions (summary level)
  - Explorer/Classifier/Analyst: minimal (stack summary only)}

## Knowledge
{assembled by moira_knowledge_read_for_agent — each section labeled with type and level}

## Quality Checklist
{from L2 quality_checklist reference → reads the actual checklist YAML}

## Response Contract
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <1-2 sentences>
ARTIFACTS: [<file paths>]
NEXT: <recommended next step>

Write all detailed output to artifact files. Return ONLY the status summary above.

## Task
{L4 — task-specific context from task_context_file}

## Output
Write your detailed results to: {artifact_path}
```

#### `moira_rules_project_rules_for_agent <agent_name> <project_rules_dir>`
Determine which project rule files are relevant for a given agent.

- Returns the subset of L3 rules applicable to the agent's role:
  - `hephaestus`, `themis`, `aletheia`: all project rules (stack, conventions, patterns, boundaries)
  - `metis`: stack, patterns, boundaries
  - `daedalus`: stack, conventions
  - `hermes`, `apollo`, `athena`: stack only (minimal context)
  - `mnemosyne`, `argus`: all project rules (full access)

### D3: Updated Dispatch Module (`src/global/skills/dispatch.md`)

Replace Phase 3 simplified prompt assembly with full rule assembly.

**Changes:**

The current Phase 3 dispatch module reads role YAML + base YAML + response contract + task context inline. Phase 4 replaces this with:

1. **If instruction file exists** (`state/tasks/{id}/instructions/{agent}.md`):
   - Read the pre-assembled instruction file (written by Daedalus during planning step)
   - Use its contents as the agent prompt directly
   - This is the primary path for Standard/Full/Decomposition pipelines

2. **If no instruction file** (fallback for Quick pipeline or pre-planning steps):
   - Use the Phase 3 simplified assembly (kept as fallback)
   - This covers: Apollo (classifier) — always runs before Planner
   - This covers: Hermes (explorer) + Athena (analyst) — run before Planner in Standard/Full
   - Quick pipeline: all agents use simplified assembly (no Planner step)

3. **Pre-planning agents always use simplified assembly** — they run before Daedalus, so no instruction files exist yet. This is by design, not a gap.

**Section updates:**
- Rename current "Prompt Construction (Phase 3 Simplified)" to "Prompt Construction"
- Add "Pre-assembled Instructions" subsection describing the instruction file path
- Add decision logic: check for instruction file → if exists, use it; if not, fallback to simplified assembly
- Document which agents use which path

### D4: Updated Daedalus (Planner) Role Definition

Enhance `src/global/core/rules/roles/daedalus.yaml` with explicit rule assembly capabilities.

**Changes to identity:**
Add explicit mention that Daedalus assembles L1-L4 rules into instruction files as part of the planning step.

**Changes to capabilities:**
Already includes "Assemble agent instructions (Layer 1-4 rules) per step" — no change needed.

**New planning output structure:**
Daedalus' artifact (`plan.md`) must now include:
- Step-by-step execution plan (existing)
- Dependency graph (existing)
- Budget estimates per step (existing)
- **Conflict report** (NEW) — any rule conflicts detected and resolutions
- **Knowledge inclusion manifest** (NEW) — which knowledge at which level for each agent
- **Instruction files written** (NEW) — list of `instructions/{agent}.md` files created

**Key behavioral change:**
In Phase 3, Daedalus produced only a plan. In Phase 4, Daedalus also WRITES the instruction files to `state/tasks/{id}/instructions/`. The orchestrator no longer constructs prompts at dispatch time for post-planning agents — it reads the pre-assembled files.

### D5: Knowledge Template Files

Template knowledge files installed by `scaffold.sh` when a project is initialized. These are starter templates — Bootstrap (Phase 5) populates them with real data.

**Files created in `.moira/knowledge/`:**

```
knowledge/
├── project-model/
│   ├── index.md              # L0 template
│   ├── summary.md            # L1 template
│   └── full.md               # L2 template
├── conventions/
│   ├── index.md
│   ├── summary.md
│   └── full.md
├── decisions/
│   ├── index.md
│   ├── summary.md
│   ├── full.md
│   └── archive/              # Directory for rotated entries
├── patterns/
│   ├── index.md
│   ├── summary.md
│   ├── full.md
│   └── archive/
├── failures/
│   ├── index.md
│   ├── summary.md
│   └── full.md
└── quality-map/
    ├── summary.md            # No L0 for quality-map
    └── full.md
```

**Template format (example for `project-model/index.md`):**
```markdown
<!-- moira:knowledge project-model L0 -->
# Project Model — Index

> This file is auto-populated by /moira:init. Manual edits are preserved.

## Sections
- Domain: (not yet scanned)
- Architecture: (not yet scanned)
- Data Flow: (not yet scanned)
- Critical Paths: (not yet scanned)
- Boundaries: (not yet scanned)
- Pain Points: (not yet scanned)
```

Each template file includes:
- Knowledge type and level header tag (`<!-- moira:knowledge {type} {level} -->`)
- Placeholder sections matching the structure defined in `knowledge.md`
- "(not yet scanned)" markers for Bootstrap to replace

### D6: Updated Scaffold (`src/global/lib/scaffold.sh`)

Update `moira_scaffold_project()` to create knowledge directory structure.

**New directories:**
- `knowledge/project-model/`
- `knowledge/conventions/`
- `knowledge/decisions/archive/`
- `knowledge/patterns/archive/`
- `knowledge/failures/`
- `knowledge/quality-map/`

**New template file copies:**
- Copy knowledge template files (from D5) into the created directories
- Template source: `~/.claude/moira/templates/knowledge/` (installed by `install.sh`)

### D7: Knowledge Templates Source (`src/global/templates/knowledge/`)

The actual template files that `install.sh` installs to `~/.claude/moira/templates/knowledge/` and `scaffold.sh` copies to projects.

**Structure mirrors D5** — one template per knowledge file, 17 files total (6 types x 3 levels, minus quality-map L0, plus 2 archive directories).

### D8: Updated `install.sh`

Add Phase 4 artifacts to the installation script.

**New copy operations:**
- `global/lib/knowledge.sh` → `$MOIRA_HOME/lib/knowledge.sh`
- `global/lib/rules.sh` → `$MOIRA_HOME/lib/rules.sh`
- `global/templates/knowledge/` → `$MOIRA_HOME/templates/knowledge/`

**New verification checks:**
- `knowledge.sh` exists and is executable
- `rules.sh` exists and is executable
- Knowledge template directory exists with all 17 template files
- Knowledge access matrix exists (`knowledge-access-matrix.yaml`)

### D9: E8 Stub Upgrade

Phase 3 left E8 (stale knowledge) as a stub (D-038). With the knowledge freshness system now available, partially implement E8:

**Changes to `errors.md`:**
- E8 detection: at pipeline start, check freshness of knowledge entries used by the pipeline
- If any stale entries found: display warning to user (not blocking)
- Log stale entries to task status
- Suggest `/moira:refresh` to update knowledge

**NOT implemented yet (deferred to Phase 10/11):**
- Automatic knowledge refresh during pipeline
- Impact assessment of stale knowledge on task quality

### D10: Tier 1 Test Additions (`src/tests/tier1/`)

#### New test file: `test-rules-assembly.sh`

Tests for rule assembly system:
- L1 base rules load correctly (inviolable + overridable sections present)
- L2 role rules load for each of 10 agents
- Conflict detection: L3 overriding L1 overridable → resolved (L3 wins)
- Conflict detection: L3 overriding L1 inviolable → ERROR
- Assembled instruction file contains all required sections (Identity, Rules, Knowledge, Quality Checklist, Response Contract, Task, Output)
- Project rules subset is correct per agent role (per D2 `moira_rules_project_rules_for_agent`)
- Agent instruction file does NOT contain knowledge types the agent shouldn't access (Art 1.2 enforcement)
- Agent instruction file for hephaestus does NOT contain failures or quality-map content
- Agent instruction file for mnemosyne contains ALL 6 knowledge types at L2

#### New test file: `test-knowledge-system.sh`

Tests for knowledge system:
- Knowledge directory structure matches spec (all 6 types, correct level files)
- `moira_knowledge_read` returns correct file per level (L0→index, L1→summary, L2→full)
- `moira_knowledge_read_for_agent` returns only authorized levels per knowledge-access-matrix
- Explorer (hermes) gets L0 project-model ONLY (minimal bias, no quality-map/failures)
- Architect (metis) gets L2 decisions (full access) + L1 quality-map
- Implementer (hephaestus) gets L2 conventions (full access, no quality-map/failures)
- Reflector (mnemosyne) gets L2 for ALL 6 types including failures and quality-map
- Planner (daedalus) quality-map L0 is skipped (no L0 file exists per AD-6)
- Freshness marker parsing: extracts task ID and date correctly
- Freshness categorization: fresh/aging/stale thresholds correct
- Stale entry detection finds entries older than 20 tasks
- Archive rotation moves entries to archive/ when threshold exceeded
- Consistency validation: returns `confirm`/`extend`/`conflict` correctly
- Knowledge entries contain evidence references (Art 5.1 structural check)
- Quality-map has no L0 level (only summary + full)

#### Extended existing tests:
- `test-file-structure.sh`: add checks for knowledge directories, template files, `lib/knowledge.sh`, `lib/rules.sh`
- `test-install.sh`: add verification for Phase 4 artifacts

## Non-Deliverables (explicitly deferred)

- **Bootstrap scanning** (Phase 5): Knowledge templates are created empty. Phase 5 populates them via Explorer invocations.
- **Knowledge organic growth** (Phase 10): Reflector updating knowledge after each task is a Phase 10 concern.
- **Full semantic consistency validation** (Phase 10/11): Phase 4 implements structural/heuristic checks only. Full semantic validation requires Reflector/Auditor agents reasoning about content.
- **MCP knowledge caching** (Phase 9): Reflector detecting repeated MCP calls and proposing caches.
- **Failures knowledge population** (Phase 10): Failures template files and matrix entries exist but are empty. Reflector (Phase 10) writes failure entries after observing rejected approaches.
- **Quality map generation** (Phase 6): Quality-map template is created but not populated. Phase 6 builds the quality gate system that fills it.
- **CONFORM/EVOLVE mode** (Phase 6): Mode switching is a Phase 6 concern.
- **Smart batching/parallel dispatch** (future): Rule assembly creates the foundation (contracts in instruction files), but parallel Implementer dispatch remains sequential per AD-5.
- **Knowledge-driven scope detection** (Phase 10): Using knowledge to detect scope mismatches automatically.

## Architectural Decisions

### AD-1: Daedalus Writes Instruction Files, Not Orchestrator

The Planner agent (Daedalus) reads all rule layers and knowledge, then writes assembled instruction files to `state/tasks/{id}/instructions/{agent}.md`. The orchestrator reads these files at dispatch time instead of constructing prompts inline.

**Rationale:** The Planner is the only agent that understands the full task plan and can determine which knowledge and rules each downstream agent needs. This keeps the orchestrator simple (just reads a file) and moves intelligence to the right place (the planning step). Consistent with Art 1.1 (orchestrator purity) and Art 1.2 (Planner's defined role includes "assembles agent instructions").

### AD-2: Dual Prompt Construction Path

Two paths for agent prompt construction:
1. **Pre-planning agents** (Apollo, Hermes, Athena): use simplified Phase 3 assembly (no instruction files exist yet)
2. **Post-planning agents** (Metis, Hephaestus, Themis, Aletheia): use pre-assembled instruction files from Daedalus

Quick pipeline: uses simplified assembly for all agents (no Planner step).

**Rationale:** Pre-planning agents run before Daedalus, so no instruction files can exist. Quick pipeline deliberately skips planning for speed. The simplified path is not a workaround — it's the correct minimal-context path for agents that don't need full project knowledge.

### AD-3: Structural Consistency Validation

Knowledge consistency validation (`moira_knowledge_validate_consistency`) uses structural/keyword heuristics, not LLM reasoning. It catches obvious contradictions (e.g., different values for the same key) but doesn't attempt semantic understanding.

**Rationale:** Shell utilities can't perform semantic reasoning. Full semantic consistency is the Reflector's and Auditor's job (Phase 10/11). Structural checks catch the most common and dangerous contradictions at write time without requiring agent dispatch. This follows the principle of proportional enforcement — cheap checks everywhere, expensive checks at appropriate points.

### AD-4: Knowledge Templates as Installed Files

Knowledge templates are part of the global installation (`~/.claude/moira/templates/knowledge/`) and copied to projects by `scaffold.sh`. They are NOT generated dynamically.

**Rationale:** Templates are static — they define structure, not content. Having them as files makes them testable (Tier 1 can verify structure), versionable, and inspectable. Consistent with D-020 (file-copy distribution model).

### AD-5: Freshness by Task Count, Not Time

Freshness is measured by task distance (how many tasks since last confirmation), not calendar time. A project that hasn't been touched in 3 months but had no tasks is not "stale" — the knowledge hasn't been contradicted.

**Rationale:** Per `knowledge.md`, freshness categories are defined by task count: fresh (<10), aging (10-20), stale (>20). Calendar time is not a reliable proxy for knowledge validity — a project could be dormant for months with no changes.

### AD-6: Quality-Map Has No L0 Level

The quality-map knowledge type has only L1 (summary) and L2 (full), not L0 (index). Unlike other knowledge types where an index helps agents decide if they need more detail, the quality-map is either used (you need the assessment) or not used at all.

**Rationale:** Per knowledge-access-matrix.yaml, Architect (metis, L1), Reviewer (themis, L1), and Planner (daedalus, L0) access quality-map. But even L0 for quality-map would be meaningless — an index that says "quality-map exists with 4 sections" provides zero value. Daedalus receives quality-map at L0 per knowledge.md, but since quality-map has no L0 file, this access is effectively skipped. This is by design — the Planner doesn't need quality assessments to decompose work.

### AD-7: Failures Knowledge Type Deferred to Phase 10

The `failures` knowledge type has templates and directory structure, but no agent has meaningful access to it until the Reflector (Phase 10) begins writing failure entries. The knowledge-access-matrix.yaml includes `failures` as a dimension with `null` for all agents except mnemosyne and argus (L2), who need full access for reflection and audit.

**Rationale:** Failures are written by the Reflector after observing rejected approaches across tasks. Before Phase 10, the failures knowledge directory exists but is empty (templates only). Adding the matrix dimension now avoids a schema change later.

## Success Criteria

1. **Rule assembly works:** Daedalus can produce instruction files for all 10 agents using L1-L4 merge
2. **Conflict detection works:** L3 overriding L1 overridable is resolved; L3 overriding L1 inviolable is rejected
3. **Instruction files are self-contained:** Each instruction file contains everything the agent needs — identity, rules, knowledge, quality checklist, task context, output path
4. **Knowledge levels are enforced:** Each agent receives only its authorized knowledge level per the access matrix
5. **Knowledge read/write works:** Knowledge can be read at correct levels and written with freshness markers
6. **Freshness tracking works:** Entries can be categorized as fresh/aging/stale based on task distance
7. **Archival rotation works:** Old entries move to archive/ when threshold exceeded, summary stays current
8. **Consistency validation works:** Contradictions between new and existing knowledge are detected
9. **Dispatch uses instruction files:** Post-planning agents are dispatched with pre-assembled instruction files
10. **Pre-planning agents still work:** Apollo, Hermes, Athena use simplified assembly correctly
11. **Quick pipeline unaffected:** Quick pipeline still uses simplified assembly throughout
12. **E8 freshness warning works:** Stale knowledge detected at pipeline start, warning displayed
13. **Tier 1 tests pass:** All structural verification tests pass (existing + new Phase 4 tests)
14. **Constitutional compliance:** All invariants satisfied

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Orchestrator reads instruction files, does not assemble them (Daedalus does)
[✓] 1.2 — Each agent's instruction file contains only its authorized knowledge (enforced by access matrix)
[✓] 1.3 — Rule assembly (lib), knowledge system (lib), instruction generation (Daedalus) are separate

ARTICLE 2: Determinism
[✓] 2.1 — Pipeline selection unchanged (Phase 3)
[✓] 2.2 — Gate structure unchanged (Phase 3)
[✓] 2.3 — Conflict detection is deterministic (higher layer wins, inviolable never overridden)

ARTICLE 3: Transparency
[✓] 3.1 — Instruction files written to state/tasks/{id}/instructions/ (visible, traceable)
[✓] 3.2 — Conflict report included in Daedalus artifacts (visible at plan gate)
[✓] 3.3 — E8 stale knowledge warning displayed to user

ARTICLE 4: Safety
[✓] 4.1 — Inviolable rules preserved in every assembled instruction (cannot be overridden by L2-L4)
[✓] 4.2 — Gates unchanged (Phase 3)
[✓] 4.3 — Git-backed reversibility unchanged
[✓] 4.4 — Bypass unchanged

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — Knowledge entries include evidence references (structural check in Tier 1 tests)
[✓] 5.2 — N/A (rule change threshold is Reflector concern, Phase 10)
[✓] 5.3 — Consistency validation runs before knowledge write

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation
[✓] 6.3 — Tier 1 tests validate rule assembly and knowledge system invariants
```
