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
   - Prepend `## Agent Role Clarification` section (same as in simplified assembly prompt template) before the instruction file contents
   - Use as the agent prompt — skip simplified assembly
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
| Analytical | none | all agents (D-126) |

**Special Dispatch Cases** (not part of standard assembly paths):
| Pipeline | Agent | Dispatch Method |
|----------|-------|-----------------|
| Any | Mnemosyne (reflector) | Dedicated dispatch via `reflection.md` |
| Any | Argus (auditor) | Dedicated dispatch via `/moira audit` templates |
| Any | Completion processor | Dedicated dispatch via `completion.md` (Section 7 of orchestrator) |

**Note:** Metis (architect) dispatch via simplified assembly additionally includes step 4f (pre-architecture documentation fetch — D-164), which injects external system documentation and closed-world constraint before the quality checklist.

### Instruction Size Validation (D-113)

Before dispatching any agent, estimate instruction size (assembled prompt byte count / 4 ≈ tokens). If estimated size exceeds 50k tokens:
1. Reduce graph data: L2 → L1 → L0
2. Reduce knowledge levels: L2 → L1 → L0 (lowest priority knowledge types first)
3. Layer 4 (task-specific) instructions are NEVER truncated — they are the highest priority

The canonical size check logic is in `lib/rules.sh` → `moira_rules_assemble_instruction()`. For simplified assembly, the orchestrator applies the same reduction logic inline.

**Implementation note:** Steps 4b (graph context) and 4c (infrastructure MCP) are both implemented in `lib/rules.sh` → `moira_rules_assemble_instruction()`. The function calls `moira_mcp_format_infrastructure_section()` from `lib/mcp.sh` to generate the infrastructure tools prompt section. This applies to both simplified assembly and pre-assembled instruction files.

### Steps

1. **Read role definition:** `~/.claude/moira/core/rules/roles/{agent_name}.yaml`  <!-- Runtime path; installed by src/install.sh from src/global/core/rules/roles/ -->
   - Extract: `identity`, `capabilities`, `never` constraints
2. **Read base rules:** `~/.claude/moira/core/rules/base.yaml`
   - Extract: `inviolable` rules (always included)
3. **Read response contract:** `~/.claude/moira/core/response-contract.yaml` (Note: `rules.sh` `moira_rules_assemble_instruction` embeds the response contract inline rather than reading this file. The file serves as the canonical reference.)
4. **Read task context:** from state files in `.claude/moira/state/tasks/{task_id}/`
   - Input description, previous step artifacts (as specified by pipeline `reads_from`)
4b. **Graph context loading (D-107, D-155):** If `graph_available` is `true` in `.claude/moira/state/current.yaml`:
   - **Pre-planning agents (Apollo, Hermes, Athena, Metis):** If MCP is enabled and the Ariadne infrastructure server is registered, use `ariadne_context` with `budget_tokens: 1000` and `task: "understand"` to assemble task-relevant structural context. Seed files: extract file paths mentioned in the task input description. If `ariadne_context` succeeds, append result as a `## Project Graph (Context)` section to the prompt. If `ariadne_context` fails (MCP error, server unavailable, or empty result), fall back to L0 view: read the L0 graph index via Bash: `source ~/.claude/moira/lib/graph.sh && moira_graph_read_view L0` and append as `## Project Graph (L0)` section. Budget adjustment: add ~1000 tokens to context estimate for ariadne_context output (or ~200-500 tokens for L0 fallback).
   - **Daedalus (planner):** Pass graph directory paths in the Task section: graph data at `.ariadne/graph/`, views at `.ariadne/views/`. Daedalus queries graphs directly and assembles `## Project Graph` sections in instruction files. Daedalus should use `ariadne_context` token estimates (`total_tokens`, `budget_used` fields) for precise budget allocation per implementation batch.
   - **Post-planning agents (Hephaestus, Themis, Aletheia):** No change — graph data comes via pre-assembled instruction files (assembled by Daedalus).
   - If `graph_available` is `false` or not present: skip this step entirely (agents work without graph data, per D-102 graceful degradation).
