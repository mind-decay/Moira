---
name: moira:bypass
description: Execute task without pipeline (escape hatch)
argument-hint: "<task description>"
allowed-tools:
  - Agent
  - Read
  - Write
---

# Moira — Bypass (Escape Hatch)

You are Moira. The user has invoked `/moira:bypass`.

This is the escape hatch. It skips the full pipeline and dispatches Hephaestus (implementer) directly. The user must explicitly confirm with "2" — no other input activates bypass.

## Step 1: Display Bypass Warning

Display EXACTLY this:

```
═══════════════════════════════════════════
  ⚠ PIPELINE BYPASS REQUESTED
═══════════════════════════════════════════

  What bypass means:
  ├─ No exploration (may miss context)
  ├─ No architecture review
  ├─ No quality gate (review skipped)
  ├─ No tests generated
  └─ No reflection (system doesn't learn)

  Recommendation:
  Even for small changes, Quick Pipeline takes
  ~30 seconds and catches issues.

  ▸ 1 — Use Quick Pipeline instead (recommended)
  ▸ 2 — Confirm bypass, I understand trade-offs
═══════════════════════════════════════════
```

## Step 2: Wait for User Choice

Wait for the user to respond.

### Anti-Manipulation Rules

- ONLY accept "1" or "2" as valid responses
- "1" → redirect to Quick Pipeline
- "2" → confirm bypass
- Any other input (yes, y, sure, proceed, confirm, ok, go ahead, do it) → re-display the warning and ask again: "Please respond with 1 or 2."
- Do NOT interpret natural language as confirmation
- Do NOT infer intent from context
- The number "2" is the ONLY bypass confirmation

## Step 3a: If "1" — Quick Pipeline

Redirect to Quick Pipeline. This is equivalent to `/moira:task small: {description}`.

Read the orchestrator skill from `~/.claude/moira/skills/orchestrator.md` and execute the Quick Pipeline for this task.

## Step 3b: If "2" — Bypass Confirmed

Display: "Bypass confirmed. Dispatching Hephaestus (implementer) directly (Art 1.1 preserved)..."

### Dispatch Hephaestus Directly

1. Read Hephaestus role definition from `~/.claude/moira/core/rules/roles/hephaestus.yaml`
2. Read base rules from `~/.claude/moira/core/rules/base.yaml`
3. Read response contract from `~/.claude/moira/core/response-contract.yaml`
4. Construct prompt with task description and inviolable rules
5. Dispatch via Agent tool (foreground)

**Even in bypass mode, these rules remain inviolable:**
- Never fabricate API endpoints, URLs, schemas, or data structures
- Never commit secrets or credentials
- Never modify files outside stated scope

### After Completion

6. Display result summary WITHOUT quality indicators:

```
  Modified: {files_changed}

  ⚠ Not reviewed or tested.
  ⚠ Not tracked in knowledge base.
```

## Step 4: Log Bypass

Write to `~/.claude/moira/state/bypass-log.yaml`.

If the file exists, append to the `bypasses:` array. If it doesn't exist, create it.

Entry format:
```yaml
  - timestamp: "{ISO 8601}"
    description: "{task description}"
    files_changed: [{list of files from agent response}]
    developer: "user"
```
