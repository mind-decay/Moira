# Moira System Audit Report
**Date:** 2026-03-16
**Scope:** Full system — agent architecture, pipelines & gates, schemas & state, design document cross-references

## Summary

| Severity | Count |
|----------|-------|
| Critical | 2     |
| High     | 9     |
| Medium   | 21    |
| Low      | 18    |
| **Total** | **50** |

**Overall health:** The system is structurally sound — all 10 agents have matching role YAMLs, knowledge access levels are consistent, and pipeline step sequences match design docs. However, there are two critical issues (max_attempts semantics ambiguity causing unreachable retry strategies, and Constitution naming violation), several high-severity gaps in agent constraint documentation, and a systemic issue where skills reference shell functions the orchestrator cannot execute. The most common pattern is **documentation drift** — `distribution.md` and `overview.md` have fallen behind implementation, and `agents.md` NEVER constraints are weaker than the corresponding role YAMLs.

---

## Critical

### C-01: E5-QUALITY retry strategies unreachable due to max_attempts semantics conflict
- **Files:**
  - `src/global/skills/errors.md` lines 233-249 (describes 2 retry strategies: Attempt 1 + Attempt 2)
  - `src/global/core/pipelines/standard.yaml` line 172 (`max_attempts: 2`)
  - `src/global/core/pipelines/full.yaml` line 192 (`max_attempts: 2`)
  - `design/architecture/pipelines.md` lines 99-101 ("max 2 attempts total")
- **Current state:** errors.md describes two escalating E5-QUALITY retry strategies: Attempt 1 (simple retry with feedback) and Attempt 2 (architect rethink). This requires 3 total executions (original + 2 retries). But `max_attempts: 2` in the pipeline YAMLs and "max 2 attempts total" in pipelines.md limit to 2 total executions, meaning the architect-rethink strategy (Attempt 2) can never be reached.
- **Target state:** Either `max_attempts: 3` in Standard/Full/Decomposition YAMLs with pipelines.md updated to "max 3 attempts total", OR errors.md simplified to a single retry strategy.
- **Fix:** Decide which is authoritative: errors.md's 2-strategy escalation or pipelines.md's "2 attempts total". If escalation is intended, change `max_attempts` to `3` in standard.yaml, full.yaml, decomposition.yaml, and update pipelines.md. If 2 total is intended, remove Attempt 2 from errors.md.

### C-02: Constitution "per-task" gate naming violated in implementation
- **Files:**
  - `design/CONSTITUTION.md` line 62 ("classification + architecture + decomposition + **per-task** + final")
  - `src/global/core/pipelines/decomposition.yaml` line 123 (`subtask_gate`)
  - `src/global/skills/gates.md` line 264 (`subtask_gate_{n}`)
- **Current state:** Constitution Art 2.2 uses "per-task" for the Decomposition Pipeline gate. Implementation uses "subtask_gate" / "subtask_gate_{n}". This is a naming violation of the supreme document.
- **Target state:** Implementation must align to the Constitution, or the Constitution must be amended by the user. Since agents cannot modify the Constitution, the YAML and gates.md should use `per_task_gate` / `per_task_gate_{n}`.
- **Fix:** Rename `subtask_gate` to `per_task_gate` in decomposition.yaml and `subtask_gate_{n}` to `per_task_gate_{n}` in gates.md. Grep for all "subtask_gate" references and update them.

---

## High

### H-01: Orchestrator cannot execute shell functions referenced in skills
- **Files:**
  - `src/global/skills/orchestrator.md` lines 26-29 (NEVER run bash)
  - `src/global/skills/errors.md` lines 176, 231, 305, 633-637
  - `src/global/skills/gates.md` lines 69, 113, 149, 184, 209, 242, 264, 294, 335, 413-419
  - `src/global/skills/dispatch.md` lines 197-204