4b-temporal. **Temporal availability context (D-159):** If `temporal_available` is `true` in `.claude/moira/state/current.yaml`:
   - Note `temporal_available: true` in the agent dispatch context so that conditional temporal guidance in agent role capabilities activates
   - Pre-planning agents and Daedalus receive this as part of their Task section: `Temporal data: available — agents may use ariadne_churn, ariadne_coupling, ariadne_hotspots, ariadne_ownership, ariadne_hidden_deps`
   - If `temporal_available` is `false` or not present: include `Temporal data: not available — temporal tool guidance in agent capabilities does not apply`
4c. **Infrastructure MCP injection (D-115):** If MCP is enabled (`.claude/moira/config.yaml` → `mcp.enabled` is `true`):
   - Read `.claude/moira/config/mcp-registry.yaml`
   - For each server with `infrastructure: true`: collect tool names and purposes
   - Append `## Infrastructure Tools (Always Available)` section to the prompt (using template from "Infrastructure MCP — All Agents, All Pipelines" section below)
   - This applies to ALL agents in ALL pipelines (pre-planning, planning, post-planning)
   - Subagents inherit MCP servers from the parent session — infrastructure tools are callable
   - If no infrastructure servers found or MCP disabled: skip this step
4d. **MCP Resources (D-162):** When Ariadne is running and `graph_available` is `true`, MCP resources provide zero-cost ambient context. Claude Code supports resources via `@server:protocol://path` syntax — resources are automatically fetched and included as attachments.
   Available Ariadne resources:
   - `@ariadne:ariadne://overview` — project summary (node/edge counts, languages, layers, cycles)
   - `@ariadne:ariadne://file/{path}` — file metadata and dependencies
   - `@ariadne:ariadne://cluster/{name}` — cluster detail and metrics
   - `@ariadne:ariadne://smells` — architectural issues
   - `@ariadne:ariadne://hotspots` — top files by combined importance
   - `@ariadne:ariadne://freshness` — graph staleness state
   Resources complement tool calls: resources provide ambient read-only snapshots, tools provide parameterized on-demand queries. Use resources for context injection, tools for specific analysis.
4e. **Bookmark lifecycle (D-160):** Daedalus creates task-scoped bookmarks during the planning step using `ariadne_bookmark` with naming convention `task-{task_id}-{name}`. Downstream agents reference these bookmarks in `ariadne_context` and `ariadne_subgraph` calls. Bookmark cleanup is handled by the completion processor (see `completion.md`) — it calls `ariadne_remove_bookmark` for any bookmarks with the task ID prefix. If cleanup fails, stale bookmarks are harmless and do not block task completion.
4f. **Pre-architecture documentation fetch (D-164):** When constructing the prompt for Metis (architect) only — skip this step for all other agents:

   1. **Scan upstream artifacts** — read exploration.md, input.md, and requirements.md from the task state directory. Identify mentions of external systems, platforms, APIs, protocols, or third-party libraries that are NOT part of the project's own codebase.

   2. **Check verified facts cache** — for each identified external system, read `.claude/moira/knowledge/libraries/verified-facts.yaml`. If a verified entry exists for this system and is not expired (based on `expiry_hint` and agent judgment), use the cached fact. Skip Context7 fetch for this system.

   3. **Fetch documentation** — for each remaining unverified external system (max 3 systems, prioritized by mention frequency in upstream artifacts):
      - Primary: Context7 MCP — call `resolve-library-id` with the system name, then `query-docs` with the resolved library ID and a topic relevant to the task
      - Fallback: WebFetch if registered in mcp-registry.yaml
      - If no documentation tool available or fetch fails: mark the system as `DOCUMENTATION_NOT_AVAILABLE`

   4. **Inject into prompt** — assemble a `## External Documentation (auto-fetched)` section containing:
      - For each system with fetched documentation: the documentation content with system name header
      - For each system marked `DOCUMENTATION_NOT_AVAILABLE`: a note stating documentation was not available
      - Place this section after the Task section and before the Quality Checklist section in the prompt template

   5. **Add closed-world constraint** — append to the injected section:
      ```
      CLOSED-WORLD CONSTRAINT: You can ONLY make factual claims about external systems whose documentation appears in this section. For any system listed as DOCUMENTATION_NOT_AVAILABLE: you MUST classify any claim about it as UNVERIFIED and flag it as load-bearing if your decision depends on it. Do not hedge with 'may' or 'might' — either cite the documentation or report UNVERIFIED.
      ```

   6. **Cap enforcement** — if more than 3 external systems are identified, fetch only the top 3 by mention frequency. Remaining systems are listed as `DOCUMENTATION_NOT_AVAILABLE` with a note: "Documentation fetch cap reached (3 systems max)."

   Token cost: 3-15k tokens per fetched system. For tasks with 0 external system references, this step is a no-op (zero cost).

