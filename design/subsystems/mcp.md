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
      - resolve-library-id:
          purpose: "Find library identifier for doc lookup"
          cost: low
          reliability: high
          when_to_use: "When agent needs docs for a specific library"
          when_NOT_to_use: "For internal project code, for general knowledge"

      - query-docs:
          purpose: "Fetch documentation for a library"
          cost: medium-high
          reliability: high
          when_to_use: "When implementation requires specific API knowledge"
          when_NOT_to_use: "For exploratory browsing, when project has local docs"
          budget_impact: "~5-20k tokens per query"

  figma:
    type: design
    tools:
      - get_design_context:
          purpose: "Get design specs from Figma"
          cost: high
          reliability: medium
          when_to_use: "When implementing UI from Figma design"
          when_NOT_to_use: "Backend tasks, when design is in text"
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

## MCP Server Discovery

At `/moira init`, system discovers available MCP servers:
1. Scan MCP configuration
2. List available tools per server
3. Classify each tool (type, cost, reliability)
4. Generate mcp-registry.yaml
5. User reviews and adjusts

New MCP servers added later → `/moira refresh` updates registry.
