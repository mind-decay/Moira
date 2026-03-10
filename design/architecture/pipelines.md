# Pipeline Architecture

## Task Classification

First step of ANY task. Classifier agent determines size and pipeline.

| Size | Criteria | Pipeline | Gates |
|------|----------|----------|-------|
| **Small** | 1-2 files, no architecture decisions, local context | Quick | 2 (classify + final) |
| **Medium** | 3-10 files, needs project context, no new entities | Standard | 4 (classify, arch, plan, final) |
| **Large** | New entities, architecture changes, >10 files | Full | 5+ (classify, arch, plan, per-phase, final) |
| **Epic** | Multiple related tasks, requires decomposition | Decomposition | Many (classify, decomp, per-task) |

Classifier also reports **confidence**: high or low.
- High confidence + Small → Quick Pipeline
- Low confidence + Small → upgrade to Standard Pipeline

**Gate #1: User confirms classification.** Wrong classification = wrong pipeline = wrong result.

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
  │   └─ If CRITICAL → Implementer retry (max 1)
  │
  └─ [GATE: user final review]
      ├─ done   — accept
      ├─ tweak  — targeted modification
      ├─ redo   — rollback
      └─ diff   — show changes

  Post: lightweight reflection (file note, no agent)
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
  │   └─ If CRITICAL → Implementer retry (max 2 attempts total)
  │       After 2 failures → escalate to user
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
  │
  ├─ Planner → decomposition into tasks:
  │   tasks/
  │   ├─ task-001.md (large, no dependencies)
  │   ├─ task-002.md (medium, no dependencies)
  │   ├─ task-003.md (medium, depends on 001)
  │   └─ task-004.md (large, depends on 001 + 002)
  │
  │   └─ [GATE: user approves decomposition + dependency order]
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
  open new one, run /forge continue to pick up next task.
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
| Quality gate failed (attempt 1) | Retry with feedback |
| Quality gate failed (attempt 2) | Escalate to user |
| Agent crash | Retry 1x, then diagnose + escalate |
| Orchestrator context >40% | Warning |
| Orchestrator context >60% | Recommend checkpoint |
