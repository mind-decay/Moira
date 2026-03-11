# Micro-Onboarding

## Principle: Show, Don't Tell. Interactive, Not Lecture.

Onboarding is:
- 3 minutes maximum
- Interactive (user does a real task)
- Skippable
- Shows by example, not lecture

## Trigger

First `/moira init` on any project.

## Flow

### Entry Point

```
/moira init

═══════════════════════════════════════════
  MOIRA — First time setup
═══════════════════════════════════════════
  Scanning project... done.

  Welcome! Moira orchestrates engineering tasks
  with predictable, high-quality results.

  ▸ start — 3-minute interactive walkthrough
  ▸ skip  — I'll figure it out
═══════════════════════════════════════════
```

### Step 1: Core Concept (30 sec)

```
═══════════════════════════════════════════
  HOW MOIRA WORKS
═══════════════════════════════════════════

  You describe a task → Moira orchestrates agents:

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

  /moira <task>      — do a task
  /moira continue    — resume interrupted work
  /moira status      — where am I?
  /moira knowledge   — what does the system know?
  /moira metrics     — how well is it working?

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

  That's Moira! Larger tasks have more steps
  and approval points.

  Try /moira with a bigger task when ready.
═══════════════════════════════════════════
```

### Skip Path

```
> skip

  Quick reference:
  /moira <task>  — execute a task
  /moira status  — check state
  /moira help    — detailed help

  Project configured. Ready to use.
```

## Re-Onboarding

If user wants to see onboarding again: `/moira help onboarding`
