# Scanner: MCP Server Discovery
# Agent: Hermes (explorer)
# Phase: Bootstrap (/moira:init)

## Objective

Discover and catalog all available MCP servers and their tools. For each tool, determine its purpose, cost, reliability, and usage guidelines.

## Scan Strategy

1. **Check available MCP tools** — list what MCP servers and tools are available in the current environment
2. **Classify each server** by type: documentation, design, code, search, communication, or other
3. **For each tool**: determine purpose, cost (token impact), reliability, and usage guidelines
4. **Estimate token budget** per tool call based on typical response sizes

Do NOT call MCP tools — only catalog what is available and classify them.

### Classification Guidelines

**Server types:**
- `documentation` — fetches library/API documentation (e.g., Context7)
- `design` — reads design files or specs (e.g., Figma)
- `code` — generates or transforms code
- `search` — searches external sources (web, databases)
- `communication` — sends messages or notifications
- `other` — anything that doesn't fit above

**Cost levels:**
- `low` — <2k tokens typical response
- `medium` — 2-5k tokens typical response
- `medium-high` — 5-15k tokens typical response
- `high` — >15k tokens typical response

**Reliability levels:**
- `high` — consistent results, rarely fails
- `medium` — usually works, occasional failures or variable quality
- `low` — frequently fails or returns inconsistent results

## Output Format

Start output with a YAML frontmatter block between `---` delimiters.

After the second `---`, write the detailed markdown report.

### Frontmatter Contract

```yaml
---
mcp_servers:
  server_name:
    type: documentation
    tools:
      tool-name:
        purpose: "What this tool does"
        cost: medium
        reliability: high
        when_to_use: "Specific scenarios where this tool is valuable"
        when_NOT_to_use: "Scenarios where this tool should NOT be used"
        budget_impact: "~Nk tokens per call"
        token_estimate: 5000
---
```

**CRITICAL:** Use these EXACT field names VERBATIM. The downstream parser matches these exact strings.

All `purpose`, `when_to_use`, `when_NOT_to_use`, and `budget_impact` values are quoted strings.
`token_estimate` is an unquoted integer (estimated tokens per call).

### Markdown Body

After the frontmatter, write a summary:

```markdown
## MCP Servers Discovered

### {server_name} ({type})
{Brief description of what this server provides}

**Tools:**
- **{tool_name}**: {purpose} (cost: {cost}, reliability: {reliability})

## Notes
{Any observations about MCP configuration, missing servers, etc.}
```

## Output Path

Write the complete output to: `.moira/state/init/mcp-scan.md`

## Constraints

- Report ONLY what is actually available in the environment
- Do NOT call any MCP tools — only catalog their existence
- Do NOT guess at tools that might be available — only report confirmed ones
- NO opinions, NO recommendations, NO proposals
- Budget: stay within 140k tokens — this should be a quick scan
