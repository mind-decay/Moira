# Knowledge System

## Principle: Thinking Aid, Not Cache

Knowledge is not a cache of architectural decisions. It's a structured support system for correct reasoning. It helps agents make BETTER decisions, not FASTER ones.

## Three-Level Documentation

Every knowledge document exists in three forms:

| Level | Size | Purpose | Who reads |
|-------|------|---------|-----------|
| L0: Index | ~100-200 tokens | List of topics with one-liners | Explorer (stay unbiased) |
| L1: Summary | ~500-2000 tokens | Key facts for decision-making | Analyst, Planner, most agents |
| L2: Full | ~2000-10000 tokens | Complete info with examples | Architect (decisions), Implementer (conventions), Reviewer |

### Agent Knowledge Access Matrix

| Agent | project-model | conventions | decisions | patterns | quality-map | failures |
|-------|--------------|-------------|-----------|----------|-------------|----------|
| Classifier | L1 | — | — | — | — | — |
| Explorer | L0 | — | — | — | — | — |
| Analyst | L1 | — | L0 | — | — | L0 |
| Architect | L1 | L0 | L2 (full!) | L1 | L1 | L0 |
| Planner | L1 | L1 | L0 | L0 | L2 | — |
| Implementer | L0 | L2 (full!) | — | L1 | — | — |
| Reviewer | L1 | L2 (full!) | L1 | L1 | L1 | — |
| Tester | L0 | L1 | — | L0 | — | — |
| Reflector | L2 | L2 | L2 | L2 | L2 | L2 |
| Auditor | L2 | L2 | L2 | L2 | L2 | L2 |

**Authoritative source:** `src/global/core/knowledge-access-matrix.yaml`. This table is a summary. Write access is defined in the authoritative source.

**Note:** Package map access levels are a sub-dimension of project-model; see Package Map section below.

Architect reads full decisions — needs ALL precedents.
Implementer reads full conventions — needs exact HOW.
Explorer reads almost nothing — must be unbiased.

## Knowledge Components

### Project Model (knowledge/project-model/)

Not a file list. An understanding of the project:

```markdown
## Domain
What this project does, for whom, what problem it solves

## Architecture
Architecture type, key decisions, why this approach

## Data Flow
How data moves through the system

## Critical Paths
What cannot break, what is the core

## Boundaries
Where our code ends and external systems begin

## Pain Points
Known issues, technical debt, fragile areas
```

### Package Map (monorepo projects only)

When the project is a monorepo (detected at bootstrap via package.json `workspaces`, lerna.json, pnpm-workspace.yaml, or `packages/` directory pattern), bootstrap creates a package map as an extension of the project model.

```markdown
## Packages
| Package | Path | Role | Internal Dependencies |
|---------|------|------|----------------------|
| @ui/button | packages/ui/button | library | @ui/core |
| @ui/core | packages/ui/core | library | — |
| web-app | apps/web | application | @ui/button, @ui/core |
```

Stored at: `knowledge/project-model/package-map.md`
Access levels: Classifier uses L0 (package list only). Explorer uses L1 (packages + dependencies). Architect uses L1 for cross-package impact analysis.

Package map access is a sub-dimension of the `project-model` knowledge type. The access levels above apply specifically to `knowledge/project-model/package-map.md` within the agent's project-model access.

Package map is refreshed by Explorer during `/moira refresh` and updated organically when Explorer encounters new package relationships during tasks.

### Decisions Log (knowledge/decisions/)

```markdown
## [2024-01-15] Error handling pattern choice
CONTEXT: Need unified error handling in API
DECISION: Error boundary middleware + custom error classes
ALTERNATIVES REJECTED:
- Try-catch per handler (duplication)
- Global handler without types (loses context)
REASONING: Middleware = single point + typed errors enable client reaction
```

### Patterns (knowledge/patterns/)

Not "how to do X" but "when approach A works vs when it doesn't":

```markdown
## Pattern: Optimistic UI updates
WORKS WHEN: Simple CRUD, single user, low conflict probability
FAILS WHEN: Concurrent edits, complex validation, multi-step operations
EVIDENCE: Task-042 (success), Task-067 (failure — race condition)
```

### Failures (knowledge/failures/)

```markdown
## [079-v1] Cursor-based pagination rejected
APPROACH: Cursor-based with Prisma cursor API
REJECTED BECAUSE: Frontend DataTable requires offset + totalCount
LESSON: Check frontend component requirements before choosing pagination strategy
APPLIES TO: Any pagination task with existing UI components
```

### Quality Map (knowledge/quality-map/)

Assessment of existing code quality. See [quality.md](quality.md) for full quality map spec.

## Bootstrapping — Hybrid Approach

### Phase 0: Quick Scan (at /moira init, ~2-3 min)

4 parallel Explorer invocations with Layer 4 task-specific instructions (D-032):
1. **Explorer (tech scan)** → reads package.json, configs → stack.yaml
2. **Explorer (structure scan)** → directory tree, index files → project-model/summary.md
3. **Explorer (convention scan)** → linter configs, 5 sample files per dir → conventions.yaml
4. **Explorer (pattern scan)** → 3-5 representative files per layer → patterns.yaml + quality-map/summary.md

Result: System ready with BASIC knowledge. Quality map marked "preliminary."

### Phase 1: Deep Scan (background, during first tasks)

Non-blocking deep analysis:
- Full architecture map (all layers, all connections)
- Dependency analysis (internal + external)
- Test coverage assessment
- Performance hotspot detection
- Security surface scan
- Full quality map generation

User gets notification when complete:
```
ℹ Deep scan complete. Knowledge base updated.
  12 patterns documented, 3 quality concerns found.
  Run /moira knowledge to review.
```

### Phase 2: Organic Growth (ongoing)

Every task adds knowledge:
- Explorer findings → update project-model
- Architect decisions → add to decisions log
- Reviewer findings → update quality-map
- Reflector insights → update patterns/failures

### Consistency Validation

New knowledge is checked against existing:

1. If new finding CONFIRMS existing → update freshness marker
2. If new finding EXTENDS existing → merge with clarification
3. If new finding CONFLICTS → flag for Explorer verification

## Freshness System

Every fact is tagged:

```markdown
<!-- moira:freshness task-078 2024-01-20 -->
## API Error Handling Pattern
...
```

Freshness categories:
- **Fresh** (confirmed < 10 tasks ago): trusted
- **Aging** (10-20 tasks ago): still used but may be outdated
- **Stale** (> 20 tasks ago): needs verification

Stale entries are flagged by Audit and verified by Explorer at next `/moira refresh`.

## Size Management — Archival Rotation

Knowledge files grow. After threshold:

```
decisions/
├── full.md              # Last 20 decisions (active)
├── archive/
│   ├── batch-001.md     # Decisions 1-20
│   ├── batch-002.md     # Decisions 21-40
│   └── ...
└── summary.md           # ALL decisions in summary form (always current)
```

Architect normally reads summary.md. For specific old decision context → Explorer fetches from archive.

## MCP Knowledge Caching

When Reflector notices same MCP call made 3+ times:

```
Observation: context7:query-docs("react-datepicker") called in tasks: 045, 051, 058, 062
Recommendation: Cache essential API reference in knowledge/libraries/react-datepicker.md
Estimated savings: ~14k tokens per task

▸ cache  — create knowledge entry
▸ ignore — library changes too often, always fetch fresh
```