- **Current state:** Multiple skills reference shell functions (`moira_state_gate`, `moira_state_transition`, `moira_state_agent_done`, `moira_budget_orchestrator_check`, `moira_budget_generate_report`, `moira_retry_should_retry`, `moira_metrics_collect_task`, etc.) as if the orchestrator calls them directly. But orchestrator.md Section 1 explicitly says the orchestrator NEVER runs bash commands, and `allowed-tools` excludes Bash. The mechanism for how the orchestrator performs these operations is undocumented.
- **Target state:** A documented mechanism explaining how the orchestrator achieves shell function effects — either by direct YAML reads/writes following the function logic, by hooks, or by delegating to an agent.
- **Fix:** Add a "State Management Mechanism" section to orchestrator.md or dispatch.md explaining that the orchestrator performs the equivalent YAML manipulations using Read/Write tools, with shell functions serving as canonical reference for the logic. Update gates.md, errors.md, and dispatch.md to use consistent language (e.g., "write the equivalent of `moira_state_gate()` updates to current.yaml and status.yaml").

### H-02: rules.sh response contract omits QUALITY line
- **Files:**
  - `src/global/lib/rules.sh` lines 470-476
  - `src/global/skills/dispatch.md` lines 79-84
- **Current state:** The response contract in rules.sh outputs STATUS, SUMMARY, ARTIFACTS, NEXT but omits the QUALITY line that dispatch.md specifies for agents with quality gate assignments.
- **Target state:** Response contract includes QUALITY line when quality gate is assigned.
- **Fix:** Add `QUALITY: <gate>=<verdict> (<critical>C/<warning>W/<suggestion>S) [only if quality gate assigned]` to the response contract in rules.sh around line 475.

### H-03: E6-AGENT max_attempts: 1 contradicts "retry 1x" intent
- **Files:**
  - `src/global/skills/errors.md` lines 307-312 ("Retry 1x"), line 325 ("attempt 2/2")
  - `src/global/core/pipelines/quick.yaml` line 112, `standard.yaml` line 177, `full.yaml` line 197, `decomposition.yaml` line 180 (all `max_attempts: 1`)
- **Current state:** errors.md says "Retry 1x" and shows "attempt 2/2" display template. If `max_attempts` means total attempts (as implied by E5-QUALITY "max 2 attempts total"), then `max_attempts: 1` means no retry at all.
- **Target state:** `max_attempts: 2` for E6-AGENT in all four pipeline YAMLs.
- **Fix:** Change `max_attempts` from `1` to `2` for E6-AGENT in all four pipeline YAML files.
- **Dependency:** Depends on resolving C-01 to establish definitive `max_attempts` semantics.

### H-04: Final gate options conflate completion actions with gate decisions
- **Files:**
  - `src/global/core/pipelines/quick.yaml` lines 69-79
  - `src/global/core/pipelines/standard.yaml` lines 135-145
  - `src/global/core/pipelines/full.yaml` lines 156-166
  - `src/global/core/pipelines/decomposition.yaml` lines 161-171
  - `src/global/skills/gates.md` lines 274-294, 410-418
- **Current state:** All four pipeline YAMLs list final gate options as `done`, `tweak`, `redo`, `diff`, `test`. But gates.md explicitly states: "The final gate is recorded as `proceed` via `moira_state_gate()`. Completion actions (done/tweak/redo/diff/test) are NOT gate decisions." Gate state management only accepts `proceed`/`modify`/`abort`.
- **Target state:** Final gate definitions in YAMLs should separate the gate decision (always `proceed`) from the post-gate completion action menu, or add a `type: completion_action` annotation to distinguish them from gate decisions.
- **Fix:** Add a `note: "These are completion actions, not gate decisions per gates.md. Gate is always recorded as proceed."` to the final_gate definition in all four pipeline YAMLs. Optionally restructure to `gate_decision: proceed` + `completion_actions: [done, tweak, redo, diff, test]`.

