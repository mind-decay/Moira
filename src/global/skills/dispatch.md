# Agent Dispatch Module

Reference: `design/architecture/agents.md` (Agent Response Contract, Spawning Strategy), `design/architecture/rules.md` (Rule Assembly)

This skill defines how the orchestrator constructs agent prompts, dispatches agents, and processes their responses.

---

## Prompt Construction

### Pre-assembled Instructions (Primary Path)

When dispatching a post-planning agent (any agent after Daedalus has run), check for a pre-assembled instruction file:

1. Check path: `.claude/moira/state/tasks/{task_id}/instructions/{agent_name}.md`
2. If file exists and is non-empty:
   - Read the file contents
   - Use directly as the agent prompt (the file IS the complete prompt)
   - Skip simplified assembly -- the file contains all rules, knowledge, and context
3. If file does not exist:
   - Fall back to simplified assembly (below)

Instruction files are written by Daedalus (planner) during the planning step. They contain L1-L4 merged rules, authorized knowledge, quality checklist, task context, and output path. When graph data is available, instruction files may also contain a `## Project Graph` section with cluster views, blast radius data, and structural context assembled by Daedalus from `.ariadne/views/`.

### Simplified Assembly (Fallback)

Used for:
- Pre-planning agents: Apollo (classifier), Hermes (explorer), Athena (analyst) -- always
- Quick pipeline: all agents -- no Planner step exists
- Any agent when instruction file is missing (safety fallback)

### Which Agents Use Which Path

| Pipeline | Pre-assembled (instruction file) | Simplified (fallback) |
|----------|----------------------------------|----------------------|
| Quick | none | all agents |
| Standard | Hephaestus, Themis, Aletheia | Apollo, Hermes, Athena, Metis, Daedalus |
| Full | Hephaestus, Themis, Aletheia | Apollo, Hermes, Athena, Metis, Daedalus |
| Decomposition | Hephaestus, Themis, Aletheia | Apollo, Hermes, Athena, Metis, Daedalus |

**Special Dispatch Cases** (not part of standard assembly paths):
| Pipeline | Agent | Dispatch Method |
|----------|-------|-----------------|
| Any | Mnemosyne (reflector) | Dedicated dispatch via `reflection.md` |
| Any | Argus (auditor) | Dedicated dispatch via `/moira audit` templates |

### Instruction Size Validation (D-113)

Before dispatching any agent, estimate instruction size (assembled prompt byte count / 4 ≈ tokens). If estimated size exceeds 50k tokens:
1. Reduce graph data: L2 → L1 → L0
2. Reduce knowledge levels: L2 → L1 → L0 (lowest priority knowledge types first)
3. Layer 4 (task-specific) instructions are NEVER truncated — they are the highest priority

The canonical size check logic is in `lib/rules.sh` → `moira_rules_assemble_instruction()`. For simplified assembly, the orchestrator applies the same reduction logic inline.

### Steps

1. **Read role definition:** `~/.claude/moira/core/rules/roles/{agent_name}.yaml`  <!-- Runtime path; installed by src/install.sh from src/global/core/rules/roles/ -->
   - Extract: `identity`, `capabilities`, `never` constraints
2. **Read base rules:** `~/.claude/moira/core/rules/base.yaml`
   - Extract: `inviolable` rules (always included)
3. **Read response contract:** `~/.claude/moira/core/response-contract.yaml` (Note: `rules.sh` `moira_rules_assemble_instruction` embeds the response contract inline rather than reading this file. The file serves as the canonical reference.)
4. **Read task context:** from state files in `.claude/moira/state/tasks/{task_id}/`
   - Input description, previous step artifacts (as specified by pipeline `reads_from`)
4b. **Graph context loading (D-107):** If `graph_available` is `true` in `.claude/moira/state/current.yaml`:
   - **Pre-planning agents (Apollo, Hermes, Athena, Metis):** Read the L0 graph index via Bash: `source ~/.claude/moira/lib/graph.sh && moira_graph_read_view L0`. If non-empty, append as a `## Project Graph (L0)` section to the prompt. Budget adjustment: add ~200-500 tokens to context estimate for L0 index.
   - **Daedalus (planner):** Pass graph directory paths in the Task section: graph data at `.ariadne/graph/`, views at `.ariadne/views/`. Daedalus queries graphs directly and assembles `## Project Graph` sections in instruction files.
   - **Post-planning agents (Hephaestus, Themis, Aletheia):** No change — graph data comes via pre-assembled instruction files (assembled by Daedalus).
   - If `graph_available` is `false` or not present: skip this step entirely (agents work without graph data, per D-102 graceful degradation).
