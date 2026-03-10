# Multi-Developer System

## Problem

Multiple engineers on same project, each with their own Claude sessions:
1. Both read shared knowledge base
2. Both may update knowledge
3. Both may modify same files
4. Task state must not conflict

## Solution: Branch-Scoped State + Shared Knowledge

```
.claude/forge/
├── knowledge/     ← SHARED (git-tracked, merges with PRs)
├── config/        ← SHARED (git-tracked)
├── core/          ← SHARED (git-tracked)
├── project/       ← SHARED (git-tracked)
│
├── state/         ← BRANCH-SCOPED
│   ├── .gitignore ← ignores task state, keeps structure
│   ├── locks.yaml ← file reservation system
│   └── tasks/     ← per-task, per-branch isolation
│
├── metrics/       ← SHARED (git-tracked, append-friendly)
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

## File Lock System

```yaml
# .claude/forge/state/locks.yaml

active_tasks:
  - id: "078"
    branch: "feature/rbac"
    developer: "alice"
    files_reserved:
      - "src/middleware/auth.ts"
      - "src/middleware/authorize.ts"
    started: "2024-01-15T10:30:00Z"

  - id: "079"
    branch: "feature/search"
    developer: "bob"
    files_reserved:
      - "src/services/search.ts"
    started: "2024-01-15T11:00:00Z"
```

### Lock Checking

Planner checks locks before creating plan:

```
Plan requires: src/middleware/auth.ts
Lock found: reserved by Task 078 (Alice, feature/rbac)

⚠ FILE CONFLICT
▸ wait    — defer this file until Task 078 merges
▸ branch  — work against feature/rbac branch
▸ isolate — write to separate file, merge later
▸ proceed — ignore lock (may cause merge conflicts)
```

### Lock Lifecycle

1. Created: when Planner identifies files to modify
2. Active: during task execution
3. Released: when task is completed (done/abort)
4. Stale detection: audit checks for old locks on merged/deleted branches

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

Both sections coexist. No merge conflict. If semantic conflict exists, Reflector catches it at next task.

### Conflict scenarios

| Scenario | Resolution |
|----------|------------|
| Both add new patterns (different topics) | Auto-merge, no conflict |
| Both update same knowledge entry | Git merge conflict → manual resolution with context from both task docs |
| Both update conventions | Rare — conventions change infrequently. If conflict, team discusses |

## Same File Modified by Both Developers

If locks are ignored and both modify same file:
- This is handled by GIT (normal merge conflict)
- Forge's contribution: both tasks have full architecture.md and plan.md, giving merge reviewer full context
- Optional: `/forge resolve-conflict` spawns architect to analyze both changes and propose merge strategy

## Developer Isolation Guarantees

1. Task state files are never shared between sessions
2. Lock system prevents unintentional overlap
3. Knowledge updates are append-only during task execution
4. Metrics are per-task (no cross-session interference)
5. Agent instructions are generated fresh per task
