# Agent Dispatch Module

Reference: `design/architecture/agents.md` (Agent Response Contract, Spawning Strategy), `design/architecture/rules.md` (Rule Assembly)

This skill defines how the orchestrator constructs agent prompts, dispatches agents, and processes their responses.

---

## Prompt Construction

### Pre-assembled Instructions (Primary Path)

When dispatching a post-planning agent (any agent after Daedalus has run), check for a pre-assembled instruction file:

1. Check path: `~/.claude/moira/state/tasks/{task_id}/instructions/{agent_name}.md`
2. If file exists and is non-empty:
   - Read the file contents
   - Use directly as the agent prompt (the file IS the complete prompt)
   - Skip simplified assembly -- the file contains all rules, knowledge, and context
3. If file does not exist:
   - Fall back to simplified assembly (below)

Instruction files are written by Daedalus (planner) during the planning step. They contain L1-L4 merged rules, authorized knowledge, quality checklist, task context, and output path.

### Simplified Assembly (Fallback)

Used for:
- Pre-planning agents: Apollo (classifier), Hermes (explorer), Athena (analyst) -- always
- Quick pipeline: all agents -- no Planner step exists
- Any agent when instruction file is missing (safety fallback)

### Which Agents Use Which Path

| Pipeline | Pre-assembled (instruction file) | Simplified (fallback) |
|----------|----------------------------------|----------------------|
| Quick | none | all agents |
| Standard | Metis, Hephaestus, Themis, Aletheia | Apollo, Hermes, Athena |
| Full | Metis, Hephaestus, Themis, Aletheia | Apollo, Hermes, Athena |
| Decomposition | Metis, Hephaestus, Themis, Aletheia | Apollo, Hermes, Athena |

### Steps

1. **Read role definition:** `~/.claude/moira/core/rules/roles/{agent_name}.yaml`
   - Extract: `identity`, `capabilities`, `never` constraints
2. **Read base rules:** `~/.claude/moira/core/rules/base.yaml`
   - Extract: `inviolable` rules (always included)
3. **Read response contract:** `~/.claude/moira/core/response-contract.yaml`
4. **Read task context:** from state files in `~/.claude/moira/state/tasks/{task_id}/`
   - Input description, previous step artifacts (as specified by pipeline `reads_from`)
5. **Assemble prompt** using the template below

### Prompt Template

```
## Identity

{content from role yaml identity field}

## Rules

### Inviolable (NEVER violate)
{inviolable rules from base.yaml}

### Role Constraints
{never rules from role yaml}

## Response Contract

{response contract content}

You MUST return your response in this exact format:
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <1-2 sentences>
ARTIFACTS: <comma-separated list of artifact file paths you wrote>
NEXT: <recommended next step>

Write all detailed output to the artifact files. Return ONLY the status summary above.

## Task

{task description and context from input.md and previous artifacts}

## Output

Write your detailed results to: {artifact_path}
The artifact path is relative to: ~/.claude/moira/state/
```

---

## Dispatch Modes

### Foreground Dispatch (Sequential Steps)

Used for: all sequential pipeline steps (orchestrator waits for result).

```
Use the Agent tool:
  - description: "{Name} ({role}) — {brief task description}"
  - prompt: {assembled prompt from template above}
  - subagent_type: "general-purpose"
```

Wait for agent to return. Parse response.

### Background Dispatch

Used for: post-task reflection (Phase 10), parallel implementation batches (Phase 4+).

```
Use the Agent tool:
  - description: "{Name} ({role}) — {brief task description}"
  - prompt: {assembled prompt}
  - subagent_type: "general-purpose"
  - run_in_background: true
```

Do NOT wait for result. Continue with next pipeline step. Result notification arrives later.

### Parallel Dispatch

Used for: Explorer + Analyst in Standard/Full pipelines.

Send TWO Agent tool calls in a SINGLE message:

```
Agent call 1:
  - description: "Hermes (explorer) — explore codebase for {task}"
  - prompt: {explorer prompt}

Agent call 2:
  - description: "Athena (analyst) — analyze requirements for {task}"
  - prompt: {analyst prompt}
```

Both are foreground. Orchestrator waits for BOTH to complete before proceeding.

---

## Response Parsing

### Expected Format

Agent returns text. Parse the response for these fields:

```
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <text>
ARTIFACTS: <comma-separated file paths>
NEXT: <text>
```

### Parsing Rules

1. Look for `STATUS:` at the start of a line (case-insensitive)
2. Extract the status value: must be one of `success`, `failure`, `blocked`, `budget_exceeded`
3. Look for `SUMMARY:` line, extract text
4. Look for `ARTIFACTS:` line, extract comma-separated paths
5. Look for `NEXT:` line, extract text

### Handling Parse Failures

If the response does not contain a valid `STATUS:` line:
- Treat as E6-AGENT (agent failure — nonsensical output)
- Log the raw response for diagnosis
- Trigger E6 recovery flow (retry 1x, then escalate)

### Status-Specific Handling

- `success` → read SUMMARY and ARTIFACTS, update state, proceed to next step or gate
- `failure` → trigger E6-AGENT recovery
- `blocked` → trigger E1-INPUT recovery (parse REASON and NEED from response)
- `budget_exceeded` → trigger E4-BUDGET mid-execution recovery (parse COMPLETED and REMAINING)