### H-05: Metis missing E10-DIVERGE enforcement NEVER constraint
- **Files:**
  - `design/architecture/agents.md` lines 126-140
  - `src/global/core/rules/roles/metis.yaml` lines 22-27
- **Current state:** agents.md requires Metis to "compare Explorer and Analyst data for factual contradictions" and report E10-DIVERGE if disagreement is found. The metis.yaml has no NEVER constraint enforcing this (e.g., "Never proceed with technical decisions when Explorer and Analyst data conflict without reporting E10-DIVERGE").
- **Target state:** A NEVER constraint in metis.yaml enforcing E10-DIVERGE.
- **Fix:** Add to metis.yaml never list: `"Never proceed with technical decisions when Explorer and Analyst data conflict -- report E10-DIVERGE"`. Add corresponding rule to agents.md.

### H-06: Hephaestus missing validation enforcement NEVER constraint
- **Files:**
  - `design/architecture/agents.md` line 199
  - `src/global/core/rules/roles/hephaestus.yaml` lines 28-34, 45-51
- **Current state:** agents.md says Hephaestus "runs post-implementation validation commands" and "fixes errors before returning STATUS: success." No NEVER constraint enforces this (e.g., "Never return STATUS: success when post-implementation validation commands have failed").
- **Target state:** NEVER constraint in both agents.md and hephaestus.yaml.
- **Fix:** Add `"Never return STATUS: success when post-implementation validation commands have failed"` to both agents.md Hephaestus rules and hephaestus.yaml never list.

### H-07: agents.md missing Apollo pipeline-selection prohibition in Rules list
- **Files:**
  - `design/CONSTITUTION.md` line 25 ("NEVER selects pipeline type")
  - `design/architecture/agents.md` lines 46-52 (Rules section for Apollo)
  - `src/global/core/rules/roles/apollo.yaml` line 25
- **Current state:** Constitution Art 1.2 says Classifier "NEVER selects pipeline type". apollo.yaml correctly includes this. But agents.md Rules list for Apollo omits it — there's only a note below the response format, not a formal rule.
- **Target state:** agents.md Apollo Rules section includes: "Does NOT select or specify the pipeline type."
- **Fix:** Add the rule to agents.md Apollo Rules section.

### H-08: pipelines.md gate summary omits architecture gate for Decomposition
- **Files:**
  - `design/architecture/pipelines.md` line 12
  - `design/CONSTITUTION.md` line 62 ("classification + architecture + decomposition + per-task + final")
  - `src/global/core/pipelines/decomposition.yaml` lines 94-107
- **Current state:** pipelines.md gate summary for Decomposition: `classify, decomp, per-task, final` (4 gates). Constitution and YAML both include architecture gate (5 gates).
- **Target state:** `classify, arch, decomp, per-task, final` in the summary table.
- **Fix:** Insert "arch" after "classify" in the Decomposition row.

### H-09: dispatch.md Assembly Path table omits Mnemosyne and Argus
- **Files:**
  - `src/global/skills/dispatch.md` lines 34-39 (Assembly Path table)
  - `src/global/skills/dispatch.md` lines 41-43 (prose note)
- **Current state:** Table lists 8 agents across pipelines but omits Mnemosyne (reflector) and Argus (auditor). Prose note below explains they use different dispatch paths, but the table is incomplete.
- **Target state:** Table includes all 10 agents with "dedicated dispatch" notation for Mnemosyne and Argus.
- **Fix:** Add rows for Mnemosyne and Argus to the Assembly Path table.

---

## Medium

### M-01: Multiple role YAMLs omit explicit null knowledge access entries
- **Files:**
  - `src/global/core/rules/roles/athena.yaml` lines 25-31 (missing `quality_map`, `libraries`)
  - `src/global/core/rules/roles/themis.yaml` lines 34-40 (missing `failures`, `libraries`)
  - `src/global/core/rules/roles/hephaestus.yaml` lines 36-43 (missing `decisions`, `quality_map`, `failures`)
  - `src/global/core/rules/roles/aletheia.yaml` lines 25-32 (missing `decisions`, `quality_map`, `failures`, `libraries`)
  - `src/global/core/rules/roles/daedalus.yaml` lines 49-56 (missing `failures`)
  - `src/global/core/knowledge-access-matrix.yaml` lines 12-21
