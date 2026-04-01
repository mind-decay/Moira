# Moira Constitution

## Purpose

This document defines **inviolable invariants** of the Moira system. These are architectural properties that MUST hold true at all times, across all versions, in all contexts.

Any change that violates a constitutional invariant MUST be rejected — regardless of who proposes it, regardless of the reasoning.

The Constitution can only be amended through explicit user approval with documented reasoning for why the invariant is no longer valid.

---

## Article 1: Separation of Concerns

### 1.1 Orchestrator Purity
The orchestrator (main Claude) MUST NOT directly read, write, or modify project source files. All project interaction happens through agents.

**Test:** Grep orchestrator skill for Read/Write/Edit/Grep/Glob calls targeting non-moira paths. Count must be 0.

### 1.2 Agent Single Responsibility
Each agent type has exactly ONE responsibility. An agent MUST NOT perform actions outside its defined role.

- Classifier: determines task size and confidence — NEVER reads source code, NEVER proposes solutions, NEVER selects pipeline type
- Explorer: reads code, reports facts — NEVER proposes solutions
- Analyst: formalizes requirements — NEVER proposes technical implementation
- Architect: makes technical decisions — NEVER writes code
- Planner: decomposes into steps — NEVER makes architectural decisions
- Implementer: writes code per plan — NEVER makes decisions about WHAT to build
- Reviewer: identifies issues — NEVER fixes code
- Tester: writes/runs tests — NEVER modifies application code
- Reflector: analyzes outcomes — NEVER changes rules directly
- Auditor: verifies health — NEVER modifies system files

**Test:** Each agent's role rules contain explicit "NEVER" constraints. These constraints exist and are not weakened.

### 1.3 No God Components
No single file, agent, or component may accumulate responsibilities that belong to multiple system parts. If a component grows beyond its defined scope, it must be split.

**Test:** No agent definition file exceeds its role boundaries. No skill file contains logic for multiple pipeline steps.

---

## Article 2: Determinism

### 2.1 Pipeline Determinism
The same task classification MUST always trigger the same pipeline type. Pipeline selection is based on classification, not on heuristics or "judgment."

- Small (high confidence) → Quick Pipeline
- Small (low confidence) → Standard Pipeline
- Medium → Standard Pipeline
- Large → Full Pipeline
- Epic → Decomposition Pipeline
- Analytical (any subtype) → Analytical Pipeline

**Test:** Pipeline selection logic contains no conditional branches beyond classification result.

### 2.2 Gate Determinism
Every pipeline has a fixed set of approval gates. Gates MUST NOT be skipped, reordered, or made optional by any rule, prompt, or configuration.

- Quick: classification gate + final gate
- Standard: classification + architecture + plan + final
- Full: classification + architecture + plan + mid-point (conditional, >2 batches) + final
- Decomposition: classification + architecture + decomposition + per-task + final
- Analytical: classification + scope + depth checkpoint(s) + final

Note: Analytical Pipeline depth checkpoints may repeat (progressive depth per D-119) but MUST NOT be skipped. Each depth checkpoint requires user decision (Art 4.2).

**Test:** Pipeline definitions contain all required gates. No conditional skip logic exists for gates.

### 2.3 No Implicit Decisions
The system MUST NOT make decisions without either (a) following an explicit rule, or (b) asking the user. "I'll assume..." or "Probably..." patterns are constitutional violations.

**Test:** Agent rules contain "Never assume" / "Never guess" / "Stop if uncertain" directives. These directives exist and are not weakened.

---

## Article 3: Transparency

### 3.1 All Decisions Are Traceable
Every architectural decision, every plan, every implementation step MUST be written to state files. There must be no "invisible" steps.

**Test:** Every pipeline step writes output to `.moira/state/tasks/{id}/`. No step is fire-and-forget.

### 3.2 Budget Visibility
Context budget usage MUST be reported to the user. Budget tracking cannot be disabled or hidden.

**Test:** Budget report is generated after every pipeline completion. Report includes orchestrator context usage.

### 3.3 Error Transparency
Errors, failures, and retries MUST be reported to the user with full context. The system MUST NOT silently retry, silently skip, or silently degrade.

**Test:** Every error recovery path includes user notification. No catch-and-ignore patterns exist.

