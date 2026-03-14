# Phase 2: Core Agent Definitions — Spec

## Goal

All 10 agents have working prompt definitions with strict role boundaries, NEVER constraints, quality checklists, and knowledge access levels.

## Deliverables

### Layer 1: Base Rules
- `src/global/core/rules/base.yaml` — universal rules for ALL agents
  - Inviolable rules (cannot be overridden by any layer)
  - Overridable defaults (Layer 3/4 can override)

### Layer 2: Role Rules (10 files)
Each file in `src/global/core/rules/roles/`:
- `apollo.yaml` — Classifier
- `hermes.yaml` — Explorer
- `athena.yaml` — Analyst
- `metis.yaml` — Architect
- `daedalus.yaml` — Planner
- `hephaestus.yaml` — Implementer
- `themis.yaml` — Reviewer
- `aletheia.yaml` — Tester
- `mnemosyne.yaml` — Reflector
- `argus.yaml` — Auditor

#### Role file structure:
```yaml
_meta:
  name: <mythological_name>
  role: <functional_role>
  purpose: <one sentence>
  budget: <max tokens>

identity: |
  <agent identity statement>

capabilities:
  - <what agent CAN do>

never:
  - <NEVER constraints per Art 1.2>

knowledge_access:
  project_model: L0|L1|L2
  conventions: L0|L1|L2
  decisions: L0|L1|L2
  patterns: L0|L1|L2

quality_checklist: <Q file reference or null>

response_format: |
  STATUS: success|failure|blocked|budget_exceeded
  SUMMARY: <1-2 sentences>
  ARTIFACTS: [<file paths>]
  NEXT: <recommended next step>
```

### Quality Checklists (5 files)
Each in `src/global/core/rules/quality/`:
- `q1-completeness.yaml` — Requirements (Analyst)
- `q2-soundness.yaml` — Architecture (Architect)
- `q3-feasibility.yaml` — Plan (Planner)
- `q4-correctness.yaml` — Code (Reviewer)
- `q5-coverage.yaml` — Tests (Tester)

### Support Files
- `src/global/core/knowledge-access-matrix.yaml` — consolidated L0/L1/L2 matrix
- `src/global/core/response-contract.yaml` — canonical response format definition

### Tier 1 Tests
- `src/tests/tier1/test-agent-definitions.sh` — structural verification:
  - Every role file has `never:` section with ≥1 entry
  - Every role file has `knowledge_access:` section
  - Every role file has `_meta.role:` field
  - Knowledge access matrix is consistent with role files
  - All 10 agents defined

### Install.sh Update
- Copy `core/rules/base.yaml` to `$MOIRA_HOME/core/rules/`
- Copy `core/rules/roles/*.yaml` to `$MOIRA_HOME/core/rules/roles/`
- Copy `core/rules/quality/*.yaml` to `$MOIRA_HOME/core/rules/quality/`
- Copy `core/knowledge-access-matrix.yaml` and `core/response-contract.yaml`

## Design Sources
- `design/architecture/agents.md` — agent definitions, budgets, response contract
- `design/architecture/rules.md` — 4-layer system, base rules, role rules
- `design/subsystems/quality.md` — Q1-Q5 checklists
- `design/architecture/naming.md` — mythological names
- `design/CONSTITUTION.md` — Art 1.2 (NEVER constraints), Art 2.3 (anti-assumption)