- **Current state:** 5 of 10 role YAMLs omit null knowledge types that are explicit in the authoritative matrix. Only apollo.yaml and hermes.yaml list all 7 types.
- **Target state:** All role YAMLs list all 7 knowledge types explicitly.
- **Fix:** Add missing `null` entries to each affected YAML.

### M-02: YAML NEVER constraints systematically stronger than agents.md (6 agents)
- **Files:**
  - agents.md + YAML pairs for: Mnemosyne (G), Hephaestus (H), Themis (I), Argus (J), Aletheia (K), Daedalus (N)
- **Current state:** Six role YAMLs contain NEVER constraints not documented in agents.md. Examples:
  - Mnemosyne: "Never modify project source files" (YAML only)
  - Hephaestus: "Never add comments to unchanged code", "Never add features not in plan" (YAML only)
  - Themis: "Never modify project files", "Never suppress findings", "Never auto-approve" (YAML only)
  - Argus: "Never make changes -- only report findings", "Never suppress audit findings" (YAML only)
  - Aletheia: "Never skip running tests", "Never write brittle tests", "Never ignore test failures" (YAML only)
  - Daedalus: "Never skip dependency analysis" (YAML only)
- **Target state:** agents.md as the canonical reference should document all NEVER constraints.
- **Fix:** Backport all YAML-only NEVER constraints to agents.md for each affected agent.

### M-03: state.sh `last_confirmed` field name vs schema `last_task`
- **Files:**
  - `src/global/lib/state.sh` line 240
  - `src/schemas/status.schema.yaml` lines 117-121
  - `src/global/skills/orchestrator.md` line 208
- **Current state:** state.sh writes `last_confirmed` but schema defines field as `last_task`.
- **Target state:** Consistent field name `last_task`.
- **Fix:** Change `last_confirmed` to `last_task` in state.sh line 240.

### M-04: telemetry.schema.yaml incompatible with moira_yaml_validate
- **Files:**
  - `src/schemas/telemetry.schema.yaml` lines 1-3, 36, 54, 72-73
  - `src/global/lib/yaml-utils.sh` lines 316-464
- **Current state:** telemetry.schema uses nested `type: object` with `fields:` sub-structures and `type: integer` (not `number`). The validator only supports flat fields with types `string`, `number`, `enum`, `boolean`, `block`, `array`.
- **Target state:** Flatten telemetry.schema to dot-path notation and change `integer` to `number`.
- **Fix:** Rewrite telemetry.schema.yaml to use dot-path field names (e.g., `pipeline.type`) consistent with other schemas.

### M-05: metrics.schema.yaml uses `values:` instead of `enum:`
- **Files:**
  - `src/schemas/metrics.schema.yaml` lines 196-201
- **Current state:** `pipeline` and `size` fields use `values:` key for enum options. All other schemas use `enum:`.
- **Target state:** Consistent `enum:` key.
- **Fix:** Change `values:` to `enum:` on lines 196 and 200.

### M-06: errors.md E8-STALE fixed "20 tasks" threshold vs exponential decay confidence model
- **Files:**
  - `src/global/skills/errors.md` lines 433, 439
  - `src/global/lib/knowledge.sh` lines 455-496
- **Current state:** errors.md says stale = ">20 tasks since last confirmation". knowledge.sh uses exponential decay with `confidence <= 30` threshold (distance varies by knowledge type due to per-type lambda values).
- **Target state:** errors.md should reference confidence-based threshold, not a fixed task count.
- **Fix:** Update errors.md E8-STALE display to say "confidence below 30%" and reference the exponential decay model.

