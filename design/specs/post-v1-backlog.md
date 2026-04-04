# Post-v1 Backlog

All items deferred from Phases 1-12. Organized by priority. To be addressed after v1 release based on real usage data.

## Priority A — Low Effort, Clear Value

| # | Item | Source | Effort | Notes |
|---|------|--------|--------|-------|
| 1 | Version pinning enforcement | Phase 5, D8b | Trivial | Upgrade command exists, add `if pinned → warn` |
| 2 | Hook enable/disable CLI | Phase 8 | Low | Currently: edit config.yaml manually |
| 3 | Additional stack presets (nestjs, django, vue-nuxt, rust) | Phase 5 | Low | 6 presets + generic fallback cover most cases |
| 4 | Onboarding live example (Step 3) | Phase 5 | Low | Steps 1-2 work, Step 3 needs full pipeline e2e |

## Priority B — Medium Effort, Needs Usage Data

| # | Item | Source | Effort | Notes |
|---|------|--------|--------|-------|
| 5 | AGENTS.md project adaptation | Phase 5, D-044 | Medium | Global agent definitions work; need task history to know what adaptations matter |
| 6 | Team adoption flow | Phase 5 | Medium | Basic "already initialized" check exists; full flow needs multi-developer infrastructure |
| 7 | Multi-developer lock system | D-068, D-220, D-226 | Medium | Designed (D-220) but deferred (D-226) — git merge conflicts sufficient. Revisit if team usage produces evidence of need |
| 8 | Checkpoint + reflection integration | Phase 10 | Medium | Reflection runs post-completion; checkpoint is mid-pipeline; need to decide what reflection data to preserve across sessions |
| 9 | Team-shared reflection observations | Phase 10 | Medium | Currently per-developer (gitignored); sharing requires merge strategy |
| 10 | Worktree isolation for parallel implementers | Phase 3 | Medium | Sequential execution is safe; worktrees enable true parallel safety |
| 11 | Rubric versioning/evolution | Phase 10 | Medium | Static rubrics sufficient for v1; evolution needs calibration data |
| 12 | L0/L1/L2 simplification | Architecture review | Low | "Revisit if L1 maintenance proves burdensome" — hasn't proven burdensome |

## Priority C — Research-Grade (Needs Accumulated Data)

| # | Item | Source | Effort | Prerequisites |
|---|------|--------|--------|---------------|
| 13 | Bayesian rule induction | Formal methods Tier C | High | History of reflection outcomes |
| 14 | Item Response Theory for LLM-judge | Formal methods Tier C | High | Large corpus of judge evaluations |
| 15 | Information-theoretic knowledge value | Formal methods Tier C | High | Outcome tracking infrastructure |
| 16 | ADWIN concept drift detection | Formal methods Tier C | High | Long observation series |
| 17 | Thompson Sampling for rule variants | Formal methods Tier C | High | Controlled experimentation framework |
| 18 | Adaptive budget allocation | Phase 7 | Medium | Usage data showing static budgets are insufficient |
| 19 | Formal methods suite (SPRT, CUSUM, BH correction, Markov retry, exponential decay) | D-094, D-111 | High | 100+ tasks of historical data. Spec preserved at `specs/archive/2026-03-16-formal-methods-*.md`. CPM kept for v1; these techniques deferred. |
| 20 | Art 5.3 constitutional language — "consistency check step" | Architecture review U-4 | Low | Consider softening to "structural consistency check step" to match D-042 implementation reality, or plan stronger semantic consistency checking |
| 21 | Reviewer behavioral defense monitoring | Architecture review S-7 | Medium | Track whether Themis's dual mandate (Q4 code quality + behavioral defense) causes behavioral defense items to be skipped under budget pressure. If so, consider lightweight structural "contract verifier" step for mechanical behavioral checks. |

## Not Applicable (Architectural Constraints)

These are NOT deferred — they are impossible or intentionally not designed:

- **Real-time token counting** — physically not feasible in Claude Code
- **Budget-based pipeline selection** — not designed by choice (classification determines pipeline)
- **MCP server install/config** — out of scope (Moira catalogs, doesn't install)
- **Runtime MCP call interception** — not possible in Claude Code
- ~~**PreToolUse hooks** — Claude Code only supports PostToolUse~~ **OUTDATED:** PreToolUse hooks are fully supported and extensively used by Moira (pipeline-dispatch.sh, guard-prevent.sh). Removed from this list.
- **Agent-level tool tracking** — guard.sh cannot distinguish orchestrator vs agent calls (mitigated via `agent_id` bypass, D-183)