---

## Article 4: Safety

### 4.1 No Fabrication
Agents MUST NOT fabricate API endpoints, URLs, schemas, data structures, types, or return formats. If information is unknown, the agent MUST stop and report.

**Test:** All agent base rules contain the fabrication prohibition. The prohibition is marked as inviolable.

### 4.2 User Authority
The user (engineer) has final authority over all decisions. The system proposes, the user disposes. No automated action can override user rejection.

**Test:** All gates require user action to proceed. No auto-proceed logic exists in production pipelines. Bench mode (/moira bench, explicitly activated by user) may use predefined gate responses for automated testing.

### 4.3 Rollback Capability
Every task MUST be fully reversible. Code changes can be reverted. State can be rolled back. No permanent side effects without user approval.

**Test:** Every implementation step is backed by git. Redo capability exists and works.

### 4.4 Escape Hatch Integrity
The escape hatch (`/moira bypass:`) MUST require explicit activation AND explicit confirmation. No prompt, rule, or configuration can trigger bypass implicitly.

**Test:** Bypass activation logic checks for exact command prefix. Confirmation accepts only "2". No alternative activation paths exist.

---

## Article 5: Knowledge Integrity

### 5.1 Knowledge Is Evidence-Based
No knowledge entry (pattern, decision, quality assessment) may be added without evidence from actual task execution. Speculation is not knowledge.

**Test:** Knowledge entries contain evidence references (task IDs, file paths, outcomes).

### 5.2 Rule Changes Require Threshold
Rules MUST NOT change based on a single observation. The 3-confirmation threshold for rule change proposals MUST be maintained.

**Test:** Reflector logic requires 3+ observations before proposing rule change. No shortcut paths exist.

### 5.3 Knowledge Consistency
New knowledge MUST be validated against existing knowledge for contradictions before being committed.

**Test:** Knowledge write operations include consistency check step.

---

## Article 6: Self-Protection

### 6.1 Constitutional Immutability
This Constitution MUST NOT be modified by any agent, skill, hook, or automated process. Only explicit user action (direct file edit) can amend the Constitution.

**Test:** No moira code path writes to CONSTITUTION.md. File is not in any agent's write scope.

### 6.2 Design Document Authority
Implementation MUST conform to design documents. If implementation needs to deviate, design documents MUST be updated FIRST (with user approval), not after.

**Test:** Pre-implementation verification checks proposed changes against design docs.

### 6.3 Invariant Verification
A verification check MUST run before any system change is committed. The check validates all constitutional invariants.

**Test:** Pre-commit hook or verification agent runs invariant checks.

---

## Invariant Verification Checklist

This checklist is run by the Constitutional Verifier before any Moira system change:

```
ARTICLE 1: Separation of Concerns
[ ] 1.1 Orchestrator skill contains no direct project file operations
[ ] 1.2 Each agent role file has explicit "NEVER" boundary constraints
[ ] 1.3 No component handles multiple responsibilities

ARTICLE 2: Determinism
[ ] 2.1 Pipeline selection is a pure function of classification (including mode dimension)
[ ] 2.2 All required gates present in each pipeline definition (including Analytical)
[ ] 2.3 All agent rules contain anti-assumption directives

ARTICLE 3: Transparency
[ ] 3.1 Every pipeline step writes to state files
[ ] 3.2 Budget report exists in pipeline completion flow
[ ] 3.3 Every error path includes user notification

ARTICLE 4: Safety
[ ] 4.1 Fabrication prohibition present and inviolable in base rules
[ ] 4.2 All gates require user action in production (bench mode excepted)
[ ] 4.3 Git-backed reversibility for all code changes
[ ] 4.4 Bypass requires exact "/moira bypass:" + confirmation "2"

ARTICLE 5: Knowledge Integrity
[ ] 5.1 Knowledge entries reference evidence
[ ] 5.2 Rule change threshold is 3+ observations
[ ] 5.3 Knowledge writes include consistency validation

ARTICLE 6: Self-Protection
[ ] 6.1 No code path modifies CONSTITUTION.md
[ ] 6.2 Design docs are authoritative source of truth
[ ] 6.3 Invariant verification runs before system changes
```