### M-07: Config freshness_days vs task-count-based freshness
- **Files:**
  - `src/schemas/config.schema.yaml` lines 119-122 (`freshness_days`, default: 30)
  - `src/global/skills/errors.md` lines 433-434 (">20 tasks")
  - `src/global/lib/knowledge.sh` lines 455-496 (exponential decay)
- **Current state:** Config has `freshness_days` (time-based), errors.md uses task-count, knowledge.sh uses exponential decay. Three different freshness models.
- **Target state:** Single authoritative freshness mechanism (exponential decay in knowledge.sh) with config field updated.
- **Fix:** Rename `freshness_days` to `freshness_confidence_threshold` (default: 30) in config.schema.yaml, or add the new field alongside. Update errors.md to match.
- **Dependency:** Related to M-06.

### M-08: Quick Pipeline has unreachable error handlers (E10-DIVERGE, E11-TRUNCATION pre_exec)
- **Files:**
  - `src/global/core/pipelines/quick.yaml` lines 126-135
  - `src/global/skills/errors.md` lines 516-519, 566-577
- **Current state:** quick.yaml includes E10-DIVERGE handler (requires Analyst + Architect, absent from Quick Pipeline) and E11-TRUNCATION pre_exec handler (requires Planner, absent from Quick Pipeline). Neither can trigger.
- **Target state:** Remove unreachable handlers or mark as `not_applicable: true`.
- **Fix:** Remove E10-DIVERGE from quick.yaml. Remove `pre_exec` block from E11-TRUNCATION in quick.yaml.

### M-09: E5-QUALITY max_attempts semantics unclear for Quick Pipeline
- **Files:**
  - `src/global/core/pipelines/quick.yaml` lines 104-108 (`max_attempts: 1`)
  - `src/global/skills/errors.md` line 291 ("single retry only")
  - `design/architecture/pipelines.md` line 40 ("max 1" retry)
- **Current state:** Quick Pipeline E5-QUALITY has `max_attempts: 1`. errors.md and pipelines.md both say "single retry" is allowed. If max_attempts means total attempts, `1` = no retry.
- **Target state:** `max_attempts: 2` for Quick Pipeline E5-QUALITY.
- **Fix:** Change to `max_attempts: 2`. Depends on C-01 semantics resolution.
- **Dependency:** Depends on C-01.

### M-10: Quality Checkpoint conditional gate not defined in pipeline YAMLs
- **Files:**
  - `src/global/skills/gates.md` lines 298-337
  - All pipeline YAML files
- **Current state:** gates.md defines a "Quality Checkpoint" conditional gate (presented when quality-gate agent returns fail_warning). No pipeline YAML defines it.
- **Target state:** Either add `conditional_gates:` section to pipeline YAMLs, or document that conditional gates live only in gates.md.
- **Fix:** Add a note to each pipeline YAML or to gates.md clarifying that conditional gates are not part of the pipeline step sequence and are defined only in gates.md.

### M-11: budget.sh missing role definition fallback in agent budget resolution
- **Files:**
  - `src/global/lib/budget.sh` lines 39-61
  - `src/global/skills/dispatch.md` lines 258-259
- **Current state:** dispatch.md specifies 3-level fallback: budgets.yaml -> config.yaml -> role definition. budget.sh only does budgets.yaml -> config.yaml -> hardcoded defaults, never reading the role definition's budget field.
- **Target state:** budget.sh includes role definition lookup, or dispatch.md documents actual fallback chain.
- **Fix:** Add role YAML budget field lookup between config.yaml and hardcoded defaults in budget.sh.

### M-12: orchestrator.md Reflection Dispatch table uses confusing "Pipeline Value" header
- **Files:**
  - `src/global/skills/orchestrator.md` lines 315-319
- **Current state:** Table maps reflection dispatch modes (`lightweight`, `background`, `deep`, `epic`) under a "Pipeline Value" header. These don't match the pipeline enum (`quick`, `standard`, `full`, `decomposition`).
- **Target state:** Header should say "Reflection Mode" with mapping note.
- **Fix:** Rename column header and add mapping note.