4g. **Cross-gate traceability injection (D-184):** Inject focused context from previous pipeline gates into the current agent's prompt. This makes cross-gate traceability structural — agents receive scope, acceptance criteria, and UNVERIFIED assumptions from prior steps and MUST address them in their output.

   **Injection map:**

   | Current Agent | Receives From | Sections Extracted |
   |---------------|---------------|-------------------|
   | Metis (architect) | classification.md | `## Scope` (full In/Out), `## Acceptance Criteria` (full list) |
   | Daedalus (planner) | classification.md, architecture.md | `## Scope`, `## Acceptance Criteria`, `## Recommendation`, `## Assumptions` (full, including Unverified + Load-bearing) |
   | Hephaestus (implementer) | classification.md, architecture.md | `## Acceptance Criteria`, `## Assumptions / ### Unverified` (if any) |
   | Themis (reviewer) | classification.md, architecture.md | `## Acceptance Criteria`, `## Assumptions / ### Unverified` (full list for audit) |

   **Assembly process:**
   1. Read the artifact files listed in the injection map for the current agent's role
   2. Extract the specified sections (grep from `## Section` to next `## ` or EOF)
   3. Assemble into a `## Traceability Context (system-injected)` block
   4. Place this block after the Task section and before the Quality Checklist section in the prompt

   **Traceability prompt template:**
   ```
   ## Traceability Context (system-injected)

   The following data is from previous pipeline gates. You MUST address these in your output.

   ### Task Scope (from Classification)
   {extracted ## Scope content — In Scope / Out of Scope}

   ### Acceptance Criteria (from Classification)
   {extracted ## Acceptance Criteria content}

   {If architecture.md exists and agent is daedalus/hephaestus/themis:}
   ### Architecture Decision (from Architecture)
   {extracted ## Recommendation content}

   {If architecture.md contains UNVERIFIED items:}
   ### Unverified Assumptions (from Architecture)
   {extracted ## Assumptions / ### Unverified content}
   {extracted ## Assumptions / ### Load-bearing content}

   ### Your Obligations
   - Your artifact MUST reference the scope above (Daedalus: ## Scope Check, Metis: stay within scope)
   - Your artifact MUST address acceptance criteria (Daedalus: ## Acceptance Test, Themis: verify each)
   - If UNVERIFIED items listed: you MUST address each one (verify, mitigate, or justify proceeding)
   ```

   **Skip conditions:** If the required artifact files don't exist yet (e.g., classification.md not yet written when dispatching Apollo), skip this step. This is a no-op for Apollo, Hermes, and Athena (they run before any gates produce output).

   **Dual injection path:** For pre-planning agents (Metis, Daedalus), traceability is injected via simplified assembly (step 4g). For post-planning agents (Hephaestus, Themis, Aletheia), Daedalus includes the relevant traceability data in pre-assembled instruction files. The `agent-inject.sh` hook provides a lightweight backup injection for UNVERIFIED items only (see hook design in D-184).

