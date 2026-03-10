# Tweak & Redo — Post-Completion Modifications

## Available After Task Completion

```
✓ COMPLETE — Task 079: Add pagination

▸ done   — accept changes
▸ tweak  — targeted modification
▸ redo   — rollback and re-execute
▸ diff   — show changes first
```

## Tweak: Targeted Modification

User describes what needs changing. System makes minimal modifications.

### Flow

```
> tweak
> Change default page size from 20 to 50 and add sortBy parameter

═══════════════════════════════════════════
  TWEAK ANALYSIS
═══════════════════════════════════════════

  Affects:
  ├─ src/types/api.ts — add sortBy to PaginationParams
  ├─ src/services/product.ts — add orderBy to query
  └─ src/api/products.ts — parse sortBy from params

  Does NOT affect:
  └─ tests (will need update after)

  Scope check: within original task scope ✅

  ▸ proceed — apply tweak
  ▸ clarify — adjust description
  ▸ cancel  — keep current result
═══════════════════════════════════════════
```

### Tweak Pipeline

```
User description
  ├─ Quick Explorer → identify affected files
  ├─ Scope check → within original task?
  │   ├─ YES → proceed
  │   └─ NO → "This changes architecture. Recommend separate task."
  │           ▸ force-tweak / new-task
  ├─ Implementer → targeted changes
  │   (receives: original plan + current state + tweak delta + scope limits)
  ├─ Reviewer → reviews ONLY changed lines + integration points
  ├─ Tester → updates affected tests
  └─ [GATE: user reviews]
```

### Tweak Rules

- Implementer changes ONLY what tweak describes
- Implementer has original plan context (understands what was already done)
- Reviewer focuses on integration (does tweak break existing work?)
- If tweak requires architecture change → recommend separate task

## Redo: Full Rollback

User decides the approach was wrong. Roll back and try differently.

### Flow

```
> redo

═══════════════════════════════════════════
  REDO — Full Rollback
═══════════════════════════════════════════

  This will:
  ├─ Revert ALL code changes from this task
  ├─ Preserve exploration and analysis results
  └─ Re-enter pipeline at your chosen point

  Re-enter at:
  ▸ architecture — change approach entirely
  ▸ plan         — keep architecture, change execution
  ▸ implement    — keep plan, re-implement from scratch

  What prompted the redo?
  > Cursor pagination doesn't work with our DataTable component
═══════════════════════════════════════════
```

### Redo Pipeline

```
User chooses re-entry point + provides reason
  │
  ├─ Git revert of task changes
  │
  ├─ Archive previous attempt:
  │   architecture-v1.md → marked "rejected: <reason>"
  │   plan-v1.md → archived
  │   impl results → discarded (code reverted)
  │
  ├─ Re-enter pipeline at chosen step
  │   Agent receives:
  │   - Original requirements (unchanged)
  │   - REJECTED approach with reason
  │   - Updated constraints from user
  │
  └─ Pipeline continues normally
```

### Redo Knowledge Capture

Every redo is captured in knowledge/failures/:

```markdown
## [079-v1] Cursor-based pagination rejected
CONTEXT: Products API pagination
APPROACH: Cursor-based with Prisma cursor API
REJECTED BECAUSE: Frontend DataTable requires offset + totalCount
LESSON: Check frontend component requirements before choosing pagination strategy
APPLIES TO: Any pagination task with existing UI components
```

This prevents the system from making the same mistake in future tasks.

### Re-entry Points

| Point | What's preserved | What's re-done |
|-------|-----------------|----------------|
| architecture | exploration + analysis | architecture + plan + implementation |
| plan | exploration + analysis + architecture | plan + implementation |
| implement | exploration + analysis + architecture + plan | implementation only |