### M-13: overview.md data flow shows wrong path prefix `.moira/` instead of `.claude/moira/`
- **Files:**
  - `design/architecture/overview.md` line 67
- **Current state:** Classifier data flow shows `.moira/state/tasks/{id}/classification.md`.
- **Target state:** `.claude/moira/state/tasks/{id}/classification.md` per D-061.
- **Fix:** Update path prefix.

### M-14: dispatch.md references shell functions as "patterns" the orchestrator can't call
- **Files:**
  - `src/global/skills/dispatch.md` lines 197-204
  - `src/global/lib/state.sh` lines 46-91, 142-188
- **Current state:** dispatch.md says "Use `moira_state_transition()` pattern" — these are actual shell functions the orchestrator cannot call.
- **Target state:** Reword to explain orchestrator performs equivalent YAML writes.
- **Fix:** Reword lines 197-204 to describe YAML field updates directly.
- **Dependency:** Related to H-01.

### M-15: Quick Pipeline test option dispatches Aletheia without a defined Tester step
- **Files:**
  - `src/global/core/pipelines/quick.yaml` lines 69-79
  - `design/architecture/pipelines.md` lines 26-61
- **Current state:** Final gate `test` option dispatches Aletheia ad-hoc, but Quick Pipeline has no Tester step. This works as a completion action but is undocumented.
- **Target state:** Document that `test` dispatches Aletheia outside the pipeline step sequence.
- **Fix:** Add comment in quick.yaml final_gate.

### M-16: distribution.md missing multiple file entries vs overview.md and implementation
- **Files:**
  - `design/architecture/distribution.md` lines 228-289
  - `design/architecture/overview.md` lines 114-164
- **Current state:** distribution.md is missing: `metrics.schema.yaml`, `audit.schema.yaml` (schemas section); `retry.sh`, `audit.sh`, `metrics.sh` (lib section); `audit/` (templates section); `xref-manifest.yaml` (core section). Total: 8 missing entries.
- **Target state:** distribution.md matches overview.md and implementation.
- **Fix:** Add all 8 missing entries to distribution.md.

### M-17: No upgrade.md command file despite documented `/moira upgrade` command
- **Files:**
  - `design/architecture/commands.md` lines 100-108
  - `design/architecture/distribution.md` lines 279-289
- **Current state:** commands.md documents `/moira upgrade`. No implementation exists. Roadmap Phase 12 includes it.
- **Target state:** commands.md and distribution.md should annotate this as a Phase 12 deliverable.
- **Fix:** Add "Phase 12 deliverable" annotation to both documents.

### M-18: Hermes (Explorer) missing explicit "never interpret findings" NEVER constraint
- **Files:**
  - `design/CONSTITUTION.md` line 26 ("reports facts")
  - `src/global/core/rules/roles/hermes.yaml` lines 21-26
- **Current state:** Constitution says Explorer "reports facts". YAML has "Never propose solutions" and "Never express opinions" but no explicit "Never interpret findings" or "Never draw conclusions". Identity block says "report FACTS only" but this is weaker than a NEVER constraint.
- **Target state:** Add "Never interpret or draw conclusions from findings" to NEVER list.
- **Fix:** Add to hermes.yaml never list and agents.md Hermes rules.

### M-19: overview.md missing scaffold template subdirectories
- **Files:**
  - `design/architecture/overview.md` lines 128-133
  - `src/global/lib/scaffold.sh` lines 27-29
- **Current state:** overview.md lists `templates/reflection/` and `templates/judge/` but scaffold.sh doesn't create them. scaffold.sh creates `templates/scanners`, `templates/knowledge`, `templates/audit` but misses `templates/reflection/`, `templates/judge/`, `templates/scanners/deep/`.
- **Target state:** scaffold.sh creates all directories listed in overview.md.
- **Fix:** Add missing `mkdir -p` calls to scaffold.sh.

