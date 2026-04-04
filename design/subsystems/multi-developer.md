# Multi-Developer System

## Problem

Multiple engineers on same project, each with their own Claude sessions:
1. Both read shared knowledge base
2. Both may update knowledge
3. Both may modify same files
4. Task state must not conflict

## Solution: Branch-Scoped State + Shared Knowledge

```
.moira/
├── knowledge/     ← SHARED (git-tracked, merges with PRs)
├── config/        ← SHARED (git-tracked)
│   └── locks.yaml ← file reservation system (committed for cross-developer visibility, D-033)
├── core/          ← SHARED (git-tracked)
├── project/       ← SHARED (git-tracked)
│
├── state/         ← BRANCH-SCOPED
│   ├── .gitignore
│   ├── tasks/     ← per-task, per-branch isolation
│   └── metrics/   ← SHARED (git-tracked, append-friendly)
└── hooks/         ← SHARED (git-tracked)
```

### State: Branch-scoped, not committed until done

- Task files, manifests, instructions → per developer's working directory
- Not committed until task's code changes are committed
- Each developer's state doesn't interfere with others

### Knowledge: Shared, committed with code

- Updated at end of task, committed alongside code changes
- Merges through normal git flow (PR review)
- Append-friendly format prevents merge conflicts

## File Conflict Handling (D-226)

File conflicts between developers are handled by git's standard merge conflict mechanism. Moira's contribution: both tasks have full `architecture.md` and `plan.md`, giving merge reviewers context from both sides.

### Planner File Manifest

Planner (Daedalus) writes `reserved-files.txt` as a structured artifact during planning — one file path per line of files the plan intends to modify. This is used for impact analysis, not enforcement. If absent → graceful degradation.

### Why Not Locks?

File locking was designed (D-220) but deferred (D-226). Analysis showed:
- Git already handles file conflicts — merge conflicts are a solved problem, not data loss
- Per-session locks in gitignored state are invisible to other developers
- ~150 lines of shell + 20 test assertions for marginal earlier detection
- If merge conflicts become a practical problem, revisit with real evidence

## Knowledge Merge Strategy

### Append-friendly format

Knowledge files use sectioned format, not narrative:

```markdown
## [078] Repository caching pattern
Added: 2024-01-15, Task: 078
...

## [079] Search index refresh pattern
Added: 2024-01-15, Task: 079
...
```

Both sections coexist. No merge conflict.

### Structural Conflict Detection (D-221)

Before writing a new entry, shell function in `knowledge.sh` checks for exact header collision in `full.md`. If duplicate header found → entry written to `contested.md` instead of `full.md`. See `knowledge.md` § Conflict Detection for full design.

**What is detected:** Identical `## Decision:` or `## Pattern:` headers with different content.
**What is NOT detected:** Semantic conflicts expressed with different words (acknowledged limitation — requires LLM, probabilistic).

### Conflict scenarios

| Scenario | Resolution |
|----------|------------|
| Both add new patterns (different topics) | Auto-merge, no conflict |
| Both add pattern with same header | Structural conflict detection → `contested.md` |
| Both update same knowledge entry | Git merge conflict → manual resolution with context from both task docs |
| Both update conventions | Rare — conventions change infrequently. If conflict, team discusses |

## Same File Modified by Both Developers

If locks deny the dispatch (D-220), implementer cannot proceed until conflict is resolved.

If lock enforcement is bypassed (escape hatch) and both modify same file:
- This is handled by GIT (normal merge conflict)
- Moira's contribution: both tasks have full architecture.md and plan.md, giving merge reviewer full context
- Optional: `/moira resolve-conflict` spawns architect to analyze both changes and propose merge strategy

## Developer Identity (D-225)

Every task records developer identity for lock attribution, metrics, and stale detection:

- **Source:** `git config user.name` → `$USER` → `"unknown"` (fallback chain)
- **Written by:** `task-init.sh` at scaffold time (shell, deterministic)
- **Stored in:** `status.yaml` field `developer: "Alice"`, lock files (D-220)
- **Privacy:** Identity stays in gitignored state. Committed metrics use anonymous aggregates unless `developer_tracking: team` in `config.yaml`

## Developer Isolation Guarantees

1. Task state files are never shared between sessions
2. File conflicts handled by git merge — Moira provides architecture.md and plan.md for context (D-226)
3. Knowledge updates are append-only; structural conflicts detected deterministically (D-221)
4. Metrics are per-task (no cross-session interference)
5. Agent instructions are generated fresh per task
6. Developer identity recorded for metrics and team tracking (D-225)
