# Pipeline Architecture

## Task Classification

First step of ANY task. Classifier agent determines size and pipeline.

| Size | Criteria | Pipeline | Gates |
|------|----------|----------|-------|
| **Small** | 1-2 files, no architecture decisions, local context | Quick | 2 (classify + final) |
| **Medium** | 3-10 files, needs project context, no new entities | Standard | 4 (classify, arch, plan, final) |
| **Large** | New entities, architecture changes, >10 files | Full | 5+ (classify, arch, plan, per-phase, final) |
| **Epic** | Multiple related tasks, requires decomposition | Decomposition | Many (classify, arch, decomp, per-task, final) |
| **Small (low confidence)** | 1-2 files, classification uncertain | Standard | 4 (classify, arch, plan, final) |

Classifier also reports **confidence**: high or low.
- High confidence + Small → Quick Pipeline
- Low confidence + Small → upgrade to Standard Pipeline

**Monorepo support:** For monorepo projects, Classifier includes package scoping in its output — which packages are relevant to the task. Explorer receives package-scoped instructions limiting exploration to those packages and their direct dependencies. If scope proves insufficient during exploration, E2-SCOPE (monorepo subtype, D-070) triggers re-scoping with user input.

**Gate #1: User confirms classification.** Wrong classification = wrong pipeline = wrong result.

**Minimum viable task size:** The Quick Pipeline adds ~1-3 minutes of overhead (classification + exploration + implementation + review). Tasks that can be done correctly in under 30 seconds are better served by the escape hatch (`/moira bypass:`). The pipeline's value is in tasks where getting it right the first time matters more than speed.

---

## Quick Pipeline (Small Tasks, High Confidence)

```
USER → task description
  │
  ├─ Classifier → small (confidence: high)
  │   └─ [GATE: confirm classification]
  │
  ├─ Explorer → finds relevant files → context.md
  │
  ├─ Implementer → reads context, makes changes
  │   (loads conventions L2, project context minimal)
  │
  ├─ Reviewer → quick review
  │   └─ If CRITICAL → Implementer retry (max_attempts=2, D-095)
  │
  └─ [GATE: user final review]
      ├─ done   — accept
      ├─ tweak  — targeted modification
      ├─ redo   — rollback
      ├─ diff   — show changes
      └─ test   — run additional tests (dispatches Aletheia ad-hoc, not a pipeline step)

  Post: Orchestrator writes structured reflection note to
        `.claude/moira/state/tasks/{id}/reflection-note.yaml`:
        ```yaml
        task_id: {id}
        classification_correct: true|false
        implementation_accepted: true|false|tweaked
        issues_found: []  # list of review findings if any
        knowledge_updates: []  # typically empty for quick tasks
        ```
        No Reflector agent dispatched — this is a lightweight
        substitute for Quick Pipeline knowledge accumulation.
  Budget report displayed.
```

**Time estimate: 1-3 minutes. Minimal context usage.**

---

## Standard Pipeline (Medium Tasks)

```
USER → task description
  │
  ├─ Classifier → medium
  │   └─ [GATE: confirm classification]
  │
  ├─ PARALLEL (both foreground, sent in one message):
  │   ├─ Explorer → codebase analysis → exploration.md
  │   └─ Analyst → requirements formalization → requirements.md
  │
  ├─ Architect → reads both → architecture.md
  │   └─ [GATE: user approves architecture]
  │       ├─ proceed — continue
  │       ├─ details — show full reasoning
  │       ├─ modify  — provide feedback
  │       └─ abort   — cancel
  │
  ├─ Planner → creates plan + assembles agent instructions → plan.md
  │   └─ [GATE: user approves plan]
  │       ├─ proceed  — continue
  │       ├─ details  — show full plan
  │       ├─ modify   — provide feedback for plan revision
  │       ├─ rearchitect — route back to Architect with feedback (max 1x per pipeline)
  │       │   └─ Metis receives original architecture + user's plan-gate feedback
  │       │   └─ After revised architecture → architecture gate presented again
  │       │   └─ Then Planner runs again with new architecture
  │       └─ abort    — cancel
  │
  ├─ Implementation (batched):
  │   ├─ Phase 1 (parallel background):
  │   │   ├─ Implementer-A → Batch A
  │   │   ├─ Implementer-B → Batch B
  │   │   └─ Implementer-C → Batch C
  │   │
  │   └─ Phase 2 (dependent batches, after Phase 1):
  │       ├─ Implementer-D → Batch D
  │       └─ Implementer-E → Batch E (shared files)
  │
  ├─ Reviewer → reviews all changes (foreground)
  │   └─ If CRITICAL → Implementer retry (max_attempts=3, D-095)
  │       After max_attempts exhausted → escalate to user
  │
  ├─ Tester → writes + runs tests (foreground)
  │
  └─ [GATE: user final review]
      ├─ done / tweak / redo / diff / test

  Post: Reflector (background, non-blocking)
  Budget report displayed.
```