### M-20: Standard Pipeline max_attempts semantics — errors.md describes 2 retry strategies vs YAML max_attempts: 2
- **Files:**
  - `src/global/skills/errors.md` lines 233-249
  - `src/global/core/pipelines/standard.yaml` line 172
- **Current state:** Same as C-01. errors.md "Attempt 1" and "Attempt 2" naming is ambiguous — could mean 2 retries (3 total) or 2 total attempts (1 retry).
- **Target state:** Add semantic comment to `max_attempts` field: "Total attempts including original (not retry count)".
- **Fix:** Add comment to all pipeline YAMLs at `max_attempts` fields clarifying semantics.
- **Dependency:** Depends on C-01.

### M-21: gates.md references shell functions the orchestrator can't execute
- **Files:**
  - `src/global/skills/gates.md` lines 113, 149, 184, 209, 242, 264, 294, 337, 413-419
- **Current state:** gates.md uses `moira_state_gate("gate_name", decision)` as if the orchestrator calls it directly.
- **Target state:** Describe YAML writes instead of shell function calls.
- **Fix:** Related to H-01. Rewrite gate state management section to describe YAML field updates.
- **Dependency:** Depends on H-01.

---

## Low

### L-01: Apollo NEXT example in agents.md could be confused with pipeline selection
- **Files:** `design/architecture/agents.md` lines 37-42, line 44
- **Fix:** Add clarifying comment that NEXT is a step recommendation, not pipeline selection.

### L-02: dispatch.md Agent-to-Gate Mapping table doesn't note omitted agents
- **Files:** `src/global/skills/dispatch.md` lines 272-278
- **Fix:** Add note: "Agents not listed (Apollo, Hermes, Hephaestus, Mnemosyne, Argus) have no quality gate."

### L-03: Knowledge access path mapping exists only in dispatch.md
- **Files:** `src/global/skills/dispatch.md` lines 325-337, `src/global/core/knowledge-access-matrix.yaml`
- **Fix:** Consider adding path mapping to knowledge-access-matrix.yaml or cross-reference.

### L-04: pipelines.md context thresholds imprecise vs orchestrator.md 4-tier model
- **Files:** `design/architecture/pipelines.md` lines 297-298, `src/global/skills/orchestrator.md` lines 233-236
- **Fix:** Update pipelines.md to reference orchestrator.md Section 6 for authoritative thresholds.

### L-05: Config `budgets.orchestrator_max_percent` naming misleading
- **Files:** `src/schemas/config.schema.yaml` lines 55-59
- **Fix:** Rename to `orchestrator_healthy_threshold` or update default to match warning threshold. Low priority (field is reserved).

### L-06: Config reserved `pipelines.*.max_retries` fields unused
- **Files:** `src/schemas/config.schema.yaml` lines 35-54
- **Fix:** Add roadmap phase reference or remove.

### L-07: Config missing `classification.confidence_override` field
- **Files:** `src/schemas/config.schema.yaml` lines 25-33
- **Fix:** Add comment clarifying confidence is classifier-determined only.

### L-08: Decomposition architecture gate variant not documented in gates.md
- **Files:** `src/global/core/pipelines/decomposition.yaml` lines 96-107, `src/global/skills/gates.md`
- **Fix:** Add note to gates.md Architecture Gate section specifying Decomposition uses Standard variant.

### L-09: overview.md missing `bench.sh` and `retry.sh` in lib listing
- **Files:** `design/architecture/overview.md` lines 147-164
- **Fix:** Add both files to the listing.

### L-10: overview.md missing audit.md skill reference in dispatch.md
- **Files:** `design/architecture/overview.md` lines 116-120, `src/global/skills/dispatch.md` line 43
- **Fix:** Clarify in dispatch.md that audit command is `~/.claude/commands/moira/audit.md`.

