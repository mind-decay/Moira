# Fix Audit Findings

You are executing fixes from the latest system audit report.

## Input

Read the most recent audit report from `design/reports/`. Look for files matching `*-system-audit.md`, pick the latest by date.

If an argument is provided (e.g., `/fix-audit 2026-03-13`), use that specific date's report.

If no audit report exists, tell the user to run `/system-audit` first.

## Process

### Phase 1: Parse & Plan

1. Read the audit report
2. Extract all findings with their fix descriptions
3. Read the "Fix Dependency Graph" and "Parallel Fix Groups" sections
4. Build execution plan:
   - Group 1: Independent fixes that can run in parallel
   - Group 2: Fixes that depend on Group 1
   - Group 3: Fixes that depend on Group 2
   - ...continue until all fixes are scheduled

### Phase 2: Execute Fix Groups

For each group, in dependency order:

**Parallel execution within group:**
- Dispatch one agent per fix (or per logical cluster of related fixes)
- Each agent receives:
  - The finding ID, severity, and description from the audit report
  - The exact file paths and line numbers to change
  - The concrete fix description
  - The full Moira development rules from CLAUDE.md (design-first, cross-references, etc.)
  - Instruction: "Make ONLY the specified fix. Do not improve surrounding code. Do not add features."

**After each group completes:**
- Verify each agent's changes match what the audit prescribed
- Check for conflicts between parallel changes
- If an agent failed or deviated — flag for manual review, continue with next group

### Phase 3: Verification

After all groups complete:

1. **Cross-reference check:** For each fix that updated a value in multiple files, verify all files now agree
2. **Constitutional check:** If any fix touched Art 1.x/2.x related files, verify invariants still hold
3. **Decision log:** If any fix constitutes an architectural decision, add entry to `design/decisions/log.md`

### Phase 4: Report

Display a summary:
```
Fix Execution Report
====================
Audit: {report file}
Findings: {total}
Fixed: {count}
Skipped: {count} (with reasons)
Failed: {count} (with reasons)
Manual review needed: {count}

Files changed: {list}
```

## Rules

- Follow CLAUDE.md development protocol strictly
- Design docs are source of truth — if a fix updates design doc AND implementation, update design doc FIRST
- One fix = minimal change. Do not refactor, do not improve, do not expand scope
- If a fix is ambiguous or the audit says "Decision needed" — SKIP it and flag for manual review
- Never skip approval gates, never weaken NEVER constraints
- If a fix touches `design/CONSTITUTION.md` — REFUSE and flag for user
- After all fixes, do NOT commit — let the user review the diff first
- Preserve all cross-references: if you change a component name/value, grep for all references