---

## Full Pipeline (Large Tasks)

```
USER → task description
  │
  ├─ Classifier → large
  │   └─ [GATE: confirm classification]
  │
  ├─ PARALLEL:
  │   ├─ Explorer → deep analysis → exploration.md
  │   └─ Analyst → deep requirements → requirements.md
  │
  ├─ Architect → architecture.md + alternatives.md
  │   └─ [GATE: user CHOOSES architecture from alternatives]
  │
  ├─ Planner → phased plan with dependencies → plan.md
  │   └─ [GATE: user approves plan]
  │       ├─ proceed  — continue
  │       ├─ details  — show full plan
  │       ├─ modify   — provide feedback for plan revision
  │       ├─ rearchitect — route back to Architect with feedback (max 1x per pipeline)
  │       │   └─ Metis receives original architecture + user's plan-gate feedback
  │       │   └─ After revised architecture → architecture gate presented again
  │       │   └─ Then Planner runs again with new architecture
  │       └─ abort    — cancel
  │
  ├─ For each phase:
  │   ├─ Implementers (batched, parallel where possible)
  │   ├─ Reviewer → phase review
  │   ├─ Tester → phase tests
  │   └─ [GATE: phase approval]
  │       (checkpoint saved — can resume in new session)
  │
  ├─ Integration check (Tester on cross-phase boundaries)
  │
  └─ [GATE: final review]

  Post: Deep Reflector analysis (background)
```

---

## Decomposition Pipeline (Epics)

```
USER → epic description (from YouTrack, Slack, etc.)
  │
  ├─ Classifier → epic
  │   └─ [GATE: confirm]
  │
  ├─ Analyst → deep requirement breakdown → epic-requirements.md
  │
  ├─ Architect → system-level design → epic-architecture.md
  │   └─ [GATE: architecture approval] (D-085)
  │
  ├─ Planner → decomposition into tasks:
  │   tasks/
  │   ├─ task-001.md (large, no dependencies)
  │   ├─ task-002.md (medium, no dependencies)
  │   ├─ task-003.md (medium, depends on 001)
  │   └─ task-004.md (large, depends on 001 + 002)
  │
  │   └─ [GATE: user approves decomposition + dependency order]
  │       ├─ proceed  — continue
  │       ├─ details  — show full decomposition
  │       ├─ modify   — provide feedback for decomposition revision
  │       ├─ rearchitect — route back to Architect with feedback (max 1x per pipeline)
  │       │   └─ Metis receives original architecture + user's decomposition-gate feedback
  │       │   └─ After revised architecture → architecture gate presented again
  │       │   └─ Then Planner re-decomposes with new architecture
  │       └─ abort    — cancel
  │
  ├─ For each task (respecting dependencies):
  │   └─ Execute via appropriate pipeline (Standard/Full)
  │   └─ [GATE after each task]
  │   └─ Checkpoint saved (each task is resumable independently)
  │
  ├─ Integration verification (cross-task)
  │
  └─ Epic-level reflection

  Each sub-task creates a checkpoint. User can close session,
  open new one, run /moira continue to pick up next task.
```

---

## Smart Batching (within Implementation step)

### Planner creates batches based on:

**Step 1: File Dependency Graph**
```
src/types/user.ts ──────────┐
                             ├──→ src/api/users.ts ──→ src/api/index.ts
src/db/user-repository.ts ──┘
```

**Step 2: Cluster by dependency** — files that depend on each other = one cluster

**Step 3: Budget check per cluster** — if cluster exceeds budget → split

**Step 4: Execution phases**
- Phase 1: all independent clusters (parallel)
- Phase 2: dependent clusters (after Phase 1 completes)
- Final: shared files (imports from multiple clusters)

**Step 5: CPM Optimization**

Critical Path Method replaces the fixed 3-phase heuristic with optimal multi-phase scheduling:

```
Input: File dependency DAG from Steps 1-2
Output: Optimal phase assignment minimizing total pipeline time

1. Topological sort the DAG
2. Forward pass: earliest_start(v) = max(earliest_finish(u)) for all predecessors u
3. Backward pass: latest_start(v) from terminal nodes
4. Critical path = nodes where earliest_start == latest_start (zero slack)
5. Phase assignment: nodes with same earliest_start go in same phase
6. Budget check: if any phase exceeds agent budget, split using LPT heuristic
```

LPT (Longest Processing Time first) for budget-constrained splitting: sort files by estimated size descending, assign each to batch with smallest current total. Guarantee: total makespan ≤ (4/3) × optimal.

Constraints preserved:
- Shared files (modified by multiple clusters) still go in FINAL batch (unchanged)
- Contract interfaces between batches still defined by Architect (unchanged)
- Budget per batch still checked (now uses LPT for splitting instead of arbitrary splits)

### Contract Interface System

When batches depend on each other, Architect defines contracts:

```markdown
Contract: Batch A → Batch D
Batch A will export from src/types/user.ts:
- interface User { id: string; name: string; email: string; role: UserRole }
- type UserRole = 'admin' | 'user' | 'viewer'

Batch D MUST use these types as-is.
```

### Merge Conflict Prevention

Files modified by multiple clusters → always in the FINAL batch, executed by a single Implementer who sees all previous results.

---

## Approval Gate UX

Standard gate format:

```
═══════════════════════════════════════════
 GATE: <Gate Name>
═══════════════════════════════════════════

 Summary:
 <1-3 sentences describing what was decided/produced>

 Key points:
 • <bullet 1>
 • <bullet 2>
 • <bullet 3>

 Impact: <files affected, estimated budget usage>

 Details:
 → <path to full document>

 ▸ proceed   — continue to next step
 ▸ details   — show full document
 ▸ modify    — provide feedback for revision
 ▸ abort     — cancel task
═══════════════════════════════════════════
```

---

## Mid-Pipeline Mutation Detection

At each pipeline step boundary (before dispatching the next agent), the orchestrator performs a `git status` check to detect external modifications:

1. Compare modified files from `git status` against the pipeline's known working set (files explored, files planned for modification, files already changed by previous steps)
2. If overlap detected, the orchestrator pauses and presents options:

```
═══════════════════════════════════════════
 ⚠ EXTERNAL CHANGES DETECTED (mid-pipeline)
═══════════════════════════════════════════
 Files modified externally during pipeline execution:
 - src/api/users.ts (in working set — planned for modification)
 - src/types/roles.ts (in working set — explored)

 ▸ accept     — update working set, continue with current plan
 ▸ re-explore — re-run Explorer on changed files, then resume
 ▸ abort      — cancel pipeline
═══════════════════════════════════════════
```

This catches human edits made during gate waits that would otherwise cause agents to work from stale data. Non-overlapping external changes (files outside the working set) are ignored.

---

## State Transition Validation

Each pipeline state transition is validated against the pipeline YAML definition before execution:

- Before transitioning from step X to step Y, the orchestrator checks that Y is a valid successor of X per the pipeline definition
- Invalid transitions (e.g., skipping a required step, transitioning to a non-successor) are logged and blocked — treated as an orchestrator error (E6-ORCH)
- This makes step-skipping structurally detectable even if the orchestrator's context degrades during long pipelines

---

## Pipeline Error Handling

See [Fault Tolerance](../subsystems/fault-tolerance.md) for full error taxonomy and recovery.

Summary of pipeline-level error handling:

| Error | Pipeline Response |
|-------|-------------------|
| Agent blocked (missing info) | Pause, ask user, resume |
| Scope change detected | Stop, re-classify, gate |
| Conflict detected | Stop, present options, gate |
| Budget exceeded (pre-exec) | Planner auto-splits |
| Budget exceeded (mid-exec) | Save partial, spawn new agent |
| Quality gate failed (attempts 1-2) | Retry with feedback / architect rethink |
| Quality gate failed (attempt 3) | Escalate to user |
| Agent crash | Retry 1x, then diagnose + escalate |
| Semantic error (wrong content) | Reviewer catches → retry with feedback, or gate modify |
| Agent data conflict | Architect flags → present both versions at gate |
| Context truncation | Budget pre-check → split; Reviewer post-check → retry reduced |
| Orchestrator context >25% | Monitor (include in gate status) |
| Orchestrator context >40% | Warning (offer checkpoint) |
| Orchestrator context >60% | Mandatory checkpoint (D-064) |

See [context-budget.md](../subsystems/context-budget.md) for the full 4-tier budget threshold specification.
