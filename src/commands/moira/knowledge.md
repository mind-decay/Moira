---
name: moira:knowledge
description: View and manage the Moira knowledge base
argument-hint: "[patterns|decisions|quality-map|conventions|project-model|failures|edit]"
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
---

# /moira:knowledge — Knowledge Base

View and manage the project's knowledge base.

## Setup

- **MOIRA_HOME:** `~/.claude/moira/`
- **Knowledge dir:** `.claude/moira/knowledge/`
- **Knowledge access matrix:** `~/.claude/moira/core/knowledge-access-matrix.yaml`

## Step 1: Verify Initialization

Read `.claude/moira/config.yaml`.

If not found, display and stop:
```
Moira is not initialized for this project.
Run /moira:init first.
```

## Step 2: Parse Argument

| Argument | Action |
|----------|--------|
| _(none)_ | Show overview of all knowledge types |
| `patterns` | Show patterns knowledge (L1 summary) |
| `decisions` | Show decisions knowledge (L1 summary) |
| `quality-map` | Show quality map (L1 summary) |
| `conventions` | Show conventions knowledge (L1 summary) |
| `project-model` | Show project model (L1 summary) |
| `failures` | Show failures knowledge (L1 summary) |
| `edit` | Instructions for manual editing |

## Step 3: Overview (no argument)

For each knowledge type, read the directory `.claude/moira/knowledge/{type}/` and report:

**Knowledge types to check:**
- `project-model` — domain, architecture, data flow, critical paths
- `conventions` — coding standards, naming, imports
- `decisions` — architectural decisions with context
- `patterns` — what works vs what doesn't (with evidence)
- `failures` — rejected approaches, lessons learned
- `quality-map` — code quality assessment per area

For each type:
1. Check if directory exists
2. If exists: list which levels are present (index.md=L0, summary.md=L1, full.md=L2)
3. Count archive entries if `archive/` subdirectory exists
4. Read freshness data: look for `<!-- moira:freshness ... -->` markers in files

Display:

```
═══════════════════════════════════════════
  MOIRA — Knowledge Base
═══════════════════════════════════════════

  Project: {project.name}
  Stack:   {project.stack}

─── Knowledge Types ──────────────────────

  project-model   L0 L1 L2   {freshness}
  conventions     L0 L1 L2   {freshness}
  decisions       L0 L1 L2   {freshness}   {archive_count} archived
  patterns        L0 L1 L2   {freshness}   {archive_count} archived
  failures        L0 L1 --   {freshness}
  quality-map     -- L1 L2   {freshness}

  Levels present shown as L0/L1/L2, missing shown as --

─── Agent Access Matrix ──────────────────

  apollo       project-model(L1)
  hermes       project-model(L0)
  athena       project-model(L1) decisions(L0) failures(L0)
  metis        project-model(L1) conventions(L0) decisions(L2) patterns(L1) quality-map(L1) failures(L0)
  daedalus     project-model(L1) conventions(L1) decisions(L0) patterns(L0) quality-map(L2) libraries(L0)
  hephaestus   project-model(L0) conventions(L2) patterns(L1) libraries(L1)
  themis       project-model(L1) conventions(L2) decisions(L1) patterns(L1) quality-map(L1)
  aletheia     project-model(L0) conventions(L1) patterns(L0)
  mnemosyne    ALL(L2)
  argus        ALL(L2) READ-ONLY

─── Freshness ────────────────────────────

  Confidence ranges: >70 trusted | 30-70 usable | <=30 needs-verification

  {For each type with freshness data:}
  {type}: confidence {score}% ({category})

═══════════════════════════════════════════

  View details: /moira:knowledge <type>
  Edit manually: /moira:knowledge edit
```

## Step 4: Type Detail (with argument)

When a specific knowledge type is requested (e.g., `patterns`, `decisions`):

1. Read `.claude/moira/knowledge/{type}/summary.md` (L1 level)
2. If L1 doesn't exist, try `index.md` (L0 level)
3. If nothing exists, report "No {type} knowledge collected yet."

Display:

```
═══════════════════════════════════════════
  MOIRA — Knowledge: {type}
═══════════════════════════════════════════

  Level: L1 (Summary)
  Freshness: {score}% ({category})
  Last verified: {task_id} on {date}

───────────────────────────────────────────

{content of summary.md or index.md}

───────────────────────────────────────────

  {If archive/ exists:}
  Archive: {count} entries
  View full (L2): Read .claude/moira/knowledge/{type}/full.md
  View archive: Read .claude/moira/knowledge/{type}/archive/

═══════════════════════════════════════════
```

## Step 5: Edit Mode

When `edit` is provided:

Display instructions:
```
═══════════════════════════════════════════
  MOIRA — Knowledge Edit
═══════════════════════════════════════════

  Knowledge files are markdown. You can edit them directly.

  Locations:
  .claude/moira/knowledge/
  ├── project-model/
  │   ├── index.md       (L0 — topic list)
  │   ├── summary.md     (L1 — key facts)
  │   └── full.md        (L2 — complete)
  ├── conventions/
  │   ├── index.md
  │   ├── summary.md
  │   └── full.md
  ├── decisions/
  │   ├── index.md
  │   ├── summary.md
  │   ├── full.md
  │   └── archive/       (rotated entries)
  ├── patterns/
  │   ├── index.md
  │   ├── summary.md
  │   ├── full.md
  │   └── archive/
  ├── failures/
  │   ├── index.md
  │   └── summary.md
  └── quality-map/
      ├── summary.md
      └── full.md

  Guidelines:
  - Keep L0 under 200 tokens (topic list with one-liners)
  - Keep L1 under 2000 tokens (key facts for decisions)
  - L2 can be up to 10000 tokens (full detail with examples)
  - Add freshness markers: <!-- moira:freshness {task_id} {date} λ={rate} -->
  - After editing, run /moira:audit knowledge to verify consistency

═══════════════════════════════════════════
```

## Notes

- This command is read-only (except `edit` which just shows instructions).
- Freshness scoring uses exponential decay with per-type λ values:
  - conventions: 0.02, patterns: 0.05, project_model: 0.08
  - decisions: 0.01, failures: 0.03, quality_map: 0.07
- If freshness computation fails, show "unknown" rather than crashing.
- The agent access matrix is read from the canonical source at `~/.claude/moira/core/knowledge-access-matrix.yaml`. If unavailable, display the hardcoded summary above.
