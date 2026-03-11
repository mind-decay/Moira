# Audit System

## Principle: Trust But Verify

The Audit system is an independent observer verifying health of ALL Moira components. Not part of the pipeline, not part of reflection — a separate subsystem.

## Audit Triggers

### Automatic
- After every 20 tasks: full audit
- On `/moira upgrade`: compatibility audit
- On `/moira refresh`: knowledge audit subset

### Manual
- `/moira audit`: full audit (all 5 domains)
- `/moira audit <domain>`: specific domain audit

### Passive (lightweight, during normal operation)
- On task start: check locks, check state consistency
- On explore: flag if findings contradict knowledge
- On review: flag if code contradicts conventions

Passive checks don't produce full reports — just inline warnings.

## Tiered Audit Depth

| Type | Trigger | Depth | Agents | Time |
|------|---------|-------|--------|------|
| Light | Every 10 tasks (passive) | Surface consistency checks | 1 (auditor) | ~1 min |
| Standard | Every 20 tasks or manual | Full 5-domain audit | 1-2 | ~3-5 min |
| Deep | On upgrade, quarterly, manual | Deep with codebase verification | 3-4 | ~10-15 min |

## Five Audit Domains

### 1. Rules Audit

Checks:
- Core rules integrity (no unauthorized modifications)
- All role files present and valid
- Quality criteria files complete
- Inviolable rules intact
- Project rules match detected reality (stack, conventions)
- No conflicts between layers
- No duplicate or contradicting rules

Findings example:
```
conventions.yaml line 23: "naming: camelCase"
But last 5 tasks used snake_case in API routes.
→ Convention may be wrong or outdated. Verify.
```

### 2. Knowledge Audit

Checks:
- Project model coverage (% of directories documented)
- Project model accuracy (does it match reality?)
- Decision log completeness (context + reasoning present?)
- Pattern evidence (are patterns backed by task evidence?)
- Quality map coverage and accuracy
- Freshness (% fresh vs aging vs stale)
- Internal contradictions
- Missing areas (new directories not documented)

Findings example:
```
"Uses Redis for caching" — no Redis dependency found.
Possibly removed? Verify.
```

### 3. Agent Performance Audit

Analyzes per-agent effectiveness over recent tasks:
- Explorer accuracy (how often did it miss relevant files?)
- Analyst completeness (how often did reviewer catch missing edge cases?)
- Architect first-pass acceptance rate
- Planner accuracy (batch conflicts, budget estimate accuracy)
- Implementer first-pass review score
- Reviewer catch rate and false positive rate
- Common failure patterns per agent

Produces specific rule update recommendations:
```
Explorer misses utility files in shared/ directory.
→ Add "always check shared/ and utils/" to explorer rules.

Implementer misses null checks on optional fields (5 occurrences).
→ Add "null check rule" to implementer rules.
```

### 4. Config Audit

Checks:
- MCP registry: unused servers, call efficiency, caching opportunities
- Budget configuration: agents hitting >70% frequently → adjust
- Hooks: all required hooks active and functional
- Version: is core up to date?
- State: orphaned tasks, stale locks

### 5. Cross-Consistency Audit

Most important. Verifies ALL components are aligned:

- **Rules ↔ Knowledge**: do rules match documented patterns?
- **Rules ↔ Codebase**: do rules match actual code?
- **Knowledge ↔ Codebase**: does project model match reality?
- **Agents ↔ Rules**: do agents reference current rule versions?
- **State ↔ Reality**: do locks match branches, are completed tasks actually merged?

## Audit Output

### Summary (displayed to user)
```
MOIRA SYSTEM AUDIT
├─ Rules: 1 issue (conventions drift)
├─ Knowledge: 3 issues (1 stale, 1 gap, 1 missing reasoning)
├─ Agents: 4 recommendations
├─ Config: 1 optimization
└─ Consistency: 2 mismatches
Total: 11 findings (2 high, 5 medium, 4 low risk)
```

### Detailed report
Written to: `.claude/moira/state/audits/{date}-audit.md`

## Recommendation Approval

### Batch approval by risk level:

**Low risk (auto-apply with confirmation):**
- Freshness marker updates
- Adding scan paths to explorer
- Budget threshold adjustments
- MCP cache suggestions

Presented as:
```
6 low-risk improvements found.
▸ apply-all — apply all 6
▸ review    — go through one by one
```

**Medium risk (batch approval):**
- Rule wording changes
- Convention updates
- Agent instruction modifications

Presented individually with context:
```
Recommendation 1/3:
Add "null check on optionals" to implementer rules.
Evidence: 5 occurrences in last 30 tasks.
▸ apply / skip / modify
```

**High risk (individual approval):**
- Removing or replacing rules
- Changing pipeline behavior
- Architecture pattern reclassification

Always requires detailed review:
```
⚠️ High-risk recommendation:
Reclassify "inline validation" from ⚠️ Adequate to 🔴 Problematic.
This changes how implementer handles validation in ALL future tasks.
Evidence: [detailed evidence]
▸ apply / defer / reject
```

## Auditor Agent

Separate agent, not part of normal pipeline:

```yaml
identity: |
  You are the Auditor. You verify system health.
  You are INDEPENDENT from the pipeline.

capabilities:
  - Read ALL moira files (rules, knowledge, config, state, metrics)
  - Read project files (to verify knowledge accuracy)
  - Cross-reference between any components
  - Statistical analysis of metrics data

constraints:
  - READ-ONLY — never modify any files
  - Never participate in task execution
  - Recommendations must be actionable and evidence-based
  - Classify findings by risk: low / medium / high

output:
  detailed: .claude/moira/state/audits/{date}-audit.md
  summary: returned to orchestrator for display
```