### L-11: status.schema.yaml completion.action includes intermediate actions (diff, test)
- **Files:** `src/schemas/status.schema.yaml` lines 122-126, `src/schemas/telemetry.schema.yaml` lines 131-133
- **Fix:** Add description clarifying status tracks last action (including intermediate), telemetry tracks terminal only.

### L-12: overview.md project layer "Layer 1" comment misleading
- **Files:** `design/architecture/overview.md` line 184
- **Fix:** Change to "project-adapted copy" instead of "universal rules".

### L-13: overview.md missing state files (proposals.yaml, budget-accuracy.yaml, retry-stats.yaml, audit-pending.yaml)
- **Files:** `design/architecture/overview.md` (project layer tree), various lib files
- **Fix:** Add all four files to the state/ listing.

### L-14: overview.md missing audit YAML file formats in state/audits/
- **Files:** `design/architecture/overview.md` line 275
- **Fix:** Add `{date}-audit.yaml` and `{date}-{domain}.yaml` to the listing.

### L-15: Config mcp.registry_path field orphaned (never read by mcp.sh)
- **Files:** `src/schemas/config.schema.yaml` line 147, `src/global/lib/mcp.sh` line 26
- **Fix:** Add comment noting field is reserved.

### L-16: Roadmap inconsistent completion indicators
- **Files:** `design/IMPLEMENTATION-ROADMAP.md` line 190
- **Fix:** Either mark all completed phases or remove the Phase 10 checkmark.

### L-17: Active spec files not indexed in SYSTEM-DESIGN.md
- **Files:** `design/SYSTEM-DESIGN.md`, `design/specs/2026-03-16-*.md`
- **Fix:** Add "Current Implementation Specs" subsection to SYSTEM-DESIGN.md.

### L-18: self-protection.md gate naming convention not documented
- **Files:** `design/subsystems/self-protection.md` lines 248-253
- **Fix:** Add note explaining relationship between short gate names and YAML `_gate` suffix IDs.

---

## Fix Dependency Graph

```
C-01 (max_attempts semantics)
├── H-03 (E6-AGENT max_attempts)
├── M-09 (Quick E5 max_attempts)
└── M-20 (semantics comment)

H-01 (orchestrator shell function mechanism)
├── M-14 (dispatch.md reword)
└── M-21 (gates.md reword)

M-06 (E8-STALE threshold) ── M-07 (config freshness field)
```

All other findings are independent.

## Parallel Fix Groups

**Group A — Critical semantics (do first):**
- C-01: Resolve max_attempts semantics
- C-02: Rename subtask_gate to per_task_gate

**Group B — Orchestrator mechanism (after C-01):**
- H-01: Document orchestrator state management mechanism
- H-03: Fix E6-AGENT max_attempts (after C-01)
- M-14, M-21: Reword shell function references (after H-01)
- M-09, M-20: Fix Quick E5 + add semantics comments (after C-01)

**Group C — Agent constraints (independent):**
- H-05, H-06, H-07: Add missing NEVER constraints
- M-02: Backport YAML constraints to agents.md
- M-18: Add Hermes "never interpret" constraint

**Group D — Pipeline YAML fixes (independent, after C-01):**
- H-04: Final gate completion action annotation
- H-08: pipelines.md gate summary
- H-09: dispatch.md Assembly Path table
- M-08: Remove unreachable Quick Pipeline handlers
- M-10: Quality Checkpoint documentation
- M-15: Quick Pipeline test option documentation

**Group E — Schema fixes (independent):**
- H-02: rules.sh QUALITY line
- M-03: state.sh field name
- M-04: telemetry.schema flattening
- M-05: metrics.schema enum key
- M-06, M-07: Freshness model alignment
- M-11: budget.sh role definition fallback

**Group F — Knowledge access YAMLs (independent):**
- M-01: Add missing null entries to role YAMLs

**Group G — Documentation drift (independent):**
- M-12, M-13, M-16, M-17, M-19: overview.md + distribution.md updates
- L-01 through L-18: Low-priority documentation fixes
