# Self-Protection System — Immune System for Moira

## Problem

Moira is developed iteratively. Each session with Claude adds, modifies, or refactors parts of the system. Without protection:

1. A "small improvement" can break a core invariant
2. Agent prompt changes can subtly weaken quality guarantees
3. New features can contradict existing design decisions
4. Accumulated micro-changes can drift the system away from its principles
5. A well-intentioned refactor can remove a safety mechanism

## Solution: Three-Layer Defense

```
┌─────────────────────────────────────────────┐
│  LAYER 3: Constitutional Verifier           │
│  Checks inviolable invariants               │
│  BLOCKS changes that violate constitution   │
├─────────────────────────────────────────────┤
│  LAYER 2: Design Conformance Checker        │
│  Checks changes against design documents    │
│  WARNS on deviations, requires justification│
├─────────────────────────────────────────────┤
│  LAYER 1: Regression Detection              │
│  Checks that existing capabilities still    │
│  work after changes                         │
└─────────────────────────────────────────────┘
```

---

## Layer 1: Regression Detection

### What it checks

After any change to Moira system files, verify that existing functionality still works:

```
REGRESSION CHECKS:
├─ File structure integrity
│   All required directories exist?
│   All required files present?
│   No files deleted that are referenced by other files?
│
├─ Cross-reference integrity
│   All file references in SYSTEM-DESIGN.md point to existing files?
│   All agent names in pipeline definitions match agent definition files?
│   All rule references in assembly logic point to existing rule files?
│
├─ Pipeline completeness
│   Quick pipeline still has all required steps?
│   Standard pipeline still has all required steps?
│   Full pipeline still has all required steps?
│   Decomposition pipeline still has all required steps?
│   Analytical pipeline still has all required steps?
│
├─ Agent completeness
│   All agents defined in agents.md are present in role files?
│   (currently 11: Apollo, Hermes, Athena, Metis, Daedalus, Hephaestus, Themis, Aletheia, Mnemosyne, Argus, Calliope)
│   Each agent still has: identity, capabilities, constraints, output contract?
│   No agent lost its "NEVER" constraints?
│
├─ Rule completeness
│   base.yaml still has all inviolable rules?
│   All role files still exist?
│   Quality criteria files still complete?
│
└─ Knowledge structure
    All knowledge directories still exist?
    Three-level structure (index/summary/full) maintained?
```

### How it runs

Regression checks are implemented as a verification script that:
1. Reads the expected structure from design docs
2. Compares against actual file state
3. Reports any deviations

```bash
# Conceptual — actual implementation will be more sophisticated
moira-verify regression
```

### When it runs

- Before every commit to the moira repo
- After every implementation session
- Can be triggered manually

---

## Layer 2: Design Conformance Checker

### What it checks

Every proposed change is analyzed against design documents to detect contradictions:

```
CONFORMANCE CHECKS:

1. ARCHITECTURAL ALIGNMENT
   Does the change respect the three-layer architecture?
   Does it maintain separation between Global/Project/Execution layers?

2. AGENT BOUNDARY RESPECT
   Does the change keep agents within their defined responsibilities?
   Does it maintain the agent response contract?

3. PIPELINE INTEGRITY
   Does the change preserve deterministic pipeline flow?
   Does it maintain all required gates?
   Does it maintain error handling at each step?

4. RULE SYSTEM INTEGRITY
   Does the change respect the 4-layer rule hierarchy?
   Does it maintain inviolable vs overridable distinction?
   Does it preserve rule assembly process?

5. KNOWLEDGE SYSTEM INTEGRITY
   Does the change maintain 3-level knowledge structure?
   Does it preserve agent knowledge access matrix?
   Does it maintain freshness system?

6. DECISION CONSISTENCY
   Does the change contradict any decision in the Decision Log?
   If it MUST contradict — is the Decision Log being updated with reasoning?
```

### Process for changes that deviate from design

```
PROPOSED CHANGE conflicts with design document.

Is this intentional?
├─ NO → Reject change, fix to conform to design
└─ YES → This requires:
    1. Update design document FIRST
    2. Document WHY the design changed (in Decision Log)
    3. Verify no constitutional violations
    4. Get user approval for design change
    5. THEN implement the code change

ORDER MATTERS:
  WRONG: Change code → update docs later → maybe
  RIGHT: Update design → approve → change code → verify
```

### Impact Analysis

Before any change, the checker produces an impact analysis:

```
═══════════════════════════════════════════
  CHANGE IMPACT ANALYSIS
═══════════════════════════════════════════

  Proposed: Modify implementer agent to also run linter

  Impact:
  ├─ ARTICLE 1.2 VIOLATION ❌
  │   Implementer's role is "write code per plan"
  │   Running linter is Reviewer's responsibility
  │   This merges two responsibilities
  │
  ├─ Design doc conflict:
  │   agents.md defines Implementer as code-only
  │   agents.md defines Reviewer as quality checker
  │
  └─ Recommendation: REJECT
      If linting is needed post-implementation,
      add it to Reviewer's checklist instead.

═══════════════════════════════════════════
```

Or for a valid change:

```
═══════════════════════════════════════════
  CHANGE IMPACT ANALYSIS
═══════════════════════════════════════════

  Proposed: Add timeout handling to agent dispatch

  Impact:
  ├─ No constitutional violations ✅
  ├─ Aligns with fault-tolerance.md (E6-AGENT) ✅
  ├─ No design doc conflicts ✅
  ├─ Enhances existing error handling ✅
  │
  └─ Recommendation: APPROVE
      This extends the E6 recovery path without
      changing any architectural boundaries.

═══════════════════════════════════════════
```

---

## Layer 3: Constitutional Verifier

### What it checks

The 19 invariants from CONSTITUTION.md. These are binary — pass or fail, no gray area.

### Verification implementation

Each constitutional article maps to concrete checks:

Constitutional verification checklist defined in `design/CONSTITUTION.md` (Invariant Verification Checklist section).

```yaml
# Constitutional checks (conceptual schema)

article_1_1:
  name: "Orchestrator Purity"
  check_type: "pattern_absence"
  target: "src/global/skills/orchestrator.md"
  forbidden_patterns:
    - "Read tool" targeting non-.moira/ paths
    - "Write tool" targeting non-.moira/ paths
    - "Edit tool" targeting non-.moira/ paths
    - "Grep tool"
    - "Glob tool"
    - "Bash tool" for non-agent operations
  severity: "CONSTITUTIONAL_VIOLATION"

article_1_2:
  name: "Agent Single Responsibility"
  check_type: "constraint_presence"
  targets: "src/global/core/rules/roles/*.yaml"
  required_patterns:
    - Each file contains "NEVER" constraints matching its role boundaries
    - Explorer contains "NEVER proposes solutions"
    - Analyst contains "NEVER proposes technical implementation"
    - Architect contains "NEVER writes code"
    - Planner contains "NEVER makes architectural decisions"
    - Implementer contains "NEVER makes decisions about WHAT"
    - Reviewer contains "NEVER fixes code"
    - Tester contains "NEVER modifies application code"
    - Reflector contains "NEVER changes rules directly"
    - Auditor contains "NEVER modifies system files"
    - Calliope contains "NEVER source code" (writes only markdown)
  severity: "CONSTITUTIONAL_VIOLATION"

article_2_2:
  name: "Gate Determinism"
  check_type: "structure_verification"
  target: "src/global/skills/orchestrator.md"
  required:
    quick_pipeline_gates: ["classification", "final"]
    standard_pipeline_gates: ["classification", "architecture", "plan", "final"]
    full_pipeline_gates: ["classification", "architecture", "plan", "phase", "final"]
    decomposition_gates: ["classification", "architecture", "decomposition", "per_task", "final"]
    analytical_gates: ["classification", "scope", "depth_checkpoint", "final"]
    # Analytical pipeline depth_checkpoint may repeat (progressive depth) but never skip.
  # Gate names here are short identifiers; YAML implementations use `_gate` suffix
  # (e.g., 'classification' → `classification_gate`).
  severity: "CONSTITUTIONAL_VIOLATION"

article_4_1:
  name: "No Fabrication"
  check_type: "rule_presence"
  target: "src/global/core/rules/base.yaml"
  required_in_inviolable:
    - Pattern matching "Never fabricate" or "Never guess" for APIs/URLs/schemas
  severity: "CONSTITUTIONAL_VIOLATION"

article_4_4:
  name: "Escape Hatch Integrity"
  check_type: "logic_verification"
  target: "src/global/skills/orchestrator.md"
  required:
    - Bypass activates ONLY on "/moira bypass:" prefix
    - Confirmation accepts ONLY "2"
    - No alternative activation paths
  severity: "CONSTITUTIONAL_VIOLATION"

article_6_1:
  name: "Constitutional Immutability"
  check_type: "write_scope"
  protected_files:
    - "design/CONSTITUTION.md"
  no_code_path_may_write: true
  severity: "CONSTITUTIONAL_VIOLATION"
```

### Verification result

```
═══════════════════════════════════════════
  CONSTITUTIONAL VERIFICATION
═══════════════════════════════════════════

  Article 1: Separation of Concerns
  ├─ 1.1 Orchestrator Purity ✅
  ├─ 1.2 Agent Single Responsibility ✅
  └─ 1.3 No God Components ✅

  Article 2: Determinism
  ├─ 2.1 Pipeline Determinism ✅
  ├─ 2.2 Gate Determinism ✅
  └─ 2.3 No Implicit Decisions ✅

  Article 3: Transparency
  ├─ 3.1 Decision Traceability ✅
  ├─ 3.2 Budget Visibility ✅
  └─ 3.3 Error Transparency ✅

  Article 4: Safety
  ├─ 4.1 No Fabrication ✅
  ├─ 4.2 User Authority ✅
  ├─ 4.3 Rollback Capability ✅
  └─ 4.4 Escape Hatch Integrity ✅

  Article 5: Knowledge Integrity
  ├─ 5.1 Evidence-Based Knowledge ✅
  ├─ 5.2 Rule Change Threshold ✅
  └─ 5.3 Knowledge Consistency ✅

  Article 6: Self-Protection
  ├─ 6.1 Constitutional Immutability ✅
  ├─ 6.2 Design Document Authority ✅
  └─ 6.3 Invariant Verification ✅

  RESULT: ALL CHECKS PASSED ✅
  Change may proceed.
═══════════════════════════════════════════
```