5. **Quality checklist injection:** Check if this agent has a quality gate assignment (per Agent-to-Gate Mapping table in this document). If yes:
   - Read quality checklist from `~/.claude/moira/core/rules/quality/q{N}-*.yaml`
   - Append Quality Checklist section to prompt (using Checklist Prompt Appendix template from this document)
6. **Assemble prompt** using the template below

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
QUALITY: <gate>=<verdict> (<critical>C/<warning>W/<suggestion>S)  [only if quality gate assigned]

Write all detailed output to the artifact files. Return ONLY the status summary above.

## Task

{task description and context from input.md and previous artifacts}

{If agent has quality gate assignment (step 5):}
## Quality Checklist — {Gate Name}

{Quality checklist content from step 5, using Checklist Prompt Appendix template}

## Output

Write your detailed results to: {artifact_path}
The artifact path is relative to: .claude/moira/state/
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
QUALITY: <gate>=<verdict> (<critical>C/<warning>W/<suggestion>S)  [optional, present when agent has quality gate]
```

### Parsing Rules

1. Look for `STATUS:` at the start of a line (case-insensitive)
2. Extract the status value: must be one of `success`, `failure`, `blocked`, `budget_exceeded`
3. Look for `SUMMARY:` line, extract text
4. Look for `ARTIFACTS:` line, extract comma-separated paths
5. Look for `NEXT:` line, extract text
6. Look for `QUALITY:` line (optional). If present, extract gate name, verdict, and severity counts. Record in state for gate evaluation.

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
   - Write the equivalent of `moira_state_transition()` updates to `current.yaml` (see `lib/state.sh` for field logic) (see orchestrator.md Section 4 — When to Write State table for field logic)
2. Log: "Dispatching {Name} ({role})..."

### After Successful Dispatch

1. Record agent completion:
   - Write the equivalent of `moira_state_agent_done()` updates to `current.yaml` and `status.yaml` (see `lib/state.sh` for field logic) (see orchestrator.md Section 4 — When to Write State table for field logic)
1b. Post-agent guard check (D-099): If agent role is implementer or explorer, run guard verification against protected paths (see orchestrator.md Section 2, step d1). If violation → present Guard Violation Gate (per `gates.md`) before any approval gate.
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

## Context Budget

For ALL agent dispatches, include budget context in the prompt. This reinforces the `budget_exceeded` response contract.

### Budget Section Template

Append after the Output section in the prompt template:

```
## Context Budget

Your budget allocation: {agent_budget}k tokens.
Maximum safe load: 70% ({max_safe}k tokens).

If you detect your context is getting large:
1. STOP immediately
2. Write partial results to your output file with clear boundary marker
3. Return: STATUS: budget_exceeded, COMPLETED: "{done items}", REMAINING: "{remaining items}"
```

### Budget Values

- Read agent budget from `.claude/moira/config/budgets.yaml` → `agent_budgets.{role}`, fallback to `.claude/moira/config.yaml` → `budgets.per_agent.{role}`, fallback to role definition (`~/.claude/moira/core/rules/roles/{role}.yaml` → `budget`), fallback to schema defaults
- Calculate `max_safe = agent_budget * 70 / 100`
- Pre-planning agents: budget included via simplified assembly
- Post-planning agents: budget included via Daedalus instruction files

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

Agents not listed (Apollo, Hermes, Hephaestus, Mnemosyne, Argus) have no quality gate assignment.

### Injection Path

- **Pre-planning agents** (Athena Q1, Metis Q2, Daedalus Q3): checklist injected via simplified assembly path — append to prompt template after Task section
- **Post-planning agents** (Themis Q4, Aletheia Q5): checklist injected via instruction files written by Daedalus

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
| Daedalus (planner) | L2 (full) | quality-map/full.md |

### Injection

Read the quality map file from `.claude/moira/knowledge/quality-map/` and include it in the agent prompt:

- For L1 agents: include `summary.md` content
- For L2 agents (Daedalus): include `full.md` content

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

Read the mode from `.claude/moira/config.yaml` → `quality.mode` (default: conform).
Read the evolution target from `.claude/moira/config.yaml` → `quality.evolution.current_target` (if in EVOLVE mode).

---

## MCP Tool Allocation

When MCP is enabled for the project, include MCP context in agent dispatches.

### Condition Check

Before injecting MCP context, check if MCP is enabled:
- Read `.claude/moira/config.yaml` → `mcp.enabled`
- If `false` or not found: skip the entire MCP section
- If `true`: read `.claude/moira/config/mcp-registry.yaml` and include MCP context

### For Quick Pipeline — Simplified Assembly (D-109)

Quick Pipeline has no Daedalus, so MCP authorization is constructed directly by the dispatch module from the registry. When MCP is enabled and registry exists, append to ALL Quick Pipeline agent prompts (explorer, implementer, reviewer):

```
## MCP Usage Rules