5. **Quality checklist injection:** Check if this agent has a quality gate assignment (per Agent-to-Gate Mapping table in this document). If yes:
   - Read quality checklist from `~/.claude/moira/core/rules/quality/q{N}-*.yaml`
   - Append Quality Checklist section to prompt (using Checklist Prompt Appendix template from this document)
6. **Assemble prompt** using the template below

### Prompt Template

```
## Agent Role Clarification

You are a DISPATCHED AGENT, not the orchestrator. The "Orchestrator Boundaries" section in CLAUDE.md does NOT apply to you. You MUST freely use Read, Edit, Write, Grep, Glob, and Bash on project files to complete your task.

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
SUMMARY: <1-2 sentences, factual>
ARTIFACTS: [<list of file paths written>]
NEXT: <recommended next pipeline step>
QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)  [only if quality gate assigned]

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
1b. Post-agent guard check (D-099, D-116): If agent role is implementer, explorer, or calliope, run guard verification against protected paths (see orchestrator.md Section 2, step d1). If violation → present Guard Violation Gate (per `gates.md`) before any approval gate.
1c. **Artifact contract validation (D-184):** Performed by `artifact-validate.sh` hook at SubagentStop — validates that the agent's artifact contains required sections per role. If sections are missing, the hook blocks the agent with specific feedback. By the time the orchestrator processes the response, artifact contracts are guaranteed to be satisfied. See orchestrator.md Section 2, step d2.
2. If a gate follows this step (per pipeline definition):
   - Set `gate_pending` in `current.yaml`
   - Present gate (per `gates.md`) — gate content is extracted from artifact required sections
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
| calliope.yaml | Calliope (scribe) |

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
| Hermes (explorer) | Q1 | q1-completeness.yaml | <!-- D-189: gap analysis moved from Athena to Hermes -->
| Metis (architect) | Q2 | q2-soundness.yaml |
| Daedalus (planner) | Q3 | q3-feasibility.yaml |
| Themis (reviewer, plan-check) | Q3b | q3b-plan-check.yaml | <!-- D-190: plan validation in Full pipeline -->
| Themis (reviewer) | Q4 | q4-correctness.yaml |

**Analytical Pipeline Quality Gates** (used instead of Q1-Q5 when pipeline=analytical):

| Agent | Gate | Checklist File |
|-------|------|---------------|
| Themis (reviewer) | QA1 | qa1-scope-completeness.yaml |
| Themis (reviewer) | QA2 | qa2-evidence-quality.yaml |
| Themis (reviewer) | QA3 | qa3-actionability.yaml |
| Themis (reviewer) | QA4 | qa4-analytical-rigor.yaml |

<!-- D-194: Aletheia (Q5) removed from default pipeline — Q5 coverage via embedded verify + bash build/test step -->
<!-- D-189: Athena no longer default-dispatched — Q1 handled by Hermes gap analysis -->
Agents not listed (Apollo, Athena, Hephaestus, Aletheia, Mnemosyne, Argus, Calliope) have no quality gate assignment in default pipeline flows. Athena retains Q1 capability when dispatched on-demand.

### Injection Path

- **Pre-planning agents** (Hermes Q1, Metis Q2, Daedalus Q3): checklist injected via simplified assembly path — append to prompt template after Task section
- **Post-planning agents** (Themis Q3b plan-check, Themis Q4 review): checklist injected via instruction files written by Daedalus (Q4) or simplified assembly (Q3b)

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

## Analytical Pipeline Dispatch

When dispatching agents in the analytical pipeline, include additional mode context in the Task section of the prompt.

### Mode Context Injection

For ALL agents dispatched during the analytical pipeline, add to the Task section:

```
Pipeline mode: analytical
Subtype: {subtype from classification.md}
Pass number: {N from current.yaml analytical.pass_number}  [for analysis agents only]
Previous pass summary: {summary from previous analysis-pass files}  [if N > 1]
```

### Agent Map Resolution (Analysis Step)

At the analysis step, the orchestrator resolves which agents to dispatch:

1. Read `agent_map` from `~/.claude/moira/core/pipelines/analytical.yaml`
2. Read subtype from `.claude/moira/state/tasks/{task_id}/classification.md`
3. Look up `agent_map[subtype]`:
   - `agents` list → which agents to dispatch
   - `mode` → foreground (single agent) or parallel (multiple agents)
   - `support` → optional support agents dispatched after primary completes
   - `focus` → analytical focus directive to include in agent prompt (e.g., "Open-ended investigation. Follow leads, map unknowns.")
   - `ariadne_focus` → Ariadne query guidance to include when graph is available (e.g., "targeted queries on area of interest")
4. Dispatch agents using the resolved configuration. Include `focus` in the agent prompt's task context section. If `graph_available` is true, also include `ariadne_focus` as Ariadne query guidance.

### Organize Map Resolution (Organize Step)

At the organize step:
1. Read `organize_map` from the pipeline YAML
2. Dispatch the agent specified by `organize_map[subtype]`, falling back to `organize_map.default` (metis) if no subtype-specific entry exists (D-132: Metis is the universal organizer for all subtypes)

### Ariadne MCP Access (Tier 2)

During analytical analysis passes, Metis and Argus have access to Ariadne MCP tools (if Ariadne MCP server is running and within budget). Available queries: blast-radius, importance, spectral, compressed, diff, symbols, symbol-search, callers, callees, symbol-blast-radius, context, tests-for, reading-order, plan-impact.

---

## MCP Tool Allocation

When MCP is enabled for the project, include MCP context in agent dispatches.

### Condition Check

Before injecting MCP context, check if MCP is enabled:
- Read `.claude/moira/config.yaml` → `mcp.enabled`
- If `false` or not found: skip the entire MCP section
- If `true`: read `.claude/moira/config/mcp-registry.yaml` and include MCP context

### Infrastructure MCP — All Agents, All Pipelines (D-115)

Infrastructure MCP tools (D-108) are injected into ALL agent prompts regardless of pipeline type. This applies to both simplified assembly and pre-assembled instruction files. Subagents inherit MCP servers from the parent Claude Code session, so infrastructure tools like Ariadne are callable by all agents.

When MCP is enabled and registry contains servers with `infrastructure: true`, append to EVERY agent prompt (pre-planning, planning, post-planning — all pipelines):

```
## Infrastructure Tools (Always Available)

