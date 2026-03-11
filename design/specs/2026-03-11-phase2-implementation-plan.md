# Phase 2: Core Agent Definitions — Implementation Plan

**Goal:** All 10 agents have working prompt definitions with NEVER constraints, quality checklists, knowledge access matrix, and response contract enforcement.

**Spec:** `design/specs/2026-03-11-phase2-agent-definitions.md`

**Key design docs:**
- `design/architecture/agents.md` — agent definitions, budgets, contracts
- `design/architecture/rules.md` — Layer 1/2 structure, base rules, role examples
- `design/architecture/naming.md` — mythological names
- `design/subsystems/quality.md` — Q1-Q5 checklists
- `design/CONSTITUTION.md` — Art 1.2, Art 2.3, Art 4.1

---

## Chunk 0: Support Files

### Task 0.1: Create response-contract.yaml

**File:** `src/global/core/response-contract.yaml`

Canonical definition of the agent response format, referenced by all role files.

```yaml
_meta:
  name: response-contract
  description: Canonical agent response format

format: |
  STATUS: success|failure|blocked|budget_exceeded
  SUMMARY: <1-2 sentences, factual>
  ARTIFACTS: [<list of file paths written>]
  NEXT: <recommended next pipeline step>

rules:
  - "Return ONLY this format to orchestrator — nothing else"
  - "All detailed output goes to state files, never in return message"
  - "SUMMARY must be factual — no opinions, no recommendations beyond NEXT"
  - "ARTIFACTS must list every file written during this step"

statuses:
  success: "Step completed, artifacts written"
  failure: "Step failed after retries, see artifacts for details"
  blocked: "Cannot proceed — missing information or unclear instructions"
  budget_exceeded: "Approaching context limit, checkpoint recommended"
```

- [ ] Write response-contract.yaml
- [ ] Commit: `moira(agents): add canonical response contract definition`

### Task 0.2: Create knowledge-access-matrix.yaml

**File:** `src/global/core/knowledge-access-matrix.yaml`

Consolidated matrix — single source of truth for which agent gets which knowledge level.

Source: agents.md "Knowledge access" lines per agent.

```yaml
_meta:
  name: knowledge-access-matrix
  description: Agent knowledge access levels (L0=index, L1=summary, L2=full)

# Levels: L0 (~100-200 tokens), L1 (~500-2k), L2 (~2-10k)
# null = no access to this knowledge type

matrix:
  apollo:      { project_model: L1, conventions: null, decisions: null,  patterns: null }
  hermes:      { project_model: L0, conventions: null, decisions: null,  patterns: null }
  athena:      { project_model: L1, conventions: null, decisions: L0,    patterns: null }
  metis:       { project_model: L1, conventions: L0,   decisions: L2,    patterns: L1   }
  daedalus:    { project_model: L1, conventions: L1,   decisions: L0,    patterns: L0   }
  hephaestus:  { project_model: L0, conventions: L2,   decisions: null,  patterns: L1   }
  themis:      { project_model: L1, conventions: L2,   decisions: L1,    patterns: L1   }
  aletheia:    { project_model: L0, conventions: L1,   decisions: null,  patterns: L0   }
  mnemosyne:   { project_model: L2, conventions: L2,   decisions: L2,    patterns: L2   }
  argus:       { project_model: L2, conventions: L2,   decisions: L2,    patterns: L2   }
```

- [ ] Write knowledge-access-matrix.yaml
- [ ] Verify each row matches agents.md "Knowledge access" line
- [ ] Commit: `moira(agents): add knowledge access matrix`

---

## Chunk 1: Layer 1 — Base Rules

### Task 1.1: Create base.yaml

**File:** `src/global/core/rules/base.yaml`

Source: `design/architecture/rules.md` Layer 1 section.