{If registry contains servers with infrastructure: true:}
### Always Available (Infrastructure)
{For each infrastructure server and its tools:}
- {server}:{tool} — {purpose}

{If registry contains non-infrastructure servers:}
### Available with Justification
{For each external server and its tools:}
- {server}:{tool} — {purpose}
  Use when: {when_to_use}
  Do NOT use when: {when_NOT_to_use}
  Budget: ~{token_estimate} tokens

Before calling any non-infrastructure MCP tool, verify:
1. Do I actually need this to write correct code?
2. Is this available in project files I was given?
3. Will the response fit within my context budget?

If (1) is no or (2) is yes → DO NOT call.
```

Infrastructure MCP tools (D-108) are always authorized — no justification check required. Example: Ariadne graph queries are always available because they are read-only structural data with near-zero cost.

### For Daedalus (Planner) — Standard/Full/Decomposition Pipelines

When MCP is enabled and registry exists, append to the Daedalus prompt:

```
## Available MCP Tools

The following MCP servers and tools are available for allocation to agents:

{For each server in registry:}
### {server_name} ({type}) {if infrastructure: true: "[INFRASTRUCTURE — always authorized]"}
{For each tool:}
- **{tool_name}**: {purpose}
  - Cost: {cost}, Reliability: {reliability}
  - Use when: {when_to_use}
  - Do NOT use when: {when_NOT_to_use}
  - Token estimate: ~{token_estimate} tokens

Infrastructure MCP tools (marked above) are always authorized for all agents — do NOT prohibit them.
For external MCP tools, explicitly AUTHORIZE or PROHIBIT per step:
- AUTHORIZE with justification and budget impact
- PROHIBIT with reason (e.g., "design already extracted", "agent should know this")
- Include MCP token estimates in step budget calculations
```

When MCP is disabled, append instead:
```
## MCP Tools
MCP tools are not configured for this project. Do not allocate MCP tools in plan steps.
```

### For Post-Planning Agents — Instruction Files

Daedalus MUST include an "MCP Usage Rules for This Step" section in instruction files:

```
## MCP Usage Rules for This Step

### Always Available (Infrastructure)
{For each infrastructure server and its tools:}
- {server}:{tool} — {purpose}

{If step has authorized external MCP tools:}
### Authorized for This Step
You MAY use:
- {server}:{tool} for "{specific query}" — {justification}

You MUST NOT use:
- Any other non-infrastructure MCP tool
- {server}:{tool} for {reason it's prohibited}

Before calling any non-infrastructure MCP tool, verify:
1. Do I actually need this to write correct code?
2. Is this available in project files I was given?
3. Will the response fit within my context budget?

If (1) is no or (2) is yes → DO NOT call.

{If step has no external MCP authorization:}
No external MCP tools are authorized for this step. Infrastructure tools above are always available.
```

This section is part of the Planner's output — Phase 9 provides the registry data that makes it actionable.

---

## Worktree Isolation

NOT used in Phase 3. Implementers write directly to the project.

Worktree isolation (`isolation: "worktree"` in Agent tool) is a Phase 12 concern for parallel execution safety.