The following tools are always available — use them freely for structural queries:

{For each infrastructure server and its tools:}
- {server}:{tool} — {purpose}
```

Infrastructure MCP tools are always authorized — no justification check, no budget impact tracking. Example: Ariadne graph queries are always available because they are read-only structural data with near-zero cost.

**Why this is separate from external MCP:** Infrastructure tools bypass Daedalus authorization because they meet strict criteria (D-108): read-only, zero external risk, near-zero token cost, Moira-owned. External MCP tools still require per-step authorization via Daedalus or registry-based guidelines.

### External MCP — Quick Pipeline (D-109)

Quick Pipeline has no Daedalus, so external MCP authorization is constructed directly by the dispatch module from the registry. When MCP is enabled and registry contains non-infrastructure servers, append to ALL Quick Pipeline agent prompts (explorer, implementer, reviewer):

```
## External MCP Usage Rules

{For each external server and its tools:}
- {server}:{tool} — {purpose}
  Use when: {when_to_use}
  Do NOT use when: {when_NOT_to_use}
  Budget: ~{token_estimate} tokens

Before calling any external MCP tool, verify:
1. Do I actually need this to write correct code?
2. Is this available in project files I was given?
3. Will the response fit within my context budget?

If (1) is no or (2) is yes → DO NOT call.
```

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

Note: When `ariadne_context` is used, its response includes `total_tokens` and `budget_used` fields. Daedalus should use these actual token counts (not estimates) for precise budget allocation in instruction files. This is more accurate than the static `token_estimate` values in the registry.
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