Structure:
```yaml
_meta:
  name: base
  layer: 1
  description: Universal rules for ALL agents in ALL projects
  applies_to: all

inviolable:
  - id: INV-001
    rule: "Never fabricate API endpoints, URLs, schemas, or data structures"
    constitution: "Art 4.1"
  - id: INV-002
    rule: "Never proceed when information is insufficient — stop and report STATUS: blocked"
    constitution: "Art 2.3"
  - id: INV-003
    rule: "Never suppress or ignore errors"
    constitution: "Art 3.3"
  - id: INV-004
    rule: "Write all detailed output to state files, return only status summary to orchestrator"
    constitution: "Art 3.1"
  - id: INV-005
    rule: "Never guess types, return formats, or data structures"
    constitution: "Art 4.1"
  - id: INV-006
    rule: "Never commit secrets or credentials"
    constitution: "Art 4.1"
  - id: INV-007
    rule: "Never modify files outside stated scope"
    constitution: "Art 1.2"

overridable:
  file_output_format: markdown
  max_function_length: 50
  naming_convention: camelCase
  test_framework: jest
  indent: "2 spaces"
```

Each inviolable rule gets an `id` and `constitution` reference for traceability (Art 3.1).

- [ ] Write base.yaml with all 7 inviolable rules
- [ ] Write overridable defaults
- [ ] Verify each inviolable maps to a Constitutional article
- [ ] Commit: `moira(agents): add Layer 1 base rules`

---

## Chunk 2: Layer 2 — Role Rules (10 agents)

Each role file follows the structure from the spec. Every field is mandatory for structural verification.

### Task 2.1: apollo.yaml (Classifier)

**File:** `src/global/core/rules/roles/apollo.yaml`

Source: agents.md Classifier section.

Key points:
- Purpose: determines task size and pipeline type
- Does NOT read project source code
- Classification is a pure function (Art 2.1)
- Pipeline mapping: small+high→quick, small+low→standard, medium→standard, large→full, epic→decomposition
- Budget: 20k
- Knowledge: project_model=L1 only
- Quality checklist: null (no Q gate for classification)

Never constraints:
- Never read project source code
- Never propose solutions or architecture
- Never change the task description
- Never skip classification

- [ ] Write apollo.yaml
- [ ] Commit with chunk (see Task 2.11)

### Task 2.2: hermes.yaml (Explorer)

**File:** `src/global/core/rules/roles/hermes.yaml`

Source: agents.md Explorer section.

Key points:
- Purpose: reads project source code, reports facts
- Scans breadth-first, then depth
- Always checks shared/, utils/, types/, config/
- Documents what was found AND what was looked for but not found
- Budget: 140k
- Knowledge: project_model=L0 (must be unbiased)
- Quality checklist: null

Never constraints:
- Never propose solutions or recommendations
- Never express opinions
- Never make architectural suggestions
- Never modify any files

- [ ] Write hermes.yaml

### Task 2.3: athena.yaml (Analyst)

**File:** `src/global/core/rules/roles/athena.yaml`

Source: agents.md Analyst section.

Key points:
- Purpose: formalizes requirements, identifies edge cases
- Must complete Q1 checklist
- Missing items → STATUS: blocked with specific questions
- Budget: 80k (note: agents.md says 80k, config schema default says 60k — use agents.md as source of truth)
- Knowledge: project_model=L1, decisions=L0

Never constraints:
- Never propose technical implementation
- Never suggest specific technologies or patterns
- Never write code or pseudocode
- Never assume requirements — ask if unclear

- [ ] Write athena.yaml

### Task 2.4: metis.yaml (Architect)

**File:** `src/global/core/rules/roles/metis.yaml`

Source: agents.md Architect section.

Key points:
- Purpose: makes technical decisions, chooses approaches
- Every decision: CONTEXT, DECISION, ALTERNATIVES REJECTED, REASONING
- Must pass Q2 checklist
- Checks quality-map for existing patterns
- Defines contract interfaces for parallel batches
- Budget: 100k
- Knowledge: project_model=L1, conventions=L0, decisions=L2, patterns=L1

