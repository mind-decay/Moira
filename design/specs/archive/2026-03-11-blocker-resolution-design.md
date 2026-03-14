# Moira Implementation Blockers — Resolution Design

**Date:** 2026-03-11
**Status:** Approved
**Context:** Pre-implementation review identified 5 blockers and 4 design defects. This document captures the approved resolutions.

---

## Blocker 1: Classifier Agent Definition

**Problem:** `pipelines.md` and `overview.md` reference a Classifier agent as the first step of every pipeline, but `agents.md` defines only 8 agents — Classifier is missing.

**Resolution:** Classifier is the 10th agent (8 base + Auditor + Classifier).

- **Role:** Determines task size and pipeline type
- **Input:** User's task description + optional size hint
- **Output:** `{ size: small|medium|large|epic, confidence: high|low, reasoning: string }` (Note: `pipeline` field removed per D-062 — pipeline selection is orchestrator's responsibility)
- **Knowledge access:** L1 (summary) — needs project context for scope assessment
- **Budget:** ~20k tokens (minimal — fast classification)
- **NEVER constraints:**
  - NEVER read project source code (only task description + knowledge summary)
  - NEVER propose solutions or architecture
  - NEVER change the task description
  - NEVER skip classification (always return a result)
- **Pipeline mapping** (per Constitution Art 2.1):
  - small + high confidence → Quick
  - small + low confidence → Standard
  - medium → Standard
  - large → Full
  - epic → Decomposition
- **Size hint handling:** If user provides `/moira small: ...`, hint is passed to Classifier as input. Classifier may agree or override with reasoning.

**Decision log:** Extends D-004 (agents list).

---

## Blocker 2: YAML Schemas for State Files

**Problem:** Five state files referenced throughout design docs have no schemas: `manifest.yaml`, `current.yaml`, `queue.yaml`, `config.yaml`, `status.yaml`.

**Resolution:** Full schemas designed upfront for all 12 phases.

### 2.1: `config.yaml` — Project Configuration (committed)

```yaml
# .claude/moira/config.yaml
version: "1.0"
project:
  name: string                    # project name
  root: string                    # absolute path to project root
  stack: string                   # free-form stack string (presets removed per D-060)

classification:
  default_pipeline: standard      # fallback if Classifier is uncertain
  size_hints_override: false      # can size hint bypass Classifier

pipelines:
  quick:
    max_retries: 1
    gates: [classification, final]
  standard:
    max_retries: 2
    gates: [classification, architecture, plan, final]
  full:
    max_retries: 2
    gates: [classification, architecture, plan, per-phase, final]
  decomposition:
    max_retries: 2
    gates: [classification, decomposition, per-task, final]

budgets:
  orchestrator_max_percent: 25     # Art 3.2 — max context usage
  agent_max_load_percent: 70       # never load agent >70%
  per_agent:                       # token limits per agent type
    classifier: 20000
    explorer: 140000
    analyst: 60000
    architect: 100000
    planner: 80000
    implementer: 140000
    reviewer: 80000
    tester: 100000
    reflector: 60000
    auditor: 60000

quality:
  mode: conform                    # conform|evolve
  evolution_threshold: 3           # min observations for rule change (Art 5.2)
  review_severity_minimum: medium  # minimum severity to block

knowledge:
  freshness_days: 30               # after this — stale marker
  archival_max_entries: 100        # entries before archival rotation

audit:
  light_every_n_tasks: 10
  standard_every_n_tasks: 20
  auto_batch_apply_risk: low       # low-risk recommendations applied in batch

mcp:
  enabled: false                   # MCP integration toggle
  registry_path: config/mcp-registry.yaml

hooks:
  guard_enabled: true              # PostToolUse audit hook
  budget_tracking_enabled: true
```

### 2.2: `current.yaml` — Active Pipeline State (gitignored)

```yaml
# .claude/moira/state/current.yaml
task_id: "task-042"                # active task ID (null if idle)
pipeline: standard                 # pipeline type
started_at: "2026-03-11T14:30:00Z"
developer: "alice"                 # from git config user.name

step: plan                         # current pipeline step
step_status: in_progress           # pending|in_progress|awaiting_gate|completed|failed
step_started_at: "2026-03-11T14:35:00Z"

gate_pending: null                 # null or gate name awaiting approval
gate_options: []                   # available actions at gate

history:                           # completed steps for current task
  - step: classification
    status: completed
    duration_sec: 12
    agent_tokens_used: 3200
    result: "size=medium, confidence=high"
  - step: exploration
    status: completed
    duration_sec: 45
    agent_tokens_used: 28000
    result: "3 artifacts written"
  - step: architecture
    status: completed
    duration_sec: 38
    agent_tokens_used: 42000
    result: "architecture.md written, gate approved"

context_budget:
  orchestrator_tokens_used: 8500   # estimated
  orchestrator_percent: 8.5
  total_agent_tokens: 73200
  warning_level: normal            # normal|warning|critical

bypass:
  active: false                    # true if escape hatch is active
  reason: null
  confirmed_at: null
```

### 2.3: `status.yaml` — Per-Task Status (gitignored)

```yaml
# .claude/moira/state/tasks/{id}/status.yaml
task_id: "task-042"
description: "Add pagination to user list endpoint"
size: medium
confidence: high
pipeline: standard
developer: "alice"

status: in_progress                # pending|in_progress|completed|failed|aborted
created_at: "2026-03-11T14:30:00Z"
completed_at: null

classification:
  classifier_size: medium
  classifier_confidence: high
  user_hint: null                  # size hint if provided
  overridden: false                # Classifier overrode hint?
  reasoning: "Multiple files affected, new API endpoint, tests needed"

artifacts:                         # files created by agents
  exploration: exploration.md
  architecture: architecture.md
  plan: plan.md
  implementation:
    - batch-1-result.md
    - batch-2-result.md
  review: review.md
  tests: tests.md

gates:                             # gate decision history
  - gate: classification
    decision: proceed
    at: "2026-03-11T14:30:15Z"
  - gate: architecture
    decision: proceed
    at: "2026-03-11T14:32:40Z"
  - gate: plan
    decision: modify
    at: "2026-03-11T14:35:00Z"
    note: "Split batch 2 into smaller chunks"
  - gate: plan
    decision: proceed
    at: "2026-03-11T14:36:10Z"

retries:                           # retry attempts
  - step: implementation
    attempt: 1
    reason: "E4-REVIEW: critical issue in error handling"
    at: "2026-03-11T14:45:00Z"

budget:
  estimated_tokens: 120000         # Planner's pre-estimate
  actual_tokens: 73200             # actually used
  by_agent:
    classifier: 3200
    explorer: 28000
    architect: 42000
    planner: 0
    implementer: 0
    reviewer: 0
    tester: 0

completion:                        # filled on completion
  action: null                     # done|tweak|redo
  tweak_count: 0
  redo_count: 0
  final_review_passed: false
```

### 2.4: `manifest.yaml` — Checkpoint for Resume (gitignored)

```yaml
# .claude/moira/state/tasks/{id}/manifest.yaml
task_id: "task-042"
pipeline: standard
developer: "alice"

checkpoint:
  step: implementation             # last completed step
  batch: 2                         # for implementation — batch number
  created_at: "2026-03-11T15:10:00Z"
  reason: context_limit            # context_limit|user_pause|error|session_end

resume_context: |
  Implementing pagination for /api/users endpoint.
  Architecture: cursor-based pagination with Prisma.
  Plan: 3 batches — (1) API layer, (2) DB queries, (3) tests.
  Batch 1 completed — controller + route added.
  Batch 2 in progress — Prisma query with cursor was written,
  but review found missing edge case for empty result set.
  Next: fix edge case, then batch 3 (tests).

decisions_made:                    # key decisions for resume context
  - "Cursor-based over offset pagination (architecture gate)"
  - "Prisma raw query for complex cursor logic (plan gate)"
  - "Split tests into separate batch (plan gate)"

files_modified:                    # files changed by this task
  - path: src/api/users/controller.ts
    batch: 1
    git_sha: "a1b2c3d"
  - path: src/api/users/pagination.ts
    batch: 2
    git_sha: "d4e5f6a"

files_expected:                    # files still to create/modify
  - path: src/api/users/pagination.ts
    batch: 2
    note: "Fix empty result edge case"
  - path: tests/api/users/pagination.test.ts
    batch: 3

dependencies:                      # inter-batch contracts
  - from_batch: 1
    to_batch: 2
    contract: "Controller calls PaginationService.paginate(cursor, limit)"
  - from_batch: 2
    to_batch: 3
    contract: "PaginationService exports paginate() returning { items, nextCursor, hasMore }"

validation:                        # for resume verification
  git_branch: "feat/user-pagination"
  git_head_at_checkpoint: "d4e5f6a"
  external_changes_expected: false  # if true — needs validation
```

### 2.5: `queue.yaml` — Epic Task Queue (gitignored)

```yaml
# .claude/moira/state/queue.yaml
epic_id: "epic-003"
description: "Migrate authentication from JWT to session-based"
created_at: "2026-03-11T10:00:00Z"
developer: "alice"

tasks:
  - task_id: "task-040"
    title: "Add session store with Redis adapter"
    status: completed               # pending|in_progress|completed|failed|aborted
    pipeline: standard
    depends_on: []
    completed_at: "2026-03-11T12:30:00Z"

  - task_id: "task-041"
    title: "Implement session middleware"
    status: completed
    pipeline: standard
    depends_on: ["task-040"]
    completed_at: "2026-03-11T13:45:00Z"

  - task_id: "task-042"
    title: "Migrate login/logout endpoints to sessions"
    status: in_progress
    pipeline: standard
    depends_on: ["task-041"]
    completed_at: null

  - task_id: "task-043"
    title: "Update auth guards and middleware chain"
    status: pending
    pipeline: standard
    depends_on: ["task-042"]
    completed_at: null

  - task_id: "task-044"
    title: "Remove JWT dependencies and cleanup"
    status: pending
    pipeline: quick
    depends_on: ["task-043"]
    completed_at: null

  - task_id: "task-045"
    title: "Integration tests for session auth flow"
    status: pending
    pipeline: standard
    depends_on: ["task-043"]        # parallel with task-044
    completed_at: null

progress:
  total: 6
  completed: 2
  in_progress: 1
  pending: 3
  failed: 0
```

---

## Blocker 3: Skill Registration Mechanism

**Problem:** `register_skills()` in `install.sh` is a stub. No mechanism for making `/moira` commands available.

**Resolution:** Moira uses the Claude Code native custom commands pattern (markdown files in `~/.claude/commands/`) — the same file convention GSD uses, but with zero GSD runtime dependency. This is consistent with D-013 (self-contained system).

**Structure:**
```
~/.claude/
├── moira/                              # core system
│   ├── skills/
│   │   └── orchestrator.md             # main orchestrator skill
│   ├── core/
│   │   ├── rules/
│   │   │   ├── base.yaml
│   │   │   ├── roles/
│   │   │   │   ├── classifier.yaml
│   │   │   │   ├── explorer.yaml
│   │   │   │   ├── analyst.yaml
│   │   │   │   ├── architect.yaml
│   │   │   │   ├── planner.yaml
│   │   │   │   ├── implementer.yaml
│   │   │   │   ├── reviewer.yaml
│   │   │   │   ├── tester.yaml
│   │   │   │   ├── reflector.yaml
│   │   │   │   └── auditor.yaml
│   │   │   └── quality/
│   │   │       ├── q1-requirements.yaml
│   │   │       ├── q2-architecture.yaml
│   │   │       ├── q3-plan.yaml
│   │   │       ├── q4-review.yaml
│   │   │       └── q5-tests.yaml
│   │   └── checklists/
│   │       └── constitutional-checks.yaml
│   ├── templates/
│   │   ├── project-claude-md.tmpl
│   │   └── scanners/                    # stack-presets/ removed per D-060
│   │       ├── nextjs.yaml
│   │       ├── react.yaml
│   │       ├── vue.yaml
│   │       ├── python.yaml
│   │       ├── go.yaml
│   │       ├── rust.yaml
│   │       ├── java.yaml
│   │       └── generic.yaml
│   ├── hooks/
│   │   ├── guard.sh
│   │   └── budget-track.sh
│   └── VERSION
│
├── commands/moira/                     # user-facing slash commands
│   ├── init.md                         # /moira:init
│   ├── task.md                         # /moira — main entry point
│   ├── status.md                       # /moira:status
│   ├── metrics.md                      # /moira:metrics
│   ├── audit.md                        # /moira:audit
│   ├── knowledge.md                    # /moira:knowledge
│   ├── bypass.md                       # /moira:bypass
│   ├── resume.md                       # /moira:resume
│   ├── refresh.md                      # /moira:refresh
│   └── help.md                         # /moira:help
│
└── settings.json                       # hooks registration (merge)
```

**Command file format** (GSD model):
```yaml
---
name: moira:task
description: Execute a task through the Moira orchestration pipeline
argument-hint: "[small:|medium:|large:] <task description>"
allowed-tools:
  - Agent          # dispatch subagents
  - Read           # read moira state/config files ONLY (.claude/moira/ paths)
  - Write          # write moira state files ONLY (.claude/moira/state/ paths)
  - TaskCreate     # todo tracking
  - TaskUpdate
  - TaskList
  # NOT included: Edit, Grep, Glob, Bash — orchestrator cannot touch project files or run commands (D-001)
---
```

**Existing `.claude/` compatibility rules:**

1. **`.claude/` already exists** — Moira creates only `.claude/moira/` subdirectory. Does not touch anything outside `moira/`.
2. **`.claude/CLAUDE.md` already exists** — Moira appends its section wrapped in markers:
   ```markdown
   <!-- moira:start -->
   ## Moira Orchestration System
   ...orchestrator instructions...
   <!-- moira:end -->
   ```
   On re-init or refresh — replaces only content between markers.
3. **`.claude/CLAUDE.md` does not exist** — Creates file with Moira section.
4. **`.claude/commands/` already exists** (GSD or other) — Moira uses its own `commands/moira/` namespace, no conflicts.
5. **Repeated `/moira:init`** — Idempotent. No duplicate sections, preserves knowledge. Regenerates config, updates CLAUDE.md section, rescans project.
6. **`/moira:init --force`** — Full reinitialization: recreates config, reruns scanners, **preserves** accumulated knowledge.

---

## Blocker 4: Claude Code API Verification

**Problem:** Design assumes hook capabilities and agent dispatch that need verification.

**Findings from research:**

| Capability | Actual Status |
|---|---|
| Agent tool (foreground/background dispatch) | Confirmed — native Claude Code tool with `run_in_background` parameter |
| Parallel agent dispatch | Confirmed — multiple Agent calls in single message |
| SessionStart hook | Confirmed — fires on startup/resume/clear/compact |
| PostToolUse hook | Confirmed — fires after tool execution, receives JSON on stdin |
| PreToolUse hook | Does NOT exist — hooks cannot block tool calls |
| Hook `additionalContext` injection | Confirmed — hooks inject messages into agent context via stdout JSON |
| `allowed-tools` in command frontmatter | Confirmed — restricts available tools for command execution |

**Resolution:** Three-layer guard mechanism (replaces guard.sh PreToolUse design):

1. **`allowed-tools` in command frontmatter** (prevention) — Orchestrator commands exclude Edit/Grep/Glob. Orchestrator physically cannot invoke forbidden tools.
2. **PostToolUse `guard.sh` hook** (detection) — Monitors all tool calls, logs violations, injects constitutional violation warning into context via `additionalContext`.
3. **CLAUDE.md prompt enforcement** (guidance) — Moira section in project CLAUDE.md contains inviolable rules about orchestrator boundaries.

**guard.sh implementation:**

```bash
#!/bin/bash
# PostToolUse hook — fires AFTER every tool call in moira sessions
# Reads JSON from stdin, checks for violations, logs audit trail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.command // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
state_dir="$HOME/.claude/moira/state"

# Only monitor moira sessions
if [ ! -f "$state_dir/current.yaml" ]; then
  exit 0
fi

# Log all tool usage for audit trail
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $tool_name $file_path" >> "$state_dir/tool-usage.log"

# Check for violations — orchestrator touching project files with forbidden tools
# Covers full Art 1.1 test: Read/Write/Edit/Grep/Glob on non-moira paths
moira_path=".claude/moira"
if [[ "$tool_name" =~ ^(Read|Write|Edit|Grep|Glob)$ ]]; then
  if [[ -n "$file_path" && "$file_path" != *"$moira_path"* ]]; then
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"CONSTITUTIONAL VIOLATION: Orchestrator used $tool_name on $file_path. Art 1.1 prohibits direct project file operations. This is logged and will appear in audit.\"}}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) VIOLATION $tool_name $file_path" >> "$state_dir/violations.log"
  fi
fi

# Check for Bash violations — only moira state reads allowed, not project commands
if [[ "$tool_name" == "Bash" ]]; then
  if [[ -n "$file_path" && ! "$file_path" =~ ^(cat|head|tail).*\.claude/moira ]]; then
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"WARNING: Orchestrator used Bash with command: $file_path. D-001 prohibits running commands. Only moira state reads are allowed.\"}}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) WARN-BASH $file_path" >> "$state_dir/violations.log"
  fi
fi
```

**Impact on design documents:**
- `design/subsystems/self-monitoring.md` — rewrite guard.sh section from PreToolUse to PostToolUse + allowed-tools
- `design/architecture/overview.md` — add `allowed-tools` as primary enforcement mechanism
- `design/IMPLEMENTATION-ROADMAP.md` — Phase 8 scope changes (hooks are audit, not prevention)

---

## Blocker 5: Bootstrap Scanner Agents

**Problem:** `knowledge.md` introduces 4 scanner agents (Tech, Structure, Convention, Pattern) not defined in `agents.md`.

**Resolution:** Scanners are Explorer agent invocations with different task-specific instructions (Layer 4 rules). No new agent types needed.

**Tech Scanner** — Explorer with instruction:
> Scan the project and report ONLY technical stack facts: languages and versions, frameworks and libraries, build tools, test frameworks, linting/formatting, database/ORM, deployment config. Output: structured list. NO opinions, NO recommendations.

**Structure Scanner** — Explorer with instruction:
> Scan the project directory structure and report ONLY structural facts: top-level layout, entry points, config locations, test organization, source vs generated vs vendored. Output: annotated directory tree. NO opinions, NO recommendations.

**Convention Scanner** — Explorer with instruction:
> Scan source code and report ONLY observed conventions: naming patterns, import style, export patterns, error handling, logging, code organization. Output: convention list with 2-3 evidence examples each. NO opinions, NO recommendations.

**Pattern Scanner** — Explorer with instruction:
> Scan source code and report ONLY recurring patterns: component/module structure, API endpoints, data access, state management, common abstractions. Output: pattern catalog with file path evidence. NO opinions, NO recommendations.

**Dispatch:** All 4 launched in parallel via Agent tool with `run_in_background: true`. Results written to `.claude/moira/knowledge/` as L2 (full) documents, from which L1 (summary) and L0 (index) are generated.

**Budget:** Each scanner uses standard Explorer budget (140k tokens). Total bootstrap ≈ 560k tokens (quick scan). Deep scan launches in background during first task with increased budget for Convention and Pattern scanners.

---

## Design Defect Resolutions

### Defect 6: Lock Visibility in Multi-Developer

**Problem:** `locks.yaml` is in gitignored `state/` directory, but locks must be visible across developers.

**Resolution:** Move `locks.yaml` to committed zone: `.claude/moira/config/locks.yaml`. On conflicts — standard git merge. Locks include TTL (`expires_at` field) and stale detection during audit.

### Defect 7: Escape Hatch vs Orchestrator Purity

**Problem:** `escape-hatch.md` says "run direct implementation" but Art 1.1 prohibits orchestrator from writing project files.

**Resolution:** Bypass = dispatch Implementer directly, skipping Explorer/Analyst/Architect/Planner steps. Orchestrator still only dispatches — Art 1.1 preserved. Only gate is final review.

### Defect 8: Git Revert in Redo

**Problem:** `tweak-redo.md` assumes git revert but D-001 states the orchestrator "never runs commands" and `overview.md` lists "Run bash commands (except agent dispatch)" as a prohibition.

**Resolution:** Orchestrator dispatches a minimal Implementer agent with a single instruction: execute the git revert. The orchestrator does NOT run Bash directly for git revert — this preserves D-001 ("never runs commands") and Art 1.1 (orchestrator purity). The Implementer agent has Bash in its allowed-tools and can execute git operations as part of its implementation role.

Note: the orchestrator's `allowed-tools` includes `Bash` for reading moira state files only (e.g., `cat .claude/moira/state/current.yaml`). Git revert is NOT an orchestrator Bash operation — it is delegated to an agent.

### Defect 9: Constitutional Invariant Count

**Problem:** `self-protection.md` states "23 invariants" twice, but Constitution has 19 (Articles 1.1-1.3, 2.1-2.3, 3.1-3.3, 4.1-4.4, 5.1-5.3, 6.1-6.3).

**Resolution:** Correct to "19 invariants" in `self-protection.md`.

---

## Design Documents Requiring Updates

Based on all resolutions above, the following design documents need updates:

| Document | Changes |
|---|---|
| `design/architecture/agents.md` | Add Classifier as 10th agent; note that bootstrap scanners are Explorer invocations |
| `design/architecture/overview.md` | Add `allowed-tools` enforcement; update file tree with `commands/moira/`; add `config/locks.yaml` |
| `design/architecture/pipelines.md` | Reference Classifier agent definition |
| `design/architecture/distribution.md` | Replace plugin model with GSD command model; update `register_skills()` to file copy + commands |
| `design/architecture/escape-hatch.md` | Clarify bypass = direct Implementer dispatch, not orchestrator execution |
| `design/architecture/tweak-redo.md` | Clarify git revert is delegated to Implementer agent, not orchestrator |
| `design/subsystems/self-monitoring.md` | Rewrite guard.sh from PreToolUse to PostToolUse + allowed-tools |
| `design/subsystems/self-protection.md` | Fix "23" → "19" invariants |
| `design/subsystems/knowledge.md` | Clarify bootstrap scanners are Explorer with Layer 4 instructions |
| `design/subsystems/multi-developer.md` | Move locks.yaml to committed config zone; add TTL field |
| `design/decisions/log.md` | Add D-028 through D-033 for all decisions made in this session |
| `design/IMPLEMENTATION-ROADMAP.md` | Add YAML schemas to Phase 1 deliverables; add Classifier to Phase 2 |
| `CLAUDE.md` (project) | No changes needed — existing rules cover new design |

---

## New Decision Log Entries

- **D-028:** Classifier is a full agent (not orchestrator function) — preserves Art 1.1 purity
- **D-029:** Full YAML schemas designed upfront — prevents ad-hoc architectural decisions during implementation
- **D-030:** Claude Code native custom commands for distribution — same file convention as GSD, zero runtime dependency on GSD (D-013 preserved)
- **D-031:** Three-layer guard (allowed-tools + PostToolUse + prompt) — replaces PreToolUse assumption
- **D-032:** Bootstrap scanners are Explorer invocations with Layer 4 instructions — no new agent types
- **D-033:** Locks in committed zone with TTL — resolves cross-developer visibility
