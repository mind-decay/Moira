# Checkpoint & Resume System

## Problem

Long tasks (large, epic) may exceed orchestrator context or require multiple sessions. Quality must not degrade on resume.

## Execution Manifest

Every task maintains a manifest tracking full execution state:

```yaml
# .claude/moira/state/tasks/078/manifest.yaml

task:
  id: "078"
  description: "Add role-based access control to API"
  classified_as: large
  pipeline: full

execution_log:
  - step: classify
    status: done
    timestamp: "2024-01-15T10:30:00Z"
    result_file: classification.md

  - step: explore
    status: done
    timestamp: "2024-01-15T10:31:00Z"
    result_file: exploration.md
    key_findings:
      - "Auth currently uses simple JWT with no role claim"
      - "14 API endpoints, 6 need role protection"
      - "Middleware chain: cors → auth → validate → handler"

  - step: analyze
    status: done
    result_file: requirements.md
    key_decisions:
      - "3 roles: admin, editor, viewer"
      - "Role hierarchy: admin > editor > viewer"

  - step: architect
    status: done
    result_file: architecture.md
    gate: approved
    architecture_summary:
      - "Role stored in JWT claims"
      - "Middleware-based check per route"

  - step: plan
    status: done
    result_file: plan.md
    gate: approved
    total_phases: 3
    total_batches: 5

  - step: implement_phase_1
    status: done
    batches: [A, B]
    changes_made:
      - "src/types/roles.ts — created"
      - "src/utils/role-check.ts — created"
      - "src/middleware/authorize.ts — created"

  - step: implement_phase_2
    status: in_progress
    batches:
      C: done
      D: pending
      E: pending

resume_context: |
  Task: adding RBAC to API. Architecture: role in JWT,
  middleware authorization, 3-role hierarchy.
  Phase 1 complete (types + utils + middleware).
  Phase 2 in progress: Batch C done (user endpoints),
  D and E pending (content + admin endpoints).
  Continue with Batch D.
```

### Key design decisions:

- `key_findings` and `key_decisions` capture essential context in compressed form
- `changes_made` tracks what was actually modified (for validation)
- `resume_context` is a human-readable summary written specifically for a new orchestrator session
- Orchestrator on resume loads ONLY: resume_context + plan.md + manifest.yaml

## Checkpoint Triggers

| Trigger | Action |
|---------|--------|
| Phase completion (large tasks) | Auto-checkpoint |
| Sub-task completion (epics) | Auto-checkpoint |
| Orchestrator context > 60% | Recommend checkpoint |
| User requests | Manual checkpoint |
| Session end (unexpected) | State is already persisted in manifest |

## Resume Flow (/moira continue)

```
1. Read manifest.yaml
2. Read resume_context
3. VALIDATE (critical for quality):
   a. Are completed step artifacts present on disk?
   b. Do changed files match what manifest says?
      (Quick Explorer check on specific files)
   c. Has anyone modified files since last session?
      (git diff check)

4. IF all consistent → continue from exact point

5. IF inconsistency detected:
   ═══════════════════════════════════════════
    ⚠ RESUME INCONSISTENCY
   ═══════════════════════════════════════════
    Manifest says src/middleware/authorize.ts
    was created in Phase 1, but file doesn't exist.

    Possible causes:
    - Manual changes between sessions
    - Git operations (stash, checkout, reset)

    ▸ re-explore — rescan and update manifest
    ▸ re-plan    — go back to planning
    ▸ explain    — tell system what happened
   ═══════════════════════════════════════════

6. IF files modified externally:
   ═══════════════════════════════════════════
    ⚠ EXTERNAL CHANGES DETECTED
   ═══════════════════════════════════════════
    Files modified since last session:
    - src/middleware/authorize.ts (manual edit)
    - src/types/roles.ts (manual edit)

    ▸ accept   — incorporate changes, continue
    ▸ revert   — undo external changes, continue as planned
    ▸ re-plan  — re-plan remaining work with new state
   ═══════════════════════════════════════════
```

## Quality Preservation on Resume

### Why quality might degrade:
1. New orchestrator has no memory of previous reasoning
2. Context of WHY decisions were made is lost
3. Subtle dependencies between steps might be forgotten

### How we prevent it:
1. **resume_context** captures essential reasoning, not just state
2. **key_findings** and **key_decisions** preserve critical context per step
3. **Validation step** catches any reality drift
4. **plan.md** contains full execution plan with contracts and dependencies
5. Agents receive the SAME assembled instructions (from files, not memory)

### Quality check after resume:
After first post-resume step completes, Reviewer does a quick integration check:
- Does the new work integrate correctly with pre-resume work?
- Are contracts maintained?
- Is code style consistent?

If issues found → flag before continuing further steps.

## Epic Task Checkpointing

For epics, each sub-task is fully independent:

```yaml
# .claude/moira/state/queue.yaml

epic:
  id: "E-012"
  description: "Implement user management system"
  tasks:
    - id: "078"
      description: "Add roles and permissions types"
      size: medium
      status: completed
      branch: "feature/user-mgmt-types"

    - id: "079"
      description: "Add RBAC middleware"
      size: large
      status: in_progress  # ← resume from here
      branch: "feature/user-mgmt-rbac"

    - id: "080"
      description: "Add user management UI"
      size: large
      status: pending
      depends_on: [078, 079]

  integration_verified: false
```

`/moira continue` on an epic:
1. Reads queue.yaml
2. Finds first non-completed task
3. If task is in_progress → resumes it
4. If task is pending → starts it (if dependencies met)
5. Shows epic progress overview
