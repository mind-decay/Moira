# MCP Integration

## Principle: MCP as Managed Resource

MCP tools are not "available to all." They are a managed resource allocated by the orchestration system to specific agents for specific purposes.

```
WRONG: Agent decides which MCP tools to use
RIGHT: Planner determines which MCP tools are needed per step,
       agent receives ONLY authorized tools
```

## MCP Registry

Generated at `/moira init` by scanning available MCP servers.

```yaml
# .claude/moira/config/mcp-registry.yaml

servers:
  context7:
    type: documentation
    tools:
      resolve-library-id:
        purpose: "Find library identifier for doc lookup"
        cost: low
        reliability: high
        when_to_use: "When agent needs docs for a specific library"
        when_NOT_to_use: "For internal project code, for general knowledge"
        token_estimate: 2000
      query-docs:
        purpose: "Fetch documentation for a library"
        cost: medium-high
        reliability: high
        when_to_use: "When implementation requires specific API knowledge"
        when_NOT_to_use: "For exploratory browsing, when project has local docs"
        budget_impact: "~5-20k tokens per query"
        token_estimate: 14000

  figma:
    type: design
    tools:
      get_design_context:
        purpose: "Get design specs from Figma"
        cost: high
        reliability: medium
        when_to_use: "When implementing UI from Figma design"
        when_NOT_to_use: "Backend tasks, when design is in text"
        token_estimate: 20000
```

## MCP Allocation in Plans

Planner explicitly authorizes MCP usage per step:

```markdown
## Step 3: Implement date picker component

MCP AUTHORIZED:
  - context7:query-docs (for: react-datepicker API reference)
    BUDGET: ~8k tokens
    JUSTIFY: Component uses react-datepicker with complex API,
             no local docs available

MCP PROHIBITED:
  - figma:* (design extracted in step 1)
  - context7 for React itself (agent should know React)
```

## Agent MCP Instructions

Each agent receives explicit MCP rules in assembled instructions:

```markdown
## MCP Usage Rules for This Step

You MAY use:
- context7:query-docs for "react-datepicker" — if you need specific API details

You MUST NOT use:
- Any other MCP tool
- context7 for libraries you should already know (React, TypeScript)

Before calling any MCP tool, verify:
1. Do I actually need this to write correct code?
2. Is this available in project files I was given?
3. Will the response fit within my context budget?

If (1) is no or (2) is yes → DO NOT call.
```

## MCP Usage Review

Reviewer checks MCP usage as part of code review:

```
- [ ] All MCP calls were authorized in the plan
- [ ] No unauthorized MCP calls were made
- [ ] MCP responses were actually used (not fetched and ignored)
- [ ] No MCP calls for information available locally
- [ ] Results from MCP were applied correctly (not misinterpreted)
```

## MCP Budget Tracking

MCP calls are included in budget reports:

```
AGENT: Implementer-2
├─ Working data: 25k
├─ MCP calls:
│   ├─ context7:query-docs("react-datepicker") → 14k ⚠️
│   └─ context7:query-docs("date-fns format")  →  6k
├─ MCP total: 20k
└─ NOTE: MCP consumed 20% of budget
```

## MCP Knowledge Caching

Reflector tracks repeated MCP calls across tasks.

When same call made 3+ times:

```
Observation: context7:query-docs("react-datepicker")
Called in tasks: 045, 051, 058, 062

Recommendation:
Cache essential API reference in knowledge/libraries/react-datepicker.md
Estimated savings: ~14k tokens per task

▸ cache  — create knowledge entry
▸ ignore — library changes too often
```

Cached MCP knowledge is stored in:
```
knowledge/libraries/
├── react-datepicker.md
├── zod.md
└── prisma-client.md
```

These are loaded as project context instead of making MCP calls.

## Infrastructure vs. External MCP Tools (D-108)

MCP tools are split into two categories:

**Infrastructure MCP** — tools that are part of Moira's own toolchain:
- Ariadne (`ariadne serve`) — project graph queries
- Always registered during init if binary supports `serve`
- Always available to graph-aware agents regardless of pipeline type
- No per-step Daedalus authorization required
- Marked with `infrastructure: true` in registry

**External MCP** — third-party tools discovered via scanner:
- Context7, Figma, IDE servers, etc.
- Require Daedalus authorization in Standard/Full pipelines
- In Quick Pipeline: authorized based on registry `when_to_use` guidelines
- Subject to full budget tracking and review

### Infrastructure Classification Criteria

A tool may be marked `infrastructure: true` only if it meets ALL of the following criteria:

- **Read-only** — no external side effects (does not modify files, state, or external systems)
- **Zero external API risk** — no network calls to third-party services
- **Near-zero token cost** — individual calls cost negligible tokens relative to agent budgets
- **Moira-owned or Moira-essential** — part of Moira's own toolchain or a tightly-coupled dependency
- **Always available** — appropriate regardless of pipeline type or Daedalus authorization state

Future tools requesting infrastructure classification must meet ALL criteria. This prevents ad-hoc classification expansion — the bar is intentionally high because infrastructure tools bypass Daedalus authorization.

Registry format with infrastructure flag:

```yaml
servers:
  ariadne:
    type: graph
    infrastructure: true
    tools:
      blast-radius:
        purpose: "Find files affected by a change"
        cost: low
        reliability: high
        when_to_use: "Before modifying a file to understand impact"
        when_NOT_to_use: "Never — always useful for impact analysis"
        token_estimate: 500
      # ... other ariadne tools

  context7:
    type: documentation
    # infrastructure: false (default, omitted)
    tools:
      query-docs:
        purpose: "Fetch library documentation"
        # ...
```

## Quick Pipeline MCP (D-109)

Quick Pipeline has no Daedalus, so MCP authorization uses a simplified model:

1. **Dispatch reads registry** during simplified assembly
2. **Infrastructure MCP**: always injected as authorized
3. **External MCP**: injected with registry-based guidelines and conservative guardrails

Template injected into Quick Pipeline agent prompts:

```markdown
## MCP Usage Rules

### Always Available (Infrastructure)
{For each server with infrastructure: true:}
- {server}:{tool} — {purpose}

### Available with Justification
{For each external server:}
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

Reviewer (Themis) checks MCP usage in Q4 review regardless of pipeline type.

## MCP Server Discovery

At `/moira init`, system discovers available MCP servers:
1. Check for Ariadne binary — if `ariadne serve` exists, register as infrastructure MCP
2. Scan MCP configuration (external servers via scanner agent)
3. List available tools per server
4. Classify each tool (type, cost, reliability)
5. Generate mcp-registry.yaml (infrastructure + external)
6. User reviews and adjusts

New MCP servers added later → `/moira refresh` updates registry.