---

## State Updates Around Dispatch

### Before Dispatch

1. Call state transition to mark step as in_progress:
   - Write to `current.yaml`: step = {step_id}, step_status = in_progress
   - Use `moira_state_transition()` pattern (validate step name, set status)
2. Log: "Dispatching {Name} ({role})..."

### After Successful Dispatch

1. Record agent completion:
   - Use `moira_state_agent_done()` pattern (step, status, duration, tokens, summary)
2. If a gate follows this step (per pipeline definition):
   - Set `gate_pending` in `current.yaml`
   - Present gate (per `gates.md`)
3. If no gate follows:
   - Advance to next step

### After Failed Dispatch

1. Record agent failure in history
2. Trigger appropriate error handler (per `errors.md`)

---

## Agent Naming Convention

ALWAYS refer to agents as `Name (role)` in all orchestrator output (D-034):

| Agent File | Display Name |
|------------|-------------|
| apollo.yaml | Apollo (classifier) |
| hermes.yaml | Hermes (explorer) |
| athena.yaml | Athena (analyst) |
| metis.yaml | Metis (architect) |
| daedalus.yaml | Daedalus (planner) |
| hephaestus.yaml | Hephaestus (implementer) |
| themis.yaml | Themis (reviewer) |
| aletheia.yaml | Aletheia (tester) |
| mnemosyne.yaml | Mnemosyne (reflector) |
| argus.yaml | Argus (auditor) |

---

## Quality Checklist Injection

For agents with quality gate assignments, append the quality checklist to their prompt. This ensures agents evaluate quality criteria and write structured findings.

### Agent-to-Gate Mapping

| Agent | Gate | Checklist File |
|-------|------|---------------|
| Athena (analyst) | Q1 | q1-completeness.yaml |
| Metis (architect) | Q2 | q2-soundness.yaml |
| Daedalus (planner) | Q3 | q3-feasibility.yaml |
| Themis (reviewer) | Q4 | q4-correctness.yaml |
| Aletheia (tester) | Q5 | q5-coverage.yaml |

### Injection Path

- **Pre-planning agents** (Athena Q1): checklist injected via simplified assembly path — append to prompt template after Task section
- **Post-planning agents** (Metis Q2, Daedalus Q3, Themis Q4, Aletheia Q5): checklist injected via instruction files written by Daedalus

### Checklist Prompt Appendix

For each agent with a quality gate, append after the Task section:

```
## Quality Checklist — {Gate Name}

You MUST evaluate every item in this checklist. For each item, report:
- `pass` — requirement satisfied
- `fail` — requirement not satisfied (include severity, detail, evidence)
- `na` — not applicable to this task (justify)
- `skip` — cannot evaluate (justify)

Write your findings to: `.claude/moira/state/tasks/{task_id}/findings/{your_name}-{gate}.yaml`
using the findings schema format.

Include a QUALITY line in your response:
QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)

Items to evaluate:
{checklist items loaded from ~/.claude/moira/core/rules/quality/q{N}-*.yaml}

CRITICAL: Do not skip items. Do not mark items as `pass` without verifying. If you cannot verify — mark as `skip` with justification, NEVER mark as `pass`.
```

Load checklist items from `~/.claude/moira/core/rules/quality/q{N}-*.yaml` where N is the gate number. Extract the `items[]` array and format each item as:

```
- [{id}] {check} (severity: {severity_if_fail})
```

---

## Quality Map Injection

For agents that receive quality map context, include the quality map summary in their instructions.

### Agents That Receive Quality Map

| Agent | Access Level | Source File |
|-------|-------------|-------------|
| Metis (architect) | L1 (summary) | quality-map/summary.md |
| Themis (reviewer) | L1 (summary) | quality-map/summary.md |
| Daedalus (planner) | L0 (full) | quality-map/full.md |

### Injection

Read the quality map file from `~/.claude/moira/knowledge/quality-map/` and include it in the agent prompt:

- For L1 agents: include `summary.md` content
- For L0 agents (Daedalus): include `full.md` content

If the quality map file does not exist or is empty, skip injection silently.

---

## Quality Mode Communication

Include the current CONFORM/EVOLVE mode in assembled instructions for agents that receive quality map context.

### Mode Section Template

Append to agent instructions (after quality map injection):

```
## Quality Mode: {CONFORM|EVOLVE}

{If CONFORM:}
Follow existing patterns as documented in the quality map.
Only avoid 🔴 Problematic patterns for NEW code.

{If EVOLVE:}
Evolving pattern: {current_target from config.yaml}
Use improved approach for this pattern only. Follow all other patterns normally.

Quality Map Summary:
{quality-map/summary.md content}
```

Read the mode from `config.yaml` → `quality.mode` (default: conform).
Read the evolution target from `config.yaml` → `quality.evolution.current_target` (if in EVOLVE mode).

---

## Worktree Isolation

NOT used in Phase 3. Implementers write directly to the project.

Worktree isolation (`isolation: "worktree"` in Agent tool) is a Phase 12 concern for parallel execution safety.
