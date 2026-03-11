# Command Reference

## Primary Commands (daily use)

### `/moira init`
Set up Moira for the current project.

- Scans project: stack, structure, conventions, patterns
- Generates project-specific rules and agents
- Creates knowledge base (quick scan)
- Triggers deep scan in background on first task
- Offers micro-onboarding for first-time users

### `/moira <task description>`
Execute a task through the appropriate pipeline.

Examples:
```
/moira Add pagination to the products API endpoint
/moira Fix typo "Sumbit" → "Submit" in login page
/moira Refactor auth system to support OAuth2
```

Size hint (optional):
```
/moira small: fix button color on settings page
/moira large: add role-based access control to all API endpoints
```

### `/moira continue`
Resume an interrupted task from the last checkpoint.

- Reads manifest.yaml for task state
- Validates completed steps still match reality
- Continues from exact interruption point
- If inconsistency detected → offers re-explore or re-plan

### `/moira status`
Show current system state.

- Active task and progress
- Branch and lock information
- Recent completed tasks
- System health (orchestrator context, knowledge freshness)

### `/moira knowledge`
View and manage the knowledge base.

Subcommands:
```
/moira knowledge               — overview of all knowledge
/moira knowledge patterns      — view patterns
/moira knowledge decisions     — view decision log
/moira knowledge quality-map   — view quality assessments
/moira knowledge edit          — open knowledge for manual editing
```

### `/moira metrics`
View performance metrics dashboard.

Subcommands:
```
/moira metrics                 — full dashboard (last 30 days)
/moira metrics details <section> — drill into section
/moira metrics compare         — compare with previous period
/moira metrics export          — export as markdown
```

## Secondary Commands

### `/moira audit`
Run system health audit.

Subcommands:
```
/moira audit                   — full audit (all 5 domains)
/moira audit rules             — rules consistency
/moira audit knowledge         — knowledge freshness and accuracy
/moira audit agents            — agent performance analysis
/moira audit config            — MCP, budgets, hooks
/moira audit consistency       — cross-component verification
```

### `/moira refresh`
Update project model and knowledge base without full re-init.

- Re-scans project structure and stack
- Updates project-model
- Checks convention drift
- Does NOT regenerate agents or rules (use `/moira init --refresh` for that)

### `/moira upgrade`
Upgrade Global Layer to latest version.

- Shows what changed in core
- Runs compatibility check against project config
- Applies compatible changes
- Flags conflicts for manual resolution
- Post-upgrade validation

### `/moira bypass: <description>`
Execute task without pipeline (escape hatch).

- Requires explicit confirmation (option "2", not "yes")
- Shows trade-offs before confirmation
- Recommends Quick Pipeline instead
- Logged in bypass-log.yaml for audit
- Cannot be triggered by prompt manipulation

### `/moira help`
Show help and documentation.

Subcommands:
```
/moira help                    — quick reference card
/moira help <command>          — detailed help for command
/moira help concepts           — how Moira works
/moira help agents             — what each agent does
/moira help pipelines          — how tasks flow through system
/moira help troubleshooting    — common issues and solutions
```

## In-Pipeline Actions

These are available at gates and completion:

### At Gates
```
▸ proceed   — approve and continue
▸ details   — show full document
▸ modify    — provide feedback for revision
▸ abort     — cancel task
```

### At Completion
```
▸ done      — accept all changes
▸ tweak     — targeted modification (describe what to change)
▸ redo      — full rollback (choose re-entry point: architecture/plan/implement)
▸ diff      — show full git diff
▸ test      — run full test suite
```

### At Error/Block
```
▸ answer    — provide missing information
▸ point     — point to file/doc with answer
▸ skip      — skip step (mark as TODO)
▸ abort     — stop execution
```

## Progressive Disclosure

```
Level 0 (default): Status + summary + action options
Level 1 (/moira details): Full reasoning and documents
Level 2 (/moira inspect <step>): Raw agent output files
Level 3 (/moira debug): System internals (budgets, rules, MCP calls, timing)
```

## Shorthand for Power Users

```
/moira k patterns        → /moira knowledge patterns
/moira k decisions       → /moira knowledge decisions
/moira m                 → /moira metrics
/moira m quality         → /moira metrics details quality
/moira s                 → /moira status
/moira a                 → /moira audit
```