Or when a violation is found:

```
═══════════════════════════════════════════
  CONSTITUTIONAL VERIFICATION
═══════════════════════════════════════════

  ...
  Article 2: Determinism
  ├─ 2.1 Pipeline Determinism ✅
  ├─ 2.2 Gate Determinism ❌ VIOLATION
  │   Standard Pipeline missing "architecture" gate.
  │   Gate was removed in latest change.
  │   This CANNOT proceed.
  └─ 2.3 No Implicit Decisions ✅
  ...

  RESULT: BLOCKED ❌
  1 constitutional violation found.
  Change MUST NOT be committed until violation is resolved.

  To resolve:
  ▸ If gate removal was accidental → restore the gate
  ▸ If gate removal is intentional → this requires
    Constitutional amendment (user must edit CONSTITUTION.md
    directly with documented reasoning)
═══════════════════════════════════════════
```

---

## Development Session Protocol

Every session working on Moira follows this protocol:

### Session Start

```
1. Read CONSTITUTION.md — refresh invariants
2. Read relevant design documents for the task
3. Read Decision Log — understand precedents
4. Read CLAUDE.md — understand development rules
5. Check current state: what's implemented, what's the change target
```

### Before Making Changes

```
1. IMPACT ANALYSIS: What will this change affect?
   - Which design documents are relevant?
   - Which constitutional articles could be affected?
   - Which existing components depend on what's being changed?

2. DESIGN-FIRST CHECK:
   - Does the implementation match design docs?
   - If not, update design docs FIRST (with user approval)

3. SCOPE CHECK:
   - Is the change scoped to what was requested?
   - No "while I'm here, let me also..." additions
   - No "this would be better if..." improvements outside scope
```

### After Making Changes

```
1. REGRESSION CHECK: Does everything that worked before still work?
2. CONFORMANCE CHECK: Does implementation match design docs?
3. CONSTITUTIONAL CHECK: Are all invariants still satisfied?
4. DECISION LOG: Was any new decision made? Document it.
```

### Session End

```
1. Summary of what was changed and why
2. Verification results (all three layers)
3. Updated state: what's implemented now, what's next
4. Any new questions or issues discovered
```

---

## Anti-Degradation Patterns

### Pattern 1: Scope Creep Prevention

```
RULE: Each development session has ONE goal.
      Changes outside that goal are noted but NOT implemented.

EXAMPLE:
  Goal: Implement Planner agent prompt
  During work, notice: "Explorer prompt could be improved"

  WRONG: Improve Explorer prompt now
  RIGHT: Note "Explorer prompt improvement" for future session
```

### Pattern 2: Additive Over Modifying

```
RULE: Prefer adding new capabilities over modifying existing ones.
      When modification is necessary, ensure the OLD behavior
      is still achievable.

EXAMPLE:
  Need: Add support for monorepo projects

  WRONG: Rewrite project scanner to handle monorepos
         (may break single-repo scanning)
  RIGHT: Add monorepo detection as new path alongside
         existing single-repo path
```

### Pattern 3: Evidence Before Evolution

```
RULE: Don't "improve" something that hasn't been proven to need
      improvement through actual use.

EXAMPLE:
  Thought: "The 3-level knowledge system might work better with 4 levels"

  WRONG: Add a 4th level because it seems logical
  RIGHT: Use the 3-level system. If it proves insufficient
         in practice (with evidence), THEN consider changes.
```

### Pattern 4: Backward Compatibility in Design Changes

```
RULE: When a design document is updated, all existing
      implementations that depend on the old design
      must be updated in the same session.

EXAMPLE:
  Change: Update agent response contract format

  WRONG: Update contract definition, leave agents unchanged
  RIGHT: Update contract + update ALL agent prompts that
         reference the contract in the same change
```

### Pattern 5: No Orphaned Components

```
RULE: When removing or replacing a component, verify that
      nothing else references it. No dead code, no broken links.

CHECK:
  - Grep for references to removed component
  - Update all references
  - Remove or redirect documentation links
```

---

## Dangerous Change Categories

Changes in these categories require extra scrutiny:

### RED — Constitutional implications
- Modifying pipeline gate structure
- Changing agent role boundaries
- Altering orchestrator restrictions
- Modifying inviolable rules
- Changing bypass mechanism

→ **Requires**: Constitutional verification + user approval

### ORANGE — Design implications
- Adding new agent types
- Modifying pipeline flow
- Changing knowledge structure
- Altering budget allocations
- Modifying quality checklists

→ **Requires**: Design doc update + conformance check

### YELLOW — Behavioral implications
- Changing agent prompt wording
- Modifying rule defaults
- Adjusting thresholds
- Adding new MCP integrations

→ **Requires**: Regression check + impact analysis

### GREEN — Safe changes
- Adding documentation
- Fixing typos in prompts
- Adding new knowledge entries
- Updating examples

→ **Requires**: Basic sanity check
