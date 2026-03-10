# Micro-Onboarding

## Principle: Show, Don't Tell. Interactive, Not Lecture.

Onboarding is:
- 3 minutes maximum
- Interactive (user does a real task)
- Skippable
- Shows by example, not lecture

## Trigger

First `/forge init` on any project.

## Flow

### Entry Point

```
/forge init

═══════════════════════════════════════════
  FORGE — First time setup
═══════════════════════════════════════════
  Scanning project... done.

  Welcome! Forge orchestrates engineering tasks
  with predictable, high-quality results.

  ▸ start — 3-minute interactive walkthrough
  ▸ skip  — I'll figure it out
═══════════════════════════════════════════
```

### Step 1: Core Concept (30 sec)

```
═══════════════════════════════════════════
  HOW FORGE WORKS
═══════════════════════════════════════════

  You describe a task → Forge orchestrates agents:

  You ──→ Classify ──→ Analyze ──→ Plan ──→ Build ──→ Review
             │           │          │         │         │
          "how big?"  "what's    "how?"   "write    "check
                       needed?"            code"    quality"

  You approve at key checkpoints (▸ prompts).
  You never need to manage agents directly.

  ▸ next
═══════════════════════════════════════════
```

### Step 2: Commands (30 sec)

```
═══════════════════════════════════════════
  COMMANDS — just 5 to remember
═══════════════════════════════════════════

  /forge <task>      — do a task
  /forge continue    — resume interrupted work
  /forge status      — where am I?
  /forge knowledge   — what does the system know?
  /forge metrics     — how well is it working?

  Everything else happens through prompts.

  ▸ next — let's try a real task
═══════════════════════════════════════════
```

### Step 3: Live Example (2 min)

```
═══════════════════════════════════════════
  LET'S TRY IT
═══════════════════════════════════════════

  Give me a small task for your project.
  Something simple: fix text, rename variable,
  add a CSS class.

  You'll review everything before it's applied.

  > _
═══════════════════════════════════════════
```

System executes real task through Quick Pipeline with annotations:

```
  Task: Fix typo "Sumbit" → "Submit" in login page

  ┌ STEP 1: Classification ─────────────────┐
  │ Classified as SMALL (1 file, simple fix) │
  │ Using simplified pipeline.               │
  └──────────────────────────────────────────┘

  ┌ STEP 2: Exploration ────────────────────┐
  │ Explorer found the typo at:              │
  │ src/components/auth/LoginForm.tsx:42      │
  └──────────────────────────────────────────┘

  ┌ STEP 3: Implementation + Review ────────┐
  │ Implementer fixed it. Reviewer verified. │
  └──────────────────────────────────────────┘

  Result:
  src/components/auth/LoginForm.tsx:42
    "Sumbit" → "Submit"

  ▸ done — accept (this is an approval gate!)
  ▸ undo — revert

  That's Forge! Larger tasks have more steps
  and approval points.

  Try /forge with a bigger task when ready.
═══════════════════════════════════════════
```

### Skip Path

```
> skip

  Quick reference:
  /forge <task>  — execute a task
  /forge status  — check state
  /forge help    — detailed help

  Project configured. Ready to use.
```

## Re-Onboarding

If user wants to see onboarding again: `/forge help onboarding`