Never constraints:
- Never write implementation code
- Never decompose into tasks (that's Planner)
- Never make requirements decisions (that's Analyst)
- Never assume API contracts — verify or STATUS: blocked

- [ ] Write metis.yaml

### Task 2.5: daedalus.yaml (Planner)

**File:** `src/global/core/rules/roles/daedalus.yaml`

Source: agents.md Planner section.

Key points:
- Purpose: decomposes architecture into execution steps
- Must pass Q3 checklist
- Creates dependency graph, clusters into batches
- Estimates context budget per batch
- Assembles Layer 1-4 rules for each agent invocation
- Allocates MCP tools per step
- Budget: 70k (note: agents.md says 70k, config default says 80k — use agents.md)
- Knowledge: project_model=L1, conventions=L1, decisions=L0, patterns=L0

Never constraints:
- Never make architectural decisions
- Never choose between technical alternatives
- Never write implementation code
- Never skip dependency analysis

- [ ] Write daedalus.yaml

### Task 2.6: hephaestus.yaml (Implementer)

**File:** `src/global/core/rules/roles/hephaestus.yaml`

Source: agents.md Implementer section.

Key points:
- Purpose: writes code per plan, follows exactly
- Implements EXACTLY what plan specifies (no more, no less)
- If plan unclear → STATUS: blocked
- Uses only authorized MCP tools
- Budget: 120k (note: agents.md says 120k, config default says 140k — use agents.md)
- Knowledge: project_model=L0, conventions=L2, patterns=L1

Never constraints:
- Never make decisions about WHAT to build
- Never add features not in the plan
- Never refactor code outside plan scope
- Never add comments/docstrings/annotations to unchanged code
- Never fabricate API endpoints, URLs, schemas, data structures
- Never guess types or return formats

- [ ] Write hephaestus.yaml

### Task 2.7: themis.yaml (Reviewer)

**File:** `src/global/core/rules/roles/themis.yaml`

Source: agents.md Reviewer section.

Key points:
- Purpose: checks code quality against standards and requirements
- Must complete Q4 checklist
- Severity: CRITICAL (blocks), WARNING (can proceed with approval), SUGGESTION (logged)
- Checks conformance with quality-map
- False positive awareness: if unsure, WARNING not CRITICAL
- Budget: 100k (agents.md says 100k, config default says 80k — use agents.md)
- Knowledge: project_model=L1, conventions=L2, decisions=L1, patterns=L1

Never constraints:
- Never fix code — only identify issues
- Never modify project files
- Never suppress findings
- Never auto-approve (all findings must be reported)

- [ ] Write themis.yaml

### Task 2.8: aletheia.yaml (Tester)

**File:** `src/global/core/rules/roles/aletheia.yaml`

Source: agents.md Tester section.

Key points:
- Purpose: writes and runs tests
- Must complete Q5 checklist
- If test fails due to implementation bug → reports, doesn't fix
- Budget: 90k (agents.md says 90k, config default says 100k — use agents.md)
- Knowledge: project_model=L0, conventions=L1, patterns=L0

Never constraints:
- Never modify application code
- Never skip running tests after writing them
- Never write brittle tests (testing implementation details)
- Never ignore test failures

- [ ] Write aletheia.yaml

### Task 2.9: mnemosyne.yaml (Reflector)

**File:** `src/global/core/rules/roles/mnemosyne.yaml`

Source: agents.md Reflector section.

Key points:
- Purpose: analyzes completed tasks for learning
- Runs AFTER task completion (non-blocking, background)
- Analyzes 6 dimensions: accuracy, efficiency, predictions, architecture, gaps, orchestrator
- Proposes rule changes only after 3+ confirming observations (Art 5.2)
- Budget: 80k (agents.md says 80k, config default says 60k — use agents.md)
- Knowledge: full access (all L2)

Never constraints:
- Never change rules directly
- Never propose rule changes with fewer than 3 observations
- Never block the pipeline (runs post-completion)
- Never modify project or system files

- [ ] Write mnemosyne.yaml

### Task 2.10: argus.yaml (Auditor)

**File:** `src/global/core/rules/roles/argus.yaml`

Source: agents.md Auditor section.

Key points:
- Purpose: independent system health verification
- Not part of task execution pipeline
- READ-ONLY
- 5 audit domains: rules, knowledge, agents, config, cross-consistency
- Can read project files to verify knowledge accuracy
- Budget: 140k (agents.md says 140k, config default says 60k — use agents.md)
- Knowledge: full access (all L2, read-only)

Never constraints:
- Never modify moira system files
- Never modify project files
- Never make changes — only report findings
- Never suppress audit findings

- [ ] Write argus.yaml

### Task 2.11: Commit all role files

- [ ] Verify all 10 files exist and have consistent structure
- [ ] Commit: `moira(agents): add all 10 agent role definitions`

---

## Chunk 3: Quality Checklists

### Task 3.1: q1-completeness.yaml (Analyst gate)

**File:** `src/global/core/rules/quality/q1-completeness.yaml`

Source: quality.md Q1 section.

```yaml
_meta:
  name: q1-completeness
  gate: Q1
  description: Requirements Completeness
  agent: athena
  pipeline_step: analysis

items:
  - id: Q1-01
    check: "Happy path clearly defined"
    required: true
  - id: Q1-02
    check: "Error cases enumerated"
    required: true
  # ... (all 8 items from quality.md)

on_missing: "STATUS: blocked — ask user for missing requirements"
```

- [ ] Write q1-completeness.yaml

### Task 3.2: q2-soundness.yaml (Architect gate)

**File:** `src/global/core/rules/quality/q2-soundness.yaml`

Source: quality.md Q2 section. 9 items.

- [ ] Write q2-soundness.yaml

### Task 3.3: q3-feasibility.yaml (Planner gate)

**File:** `src/global/core/rules/quality/q3-feasibility.yaml`

Source: quality.md Q3 section. 6 items.

- [ ] Write q3-feasibility.yaml

### Task 3.4: q4-correctness.yaml (Reviewer gate)

**File:** `src/global/core/rules/quality/q4-correctness.yaml`

Source: quality.md Q4 section. 6 sub-sections: Correctness (4), Standards (4), Performance (5), Security (5), Integration (4), Project Conventions (4). Total: 26 items.

- [ ] Write q4-correctness.yaml

### Task 3.5: q5-coverage.yaml (Tester gate)

**File:** `src/global/core/rules/quality/q5-coverage.yaml`

Source: quality.md Q5 section. 7 items.

- [ ] Write q5-coverage.yaml

### Task 3.6: Commit quality checklists

- [ ] Verify all 5 files exist and reference correct agents
- [ ] Commit: `moira(agents): add Q1-Q5 quality gate checklists`

---

## Chunk 4: Install.sh Update

### Task 4.1: Update install.sh to copy new files

**File:** `src/install.sh`

Add to `install_global()`:
- Copy `core/rules/base.yaml` → `$MOIRA_HOME/core/rules/`
- Copy `core/knowledge-access-matrix.yaml` → `$MOIRA_HOME/core/`
- Copy `core/response-contract.yaml` → `$MOIRA_HOME/core/`

Existing lines already handle:
- `core/rules/roles/*` → `$MOIRA_HOME/core/rules/roles/`
- `core/rules/quality/*` → `$MOIRA_HOME/core/rules/quality/`

Add to `verify()`:
- Check base.yaml exists at `$MOIRA_HOME/core/rules/base.yaml`
- Check 10 role files exist in `$MOIRA_HOME/core/rules/roles/`
- Check 5 quality files exist in `$MOIRA_HOME/core/rules/quality/`
- Check knowledge-access-matrix.yaml and response-contract.yaml exist

- [ ] Update install_global() with new copy targets
- [ ] Update verify() with Phase 2 checks
- [ ] Test: run install.sh, verify files copied
- [ ] Commit: `moira(agents): update install.sh for Phase 2 artifacts`

---

## Chunk 5: Tier 1 Tests

### Task 5.1: Create test-agent-definitions.sh

**File:** `src/tests/tier1/test-agent-definitions.sh`

Tests (source test-helpers.sh, run against installed $MOIRA_HOME):

**Structural tests:**
- base.yaml exists and has `inviolable:` section
- base.yaml has all 7 inviolable rules (count `- id: INV-` entries)
- All 10 role files exist in core/rules/roles/
- Each role file has `_meta.role:` field
- Each role file has `never:` section with at least 1 entry
- Each role file has `knowledge_access:` section
- Each role file has `_meta.budget:` field
- Each role file has `identity:` field
- Each role file has `capabilities:` section
- Each role file has `response_format:` or references response-contract.yaml

**Constitutional compliance (Art 1.2):**
- Each agent's `never:` contains at least 3 constraints
- Explorer (hermes) never section contains "propose" or "solution" or "recommend"
- Implementer (hephaestus) never section contains "decision" or "feature"
- Reviewer (themis) never section contains "fix" or "modify"
- Reflector (mnemosyne) never section contains "change rules directly"

**Knowledge access matrix:**
- knowledge-access-matrix.yaml exists
- Matrix has entries for all 10 agents
- Each role file's knowledge_access matches the matrix row

**Quality checklists:**
- All 5 Q files exist
- Each Q file has `_meta.agent:` field
- Each Q file has `items:` section

**Response contract:**
- response-contract.yaml exists
- Contains all 4 status values: success, failure, blocked, budget_exceeded

- [ ] Write all structural tests
- [ ] Write constitutional compliance tests
- [ ] Write matrix consistency tests
- [ ] Write quality checklist tests
- [ ] Run and verify all pass
- [ ] Commit: `moira(agents): add Tier 1 agent definition tests`

---

## Chunk 6: Design Doc Updates & Final Verification

### Task 6.1: Update config.schema.yaml budgets

The config.schema.yaml budget defaults (from Phase 1) don't match agents.md authoritative values. Fix:

| Agent | config.schema.yaml | agents.md (correct) |
|-------|-------------------|---------------------|
| analyst | 60000 | 80000 |
| planner | 80000 | 70000 |
| implementer | 140000 | 120000 |
| reviewer | 80000 | 100000 |
| tester | 100000 | 90000 |
| reflector | 60000 | 80000 |
| auditor | 60000 | 140000 |

- [ ] Update config.schema.yaml with correct budget defaults
- [ ] Commit: `moira(foundation): fix agent budget defaults to match agents.md`

### Task 6.2: Run full Tier 1 suite

- [ ] Run `src/tests/tier1/run-all.sh`
- [ ] All tests pass (Phase 1 + Phase 2)
- [ ] Fix any failures

### Task 6.3: Constitutional compliance check

- [ ] Art 1.2: every agent has explicit NEVER constraints — verified by tests
- [ ] Art 2.3: base.yaml contains anti-assumption directive (INV-002) — verified
- [ ] Art 4.1: base.yaml contains anti-fabrication rule (INV-001) — verified
- [ ] Art 1.3: no component handles multiple responsibilities — role files are single-agent
- [ ] Art 3.1: response contract requires ARTIFACTS list — verified

### Task 6.4: Verify success criteria from spec

- [ ] All 10 agent role files exist with required structure
- [ ] base.yaml has all 7 inviolable rules
- [ ] Knowledge access matrix is consistent across agents and matrix file
- [ ] All 5 quality checklists defined
- [ ] Response contract defined
- [ ] install.sh copies all Phase 2 files
- [ ] Tier 1 tests cover all structural requirements

### Task 6.5: Final commit

- [ ] Commit: `moira(agents): complete Phase 2 — core agent definitions`

---

## Dependency Graph

```
Chunk 0 (support files: contract + matrix)
    ↓
Chunk 1 (base.yaml) — no dep on Chunk 0 but logical ordering
    ↓
Chunk 2 (10 role files) — reference base.yaml structure + contract + matrix
    ↓
Chunk 3 (quality checklists) — referenced by role files
    ↓
Chunk 4 (install.sh update) — needs all files to exist
    ↓
Chunk 5 (tests) — needs installed files
    ↓
Chunk 6 (verification) — needs tests passing
```

Chunks 0, 1, 3 can be parallelized (no interdependency). Chunk 2 depends on 0+1 for structural consistency. Chunks 4-6 are sequential.
