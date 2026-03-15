---
name: moira:audit
description: Run Moira system health audit
argument-hint: "[rules|knowledge|agents|config|consistency]"
allowed-tools:
  - Agent
  - Read
  - Write
---

# Moira — Audit

Run independent system health verification across Moira's 5 domains. Dispatches Argus (auditor) with domain-specific templates. Produces structured findings with risk-classified recommendations.

## Setup

- **MOIRA_HOME:** `~/.claude/moira/`
- **Project state:** `.claude/moira/state/`
- **Template dir:** `~/.claude/moira/templates/audit/`
- **Report dir:** `.claude/moira/state/audits/`
- **Audit schema:** `~/.claude/moira/schemas/audit.schema.yaml`
- **Write scope:** `.claude/moira/` paths ONLY — NEVER write project source files

## Parse Argument

| Argument | Action |
|----------|--------|
| _(none)_ | Full audit — all 5 domains, standard depth |
| `rules` | Rules domain only |
| `knowledge` | Knowledge domain only |
| `agents` | Agents domain only |
| `config` | Config domain only |
| `consistency` | Consistency domain only |

## Execution

### 1. Determine Depth

- **If triggered by audit-pending flag** (`state/audit-pending.yaml` exists): use the pending depth (light or standard).
- **If manual invocation:** default to standard. Offer the user a choice: "Run at standard or deep depth? [standard/deep]"
- **Light audits** only cover rules and knowledge domains (D-093c).

### 2. Select Templates

Read template files from `~/.claude/moira/templates/audit/`:

| Domain | Light | Standard | Deep |
|--------|-------|----------|------|
| rules | `rules-light.md` | `rules-standard.md` | `rules-deep.md` |
| knowledge | `knowledge-light.md` | `knowledge-standard.md` | `knowledge-deep.md` |
| agents | _(skip for light)_ | `agents-standard.md` | `agents-deep.md` |
| config | _(skip for light)_ | `config-standard.md` | `config-deep.md` |
| consistency | _(skip for light)_ | `consistency-standard.md` | `consistency-deep.md` |

### 3. Dispatch Argus

For each domain to audit:
1. Read the domain template file
2. Dispatch Argus via Agent tool with the template content as the prompt
3. **For full audit:** dispatch all domain agents in parallel (no dependencies between domains — EXCEPT for deep cross-consistency which may run after others complete)
4. **Agent type:** Use `subagent_type: "general-purpose"` with a prompt that includes the full template content and Argus identity

**Agent dispatch prompt format:**
```
You are Argus, the Moira system auditor.

[Full template content from the template file]

Report your findings in the exact YAML format specified in the template.
End your response with a summary line: "FINDINGS: N total (H high, M medium, L low)"
```

### 4. Collect Results

For each domain agent response:
1. Parse the findings YAML block from the agent's response
2. Extract finding count, risk levels, domain breakdown
3. Write per-domain findings to `.claude/moira/state/audits/{date}-{domain}.yaml`

### 5. Generate Report

Combine all domain findings into a unified report:
- Write to `.claude/moira/state/audits/{date}-audit.md`
- Include summary header with total findings by risk and domain
- Include full findings YAML block
- Include narrative sections per domain

### 6. Display Summary

Show the user a summary in this format:

```
MOIRA SYSTEM AUDIT ({depth})
├─ Rules: N issues
├─ Knowledge: N issues
├─ Agents: N recommendations
├─ Config: N optimizations
└─ Consistency: N mismatches
Total: N findings (H high, M medium, L low)
```

### 7. Recommendation Approval Flow

Present recommendations grouped by risk:

**Low risk** — batch approval:
```
N low-risk improvements found.
▸ apply-all — apply all N
▸ review    — go through one by one
```
Low-risk changes (freshness markers, scan paths, budget thresholds) are written directly to `.claude/moira/` config files via Write tool.

**Medium risk** — individual approval with context:
```
Recommendation 1/N:
[Finding ID] [Description]
Evidence: [evidence]
▸ apply / skip / modify
```
Medium-risk changes (rule wording, convention updates) are written to `.claude/moira/` files via Write tool. These are moira project-layer files, not project source code.

**High risk** — detailed review:
```
⚠️ High-risk recommendation:
[Finding ID] [Description]
[Full evidence]
▸ apply / defer / reject
```
High-risk changes or changes requiring project source file modifications: dispatch Hephaestus (implementer) via Agent tool with recommendation context.

### 8. Record and Cleanup

- **Art 5.2 tracking:** For any approved rule-change recommendation, record it as an observation in `.claude/moira/state/reflection/pattern-keys.yaml` (append to patterns array with source: "audit", description of the change).
- **Clear audit-pending flag:** Delete `.claude/moira/state/audit-pending.yaml` after audit completes (regardless of whether recommendations were applied).
- **Report saved at:** `.claude/moira/state/audits/{date}-audit.md`

## Constitutional Compliance

- **Art 1.2:** Argus is READ-ONLY. Never modifies files. Recommendations are applied by this command (low/medium) or Hephaestus (high).
- **Art 4.2:** All recommendations require user approval before application.
- **Art 5.2:** Rule changes from audit are recorded as observations for trend tracking. The 3-confirmation threshold applies to automatic evolution — user-approved audit recommendations are explicit decisions.
- **Write scope:** This command writes ONLY to `.claude/moira/` paths. NEVER to project source files.
