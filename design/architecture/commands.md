# Command Reference

## Primary Commands (daily use)

### `/forge init`
Set up Forge for the current project.

- Scans project: stack, structure, conventions, patterns
- Generates project-specific rules and agents
- Creates knowledge base (quick scan)
- Triggers deep scan in background on first task
- Offers micro-onboarding for first-time users

### `/forge <task description>`
Execute a task through the appropriate pipeline.

Examples:
```
/forge Add pagination to the products API endpoint
/forge Fix typo "Sumbit" → "Submit" in login page
/forge Refactor auth system to support OAuth2
```

Size hint (optional):
```
/forge small: fix button color on settings page
/forge large: add role-based access control to all API endpoints
```

### `/forge continue`
Resume an interrupted task from the last checkpoint.

- Reads manifest.yaml for task state
- Validates completed steps still match reality
- Continues from exact interruption point
- If inconsistency detected → offers re-explore or re-plan

### `/forge status`
Show current system state.

- Active task and progress
- Branch and lock information
- Recent completed tasks
- System health (orchestrator context, knowledge freshness)

### `/forge knowledge`
View and manage the knowledge base.

Subcommands:
```
/forge knowledge               — overview of all knowledge
/forge knowledge patterns      — view patterns
/forge knowledge decisions     — view decision log
/forge knowledge quality-map   — view quality assessments
/forge knowledge edit          — open knowledge for manual editing
```

### `/forge metrics`
View performance metrics dashboard.

Subcommands:
```
/forge metrics                 — full dashboard (last 30 days)
/forge metrics details <section> — drill into section
/forge metrics compare         — compare with previous period
/forge metrics export          — export as markdown
```

## Secondary Commands

### `/forge audit`
Run system health audit.

Subcommands:
```
/forge audit                   — full audit (all 5 domains)
/forge audit rules             — rules consistency
/forge audit knowledge         — knowledge freshness and accuracy
/forge audit agents            — agent performance analysis
/forge audit config            — MCP, budgets, hooks
/forge audit consistency       — cross-component verification
```

### `/forge refresh`
Update project model and knowledge base without full re-init.

- Re-scans project structure and stack
- Updates project-model
- Checks convention drift
- Does NOT regenerate agents or rules (use `/forge init --refresh` for that)

### `/forge upgrade`
Upgrade Global Layer to latest version.

- Shows what changed in core
- Runs compatibility check against project config
- Applies compatible changes
- Flags conflicts for manual resolution
- Post-upgrade validation

### `/forge bypass: <description>`
Execute task without pipeline (escape hatch).

- Requires explicit confirmation (option "2", not "yes")
- Shows trade-offs before confirmation
- Recommends Quick Pipeline instead
- Logged in bypass-log.yaml for audit
- Cannot be triggered by prompt manipulation

### `/forge help`
Show help and documentation.

Subcommands:
```
/forge help                    — quick reference card
/forge help <command>          — detailed help for command
/forge help concepts           — how Forge works
/forge help agents             — what each agent does
/forge help pipelines          — how tasks flow through system
/forge help troubleshooting    — common issues and solutions
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
Level 1 (/forge details): Full reasoning and documents
Level 2 (/forge inspect <step>): Raw agent output files
Level 3 (/forge debug): System internals (budgets, rules, MCP calls, timing)
```

## Shorthand for Power Users

```
/forge k patterns        → /forge knowledge patterns
/forge k decisions       → /forge knowledge decisions
/forge m                 → /forge metrics
/forge m quality         → /forge metrics details quality
/forge s                 → /forge status
/forge a                 → /forge audit
```
