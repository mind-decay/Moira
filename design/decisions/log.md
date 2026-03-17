# Decision Log

All architectural decisions made during Moira system design.

---

## D-001: Orchestrator Never Executes

**Context:** How should main Claude interact with project code?
**Decision:** Main Claude is a pure orchestrator — never reads/writes project files, never runs commands.
**Alternatives rejected:**
- Hybrid mode (orchestrator can do simple tasks) — breaks predictability, encourages rationalization
- Orchestrator reads but doesn't write — still pollutes context
**Reasoning:** Minimal orchestrator context = no hallucination. Strict boundary = predictable behavior.

## D-002: File-Based Agent Communication

**Context:** How should agents communicate results to orchestrator?
**Decision:** Agents write detailed results to files, return only status summary to orchestrator.
**Alternatives rejected:**
- Full results in return message — pollutes orchestrator context
- Shared memory/state — not available in Claude Code architecture
**Reasoning:** File-based communication keeps orchestrator context clean. Agents can produce arbitrarily detailed output without impacting orchestrator.

## D-003: Deterministic Pipelines

**Context:** Should the system dynamically decide execution flow or follow fixed pipelines?
**Decision:** Fixed pipeline per task size (Quick/Standard/Full/Decomposition).
**Alternatives rejected:**
- Dynamic planning (system decides flow per task) — unpredictable, hard to debug
- Single pipeline for all (with skip-gates) — over-engineering for small tasks
**Reasoning:** Predictability requires determinism. Same input type = same execution path. Engineer knows what to expect.

## D-004: Approval Gates at Key Decision Points

**Context:** How much autonomy should the system have?
**Decision:** Gates at classification, architecture, plan, and final review. No full autonomy.
**Alternatives rejected:**
- Full autonomy — vibe coding, unpredictable
- Gate at every step — too many interruptions, slows work
- Confidence-based auto-approval — introduces unpredictability
**Reasoning:** Engineers should focus on WHAT not HOW, but must approve KEY decisions. Gates are at points where wrong decisions are most costly to fix.

## D-005: Modular Rules System (4 layers)

**Context:** How to structure agent rules across projects?
**Decision:** 4-layer system: Base (universal) → Role (per agent) → Project → Task-specific.
**Alternatives rejected:**
- Monolithic per-agent files — duplication, hard to maintain
- 2-layer (global + project) — not granular enough
**Reasoning:** Modular system allows DRY rules, project-specific overrides, and per-task customization. Planner assembles rules for each agent invocation.

## D-006: Three-Level Knowledge Documentation

**Context:** How to make knowledge useful without consuming context budget?
**Decision:** L0 (index, ~100-200 tokens) → L1 (summary, ~500-2k) → L2 (full, ~2-10k). Each agent loads only the level it needs.
**Alternatives rejected:**
- Single-level (always full) — wastes context budget
- Two-level (summary + full) — index useful for agents that need minimal context
**Reasoning:** Different agents need different depth. Explorer needs almost nothing (unbiased). Implementer needs full conventions. This matrix optimizes budget per agent.

## D-007: Hybrid Knowledge Bootstrapping

**Context:** How to initialize knowledge for a new project?
**Decision:** Quick scan at init (~2-3 min) + deep scan in background during first tasks.
**Alternatives rejected:**
- Deep scan at init (20+ min) — too slow for first use
- No init, organic only — first tasks have no context, may go wrong
**Reasoning:** Quick scan provides enough for first tasks. Deep scan runs without blocking. Organic growth fills gaps over time.

## D-008: Smart Batching with Contract Interfaces

**Context:** How to parallelize multi-file implementation?
**Decision:** Planner builds dependency graph, clusters independent files, defines contracts between dependent batches.
**Alternatives rejected:**
- One agent for all files — context budget risk on large tasks
- One agent per file — loses cross-file coherence
**Reasoning:** Semantic batches preserve coherence within batch. Contracts prevent conflicts between batches. Shared files go to final batch.

## D-009: Branch-Scoped State, Shared Knowledge

**Context:** How to handle multiple developers?
**Decision:** Task state is branch-scoped (gitignored). Knowledge is shared (git-tracked, merges with PRs).
**Alternatives rejected:**
- Everything shared — state conflicts between developers
- Everything isolated — knowledge doesn't accumulate
**Reasoning:** State is per-session, per-task, per-developer. Knowledge benefits everyone and should merge through standard git flow.

## D-010: Controlled Quality Evolution

**Context:** Should the system improve existing code patterns?
**Decision:** Two modes: CONFORM (default, follow patterns) and EVOLVE (explicit, systematic improvement). Evolution requires evidence threshold + user approval.
**Alternatives rejected:**
- Always improve — creates chaos, inconsistency
- Never improve — project stagnates
- Automatic improvement — no human oversight
**Reasoning:** Consistency > perfection for daily work. Evolution happens when evidence is strong and scope is controlled.

## D-011: Batch Audit Approval by Risk Level

**Context:** How to approve audit recommendations?
**Decision:** Low-risk: batch apply with confirmation. Medium: individual approval. High: detailed review required.
**Alternatives rejected:**
- All individual — too slow for low-risk items
- All batch — risky for high-impact changes
**Reasoning:** Proportional approval reduces overhead while maintaining safety for impactful changes.

## D-012: Tiered Audit Depth

**Context:** How often and how deep should audits run?
**Decision:** Light audit every 10 tasks (passive), standard every 20 (or manual), deep on upgrade/quarterly.
**Alternatives rejected:**
- Always deep — wastes tokens and time
- Only manual — issues accumulate undetected
**Reasoning:** Most issues caught by light/standard audit. Deep audit reserved for significant events.

## D-013: Self-Contained System

**Context:** Should Moira depend on external skill systems (GSD, Superpowers, etc.)?
**Decision:** Moira is self-contained with no external dependencies.
**Alternatives rejected:**
- Build on GSD — external changes could break Moira
- Integrate Superpowers — creates coupling
**Reasoning:** Independence ensures stability. External system changes cannot break Moira.

## D-014: Escape Hatch with Explicit Activation Only

**Context:** Should engineers be able to bypass the pipeline?
**Decision:** Yes, but only through `/moira bypass:` command with explicit "2" confirmation. Cannot be triggered by prompt manipulation.
**Alternatives rejected:**
- No bypass — too rigid for experienced engineers
- Easy bypass — becomes default, undermines system
**Reasoning:** Availability reduces friction. Friction to activate prevents misuse. Audit tracks usage for quality correlation.

## D-015: Foreground Sequential, Background Parallel

**Context:** How to spawn agents — foreground (blocking) or background?
**Decision:** Sequential pipeline steps: foreground. Parallel batches: background. Post-task reflection: background.
**Alternatives rejected:**
- All foreground — can't parallelize independent work
- All background — orchestrator can't make step-dependent decisions
**Reasoning:** Quality requires seeing each step's result before deciding next step. Speed comes from parallelizing independent batches.

## D-016: User Documentation Inside Moira

**Context:** How to help users learn the system?
**Decision:** Built-in help system (`/moira help <topic>`) + micro-onboarding + progressive disclosure.
**Alternatives rejected:**
- External docs only — hard to access during work
- No docs, intuitive UX only — complex system needs reference
**Reasoning:** Help at point of use is most effective. Progressive disclosure prevents overwhelm.

## D-017: Constitutional Invariants for Self-Protection

**Context:** How to prevent the system from degrading during iterative development?
**Decision:** Three-layer defense: regression detection + design conformance + constitutional verification. Constitution defines binary pass/fail invariants that cannot be violated.
**Alternatives rejected:**
- Tests only — can't catch architectural violations, only functional ones
- Code review only — relies on reviewer catching every invariant, not systematic
- No formal protection — "we'll be careful" is not a strategy
**Reasoning:** Moira is complex enough that accidental degradation is inevitable without structural protection. Constitution makes invariants explicit and verifiable. Three layers catch different types of regression.

## D-018: Design-First Development Protocol

**Context:** What happens when implementation needs to deviate from design?
**Decision:** Design documents MUST be updated FIRST (with user approval), THEN implementation follows. Never implement first and document later.
**Alternatives rejected:**
- Implementation-first — design docs become stale, divergence grows
- No formal protocol — leads to "I'll update docs later" which never happens
**Reasoning:** Design documents are the source of truth. If they diverge from implementation, nobody knows which is correct. Design-first ensures intentional evolution.

## D-019: Risk-Classified Change Management

**Context:** Should all changes go through the same review process?
**Decision:** Four risk levels (RED/ORANGE/YELLOW/GREEN) with proportional verification requirements.
**Alternatives rejected:**
- All changes equal — too slow for safe changes, not careful enough for dangerous ones
- No classification — developers guess what needs extra attention
**Reasoning:** Proportional effort. Typo fix shouldn't need constitutional review. Pipeline gate removal absolutely should.

## D-020: File-Copy Distribution Model

**Context:** How should users install Moira?
**Decision:** Single shell script (`install.sh`) that copies files to `~/.claude/moira/`. No package manager, no build step, no runtime dependencies beyond Claude Code + git + bash.
**Alternatives rejected:**
- npm package — adds Node.js dependency, unnecessary complexity for non-JS projects
- Homebrew formula — platform-specific, adds maintenance burden
- Claude Code plugin/extension system — doesn't exist yet, can't depend on future features
- Docker — absurd overhead for config files
**Reasoning:** Moira is just markdown + YAML + shell scripts. Installation = file copy. Simplest possible distribution. Works on any OS with Claude Code. Install in <30 sec.

## D-021: Verification Agents for Moira Development

**Context:** How to automate the three-layer verification?
**Decision:** Two dedicated agents: moira-verifier (post-change) and moira-impact-analyzer (pre-change). Defined in AGENTS.md for the Moira project itself.
**Alternatives rejected:**
- Manual verification only — humans miss things, especially after long sessions
- CI/CD pipeline — not available in Claude Code context
- Single agent for everything — too much responsibility, unclear output
**Reasoning:** Pre-change analysis prevents bad changes from being made. Post-change verification catches what slipped through. Two agents with clear roles match Moira's own design philosophy.

## D-022: Project Config via Git, State via Gitignore

**Context:** What gets committed to the project repo?
**Decision:** Project rules, knowledge, config, metrics → committed (shared with team). Task state, locks, bypass log → gitignored (per-developer).
**Alternatives rejected:**
- Everything committed — task state conflicts between developers
- Nothing committed — each developer re-bootstraps from scratch, no shared knowledge
- Separate config repo — adds complexity for no benefit
**Reasoning:** Rules and knowledge benefit the whole team. Task state is per-session and per-developer. Git is the natural sharing mechanism for team config. Second developer joining project gets all accumulated knowledge instantly.

## D-023: Layered Testing Architecture

**Context:** How to test both orchestration correctness and agent output quality?
**Decision:** Three-layer architecture: Structural Verifier (bash, 0 tokens, deterministic), Behavioral Bench (full Moira runs on fixtures, LLM-judge), Live Telemetry (passive metrics during real use).
**Alternatives rejected:**
- Test-as-Pipeline (testing as another Moira pipeline) — circular dependency, broken Moira = broken tests
- External Harness (separate tool outside Moira) — duplicates orchestration logic, two things to maintain
**Reasoning:** Structural layer is independent (works even if Moira is broken). Behavioral layer tests real behavior without duplication. Live layer is nearly free. Each layer catches different failure modes.

## D-024: LLM-Judge with Anchored Rubrics

**Context:** How to evaluate stochastic agent output quality objectively?
**Decision:** Separate Claude call evaluates results against rubrics with concrete anchored examples per score level (1-5). Hybrid approach: automated checks (compile/lint) as hard pass/fail, LLM-judge for qualitative assessment.
**Alternatives rejected:**
- Automated checks only — too shallow, passing lint doesn't mean good code
- Free-form LLM evaluation — too noisy, unpredictable scores
- Structured rubric without anchors — less calibrated, subjective interpretation of scale
**Reasoning:** Anchored examples minimize judge subjectivity. Calibration set validates judge stability. Judge SHOULD use a different model tier than agents when budget allows; same-tier evaluation is acceptable but marked in reports. Model tiers (not pinned versions) are specified in design to avoid staleness.

## D-025: Statistical Confidence Bands for Metrics

**Context:** How to distinguish real regressions from stochastic noise in LLM outputs?
**Decision:** Baseline + variance tracking per metric. Three zones: NORMAL (within band, ignore), WARN (1-2σ, observe), ALERT (>2σ, investigate). Minimum effect size threshold prevents reacting to insignificant changes.
**Alternatives rejected:**
- Fixed thresholds — don't account for natural variance per metric
- Multiple runs per test — too expensive in tokens
- No statistical model — every fluctuation looks like regression
**Reasoning:** Accumulation over time builds statistical profile cheaply. Cold start protocol handles initial lack of data. Deterministic checks separated entirely (binary, no variance).

## D-026: Tiered Test Execution by Change Risk

**Context:** When to run full bench vs quick checks?
**Decision:** Three tiers: Tier 1 (structural smoke, 0 tokens, always), Tier 2 (targeted bench, 3-5 tests, for prompt/rule changes), Tier 3 (full bench, all tests, for pipeline/gate/role boundary changes). Auto-detected from git diff, user can override.
**Alternatives rejected:**
- Always full bench — too expensive, burns token budget
- Always smoke only — misses behavioral regressions
- Manual selection only — requires user to know which tests matter
**Reasoning:** Proportional testing matches Moira's own risk classification (RED/ORANGE/YELLOW/GREEN). Budget guards prevent runaway spending.

## D-027: Privacy-First Live Telemetry

**Context:** How to collect metrics from real projects without leaking sensitive data?
**Decision:** Record only numbers and enums, never content. Three privacy levels: local-only (default), anonymized export (opt-in), team sharing (aggregates only). Sanitization pipeline rejects unexpected strings.
**Alternatives rejected:**
- No live telemetry — lose the most valuable real-world signal
- Full logging — privacy risk, storage bloat
- Opt-in only — most users won't opt in, insufficient data
**Reasoning:** Default-safe (local-only, gitignored) builds trust. Metrics without content is sufficient for all decision-making. Sanitization catches bugs that might leak content.

## D-028: Classifier as Full Agent

**Context:** pipelines.md references a Classifier agent but agents.md doesn't define it. Is it a separate agent or orchestrator function?
**Decision:** Classifier is the 10th agent (8 base + Auditor + Classifier) with full role definition, NEVER constraints, and budget allocation.
**Alternatives rejected:**
- Orchestrator-embedded classification — violates Art 1.1 (orchestrator purity), creates exception to "orchestrator never executes"
**Reasoning:** Preserves Art 1.1 completely. Consistent with architecture principle that all work is done by agents. Classification is a decision that benefits from knowledge context (L1 access).

## D-029: Full YAML Schemas Upfront

**Context:** Five state files (manifest.yaml, current.yaml, queue.yaml, config.yaml, status.yaml) referenced throughout design but no schemas defined. Should we define them minimally or fully?
**Decision:** Full schemas designed upfront for all 12 phases.
**Alternatives rejected:**
- Minimal schemas (Phase 1-3 only) — requires schema migration later, risks ad-hoc decisions
- Minimal + reserved sections — false precision for unknown fields
**Reasoning:** Per D-018, design documents must be updated first. Inventing schemas during implementation = making architectural decisions ad-hoc. Full schemas prevent this. All 12 phases have enough design context to specify fields now.

## D-030: Native Custom Commands for Distribution

**Context:** How to make `/moira` commands available to users?
**Decision:** Use Claude Code native custom commands (`~/.claude/commands/moira/*.md`). Same file convention as GSD, but zero GSD runtime dependency.
**Alternatives rejected:**
- Plugin system (marketplace) — requires marketplace infrastructure, overkill for v1
- CLAUDE.md-only — no slash command entry points, poor UX
- GSD runtime dependency — violates D-013 (self-contained)
**Reasoning:** Custom commands are a native Claude Code feature. File-based discovery (markdown + YAML frontmatter). `install.sh` copies files — consistent with D-020 (file-copy distribution). No external dependencies — consistent with D-013.

## D-031: Three-Layer Guard Mechanism

**Context:** Design assumed PreToolUse hooks for blocking orchestrator violations. Research confirmed PreToolUse does not exist in Claude Code — only PostToolUse.
**Decision:** Three-layer defense replacing single guard.sh:
1. `allowed-tools` in command frontmatter (prevention — orchestrator physically cannot call Edit/Grep/Glob/Bash)
2. PostToolUse `guard.sh` hook (detection — logs violations, injects warning into context)
3. CLAUDE.md prompt enforcement (guidance — inviolable rules about orchestrator boundaries)
**Alternatives rejected:**
- Prompt-only enforcement — no structural guarantee, relies on model compliance
- PostToolUse with rollback — too complex, cannot undo all side effects
**Reasoning:** `allowed-tools` is stronger than PreToolUse would have been — it prevents the tool from being available at all, not just blocking individual calls. PostToolUse provides audit trail for constitutional verification (Art 6.3). Prompt rules are defense-in-depth.

## D-032: Bootstrap Scanners as Explorer Invocations

**Context:** knowledge.md introduces 4 scanner agents (Tech, Structure, Convention, Pattern) not defined in agents.md. Should they be new agent types?
**Decision:** Scanners are Explorer agent invocations with different task-specific instructions (Layer 4 rules). No new agent types.
**Alternatives rejected:**
- 4 separate agents — agent proliferation (13 total), each scanner does exactly what Explorer does
- Single Scanner agent with mode parameter — unnecessary abstraction for 4 invocations
**Reasoning:** Explorer's role is "reads code, reports facts — NEVER proposes solutions." Scanning is exactly this. Layer 4 instructions customize what facts to report. Consistent with D-005 (modular rules, Layer 4 = task-specific). No new NEVER constraints needed — Explorer's existing constraints apply.

## D-033: Locks in Committed Zone with TTL

**Context:** locks.yaml was in gitignored state/ directory, but locks must be visible across developers.
**Decision:** Move locks.yaml to committed config zone (`.claude/moira/config/locks.yaml`). Add TTL (`expires_at` field) for stale lock detection.
**Alternatives rejected:**
- Keep in gitignored state — defeats purpose of locks (invisible to other developers)
- External lock service — violates D-013 (self-contained)
- Shared network file — requires infrastructure beyond git
**Reasoning:** Locks exist for cross-developer coordination. Must be in git to be shared. TTL prevents permanent locks from crashed sessions. Stale lock detection runs during audit (D-012). Standard git merge handles conflicts.

## D-034: Greek Mythology Naming System

**Context:** System needs a memorable, unique, viral-friendly identity. Original name "Forge" is overloaded (SourceForge, Electron Forge, Minecraft Forge, etc.), has poor SEO, and doesn't convey orchestration.
**Decision:** Rename system to **Moira** (the three Fates). All agents, components, and pipeline phases named after Greek mythological figures. Every name displayed as `Name (role)` format — always, everywhere, no exceptions.
**Alternatives rejected:**
- Keep "Forge" — poor googlability, crowded namespace, no mythological depth for subsystem naming
- Latin/Norse mythology — Greek has strongest cultural recognition and largest namespace
- Abstract tech names — forgettable, no narrative cohesion
**Reasoning:** Greek mythology provides: (1) meaningful metaphors (three Fates = three pipeline phases), (2) vast extensible namespace, (3) cultural resonance that aids memorability and word-of-mouth, (4) unique identity in dev tooling space. The `Name (role)` convention ensures mythology never becomes a barrier to understanding. Full mapping in `architecture/naming.md`.

## D-035: Pipeline Definitions as Separate YAML Files

**Context:** Where should pipeline step sequences and gate definitions live — inline in the orchestrator skill or as separate data files?
**Decision:** Separate YAML files in `core/pipelines/` (quick.yaml, standard.yaml, full.yaml, decomposition.yaml). Orchestrator reads the appropriate definition at runtime.
**Alternatives rejected:**
- Inline in orchestrator skill — mixes data with logic, not independently testable, harder to diff
- Single pipelines.yaml — all 4 pipelines in one file makes targeted testing harder
**Reasoning:** Separation of data from logic. Pipeline definitions are independently testable by Tier 1 structural checks. Changes are detectable by git diff for D-026 trigger matrix. One file per pipeline type matches the deterministic selection model (Art 2.1).

## D-036: Extended Pipeline State Steps

**Context:** `state.sh` defines valid pipeline steps for `moira_state_transition()`. Original set (Phase 1): classification, exploration, analysis, architecture, plan, implementation, review, testing, reflection. Phase 3 pipelines require additional steps.
**Decision:** Add three step names: `decomposition` (Planner decomposes epic), `integration` (cross-phase/cross-task verification), `completion` (final gate + post-pipeline actions).
**Alternatives rejected:**
- Reuse existing names (e.g., `plan` for decomposition) — semantically wrong, confuses state tracking
- Free-form step names without validation — loses determinism guarantee, any typo silently passes
**Reasoning:** State machine step names must be explicit and validated. Each new step corresponds to a distinct pipeline phase that doesn't map to existing names. Validation prevents silent errors.

## D-037: Final Gate Completion Actions Separate from Gate Decisions

**Context:** `moira_state_gate()` validates gate decisions as proceed/modify/abort. But the final gate offers done/tweak/redo/diff/test — these don't fit the gate decision model.
**Decision:** Final gate completion actions are NOT gate decisions. When user chooses any completion action, the gate is recorded as `proceed`. The completion action (done/tweak/redo/diff/test) triggers a separate orchestrator flow after the gate record.
**Alternatives rejected:**
- Extend `moira_state_gate()` to accept completion actions — mixes gate semantics (approve/reject/modify) with post-completion flow control
- Don't record the final gate — violates Art 3.1 (all decisions traceable)
**Reasoning:** Gates are approval checkpoints (Art 2.2). Completion actions are workflow routing. Keeping them separate preserves clean gate semantics and allows state.sh to remain simple and validated. The completion action is tracked separately in status.yaml `completion.action` field (already in schema).

## D-038: E7/E8 Error Stubs in Phase 3

**Context:** fault-tolerance.md defines 8 error types (E1-E8). E7 (rule drift) depends on guard hooks (Phase 8). E8 (stale knowledge) depends on knowledge system (Phase 4). Should Phase 3 implement full handlers or stubs?
**Decision:** E1-E6 fully implemented. E7 and E8 are stub handlers: log if detected, escalate to user. No automated detection logic.
**Alternatives rejected:**
- Full E1-E8 implementation — impossible without Phase 4/8 dependencies
- Omit E7/E8 entirely — errors.md would be incomplete, Phase 4/8 would need structural additions
**Reasoning:** Stubs establish the handler structure so future phases only need to fill in detection logic, not restructure the error handling system.

## D-039: Full Knowledge Dimensions in Access Matrix

**Context:** Phase 4 review revealed knowledge-access-matrix.yaml had only 4 dimensions (project_model, conventions, decisions, patterns) while knowledge.md defines 6 knowledge types (+ quality_map, failures). The plan hardcoded quality-map access for only 2 of 3 agents that need it, missing daedalus.
**Decision:** Expand knowledge-access-matrix.yaml to include all 6 dimensions. quality_map: metis=L1, daedalus=L2, themis=L1, mnemosyne/argus=L2, rest=null. Note: Daedalus quality_map access updated to L2 in agents.md design revision — planner needs full quality criteria to produce review-aware plans. failures: mnemosyne/argus=L2, rest=null (populated by Reflector in Phase 10). Remove hardcoded special-casing from plan — all access is matrix-driven.
**Alternatives rejected:**
- Keep 4 dimensions + hardcode quality-map — fragile, easy to miss agents, violates single source of truth
- Add failures access for more agents now — no content exists until Phase 10, premature
**Reasoning:** Single source of truth for agent knowledge access. Matrix-driven access is testable and prevents hardcoded exceptions that diverge from design docs over time.
**Verified 2026-03-15:** Daedalus quality_map = L2 confirmed across all 5 sources (this decision, agents.md, knowledge.md, knowledge-access-matrix.yaml, daedalus.yaml). No contradiction exists.

## D-040: Daedalus Writes Instruction Files (Not Orchestrator)

**Context:** Who should assemble the multi-layer instruction files for post-planning agents?
**Decision:** Daedalus (planner) writes complete instruction files to `state/tasks/{id}/instructions/{agent}.md`. The orchestrator reads these files at dispatch time instead of constructing prompts inline.
**Alternatives rejected:**
- Orchestrator assembles instructions at dispatch time — moves complexity into orchestrator, violates Art 1.1 (orchestrator purity)
- Separate "assembler" utility — adds a component when Daedalus already understands the plan context
**Reasoning:** The Planner is the only agent that understands the full task plan and can determine which knowledge and rules each downstream agent needs. Keeps orchestrator simple.

## D-041: Dual Prompt Construction Path

**Context:** How do pre-planning agents (Apollo, Hermes, Athena) get their prompts when no instruction files exist yet?
**Decision:** Two paths: pre-planning agents use simplified Phase 3 assembly; post-planning agents use pre-assembled instruction files from Daedalus. Quick pipeline uses simplified assembly throughout.
**Alternatives rejected:**
- Require Daedalus for all agents — creates circular dependency (classifier must run before planner)
- Single assembly path with optional knowledge — loses the structured instruction file benefits
**Reasoning:** Pre-planning agents run before Daedalus, so no instruction files can exist. The simplified path is the correct minimal-context path for agents that don't need full project knowledge.

## D-042: Structural Consistency Validation (Not Semantic)

**Context:** How should knowledge consistency be checked at write time?
**Decision:** Shell-based keyword heuristics that catch obvious contradictions (same key, different value). Not LLM reasoning.
**Alternatives rejected:**
- Skip consistency checks entirely — risks silent knowledge corruption
- Full semantic validation at write time — requires agent dispatch, too expensive for every write
**Reasoning:** Shell can't do semantic reasoning. Structural checks catch the most common contradictions cheaply. Full semantic consistency is the Reflector's job (Phase 10/11).

## D-043: Knowledge Templates as Installed Files

**Context:** How should knowledge structure templates be distributed?
**Decision:** Templates are part of the global installation (`~/.claude/moira/templates/knowledge/`) and copied to projects by `scaffold.sh`. Static files, not generated dynamically.
**Alternatives rejected:**
- Generate templates dynamically at init — adds runtime complexity, harder to test
- Inline templates in scaffold.sh — harder to maintain, not inspectable
**Reasoning:** Templates define structure, not content. File-based approach is testable, versionable, inspectable. Consistent with D-020 (file-copy distribution model).

## D-044: AGENTS.md Generation Deferred

**Context:** `distribution.md` Step 7 defines AGENTS.md generation with project-adapted agent definitions during `/moira:init`. Should Phase 5 implement this?
**Decision:** Defer AGENTS.md generation to Phase 6+ when quality gates exist to validate adapted agent definitions.
**Alternatives rejected:**
- Implement in Phase 5 with basic validation — adapted agents need quality gates to verify the adaptations don't weaken NEVER constraints
- Generate static AGENTS.md without adaptation — low value, global agent definitions from Phase 2 work correctly
**Reasoning:** (1) Adapted agents need quality gates (Phase 6) to validate that project-specific customization doesn't violate agent role boundaries (Art 1.2). (2) Global agent definitions work correctly without project adaptation. (3) The value of project-adapted AGENTS.md is marginal until the system has run enough tasks to understand what adaptations matter.

## D-045: Bootstrap Fields in Config Schema

**Context:** Phase 5 `/moira:init` needs to track bootstrap state (quick scan completed, deep scan pending) in config.yaml. These fields were referenced in the Phase 5 spec but not defined in config.schema.yaml.
**Decision:** Add `bootstrap.*` fields to config.schema.yaml: `quick_scan_completed` (bool), `quick_scan_at` (string/timestamp), `deep_scan_completed` (bool), `deep_scan_pending` (bool). All optional, default to false/"".
**Reasoning:** Per D-029 (full YAML schemas upfront), schema must be defined before implementation. Bootstrap state is project config (committed to git) because team members need to know whether deep scan has run.

## D-046: LLM-Judge Deferred to Phase 10

**Context:** Roadmap Phase 6 testing section mentions "LLM-judge with anchored rubrics (D-024)". However, `testing.md` roadmap integration explicitly assigns LLM-Judge implementation to Phase 10 alongside the Reflector. Which timing is correct?
**Decision:** Phase 6 creates rubric DEFINITION files (YAML with anchored examples) and bench infrastructure with automated checks only (compile, lint, test pass/fail). The actual LLM-Judge invocation (Claude call for qualitative evaluation) is deferred to Phase 10.
**Alternatives rejected:**
- Full LLM-Judge in Phase 6 — the judge evaluates the same dimensions as the Reflector (requirements coverage, code correctness, architecture quality, conventions adherence). Implementing them together ensures consistency.
- No bench infrastructure in Phase 6 — the fixtures and test case format are needed regardless of the judge. Automated checks provide immediate value.
**Reasoning:** testing.md's Phase 10 assignment is correct. The LLM-Judge and Reflector share evaluation patterns — implementing them in the same phase prevents divergence. Phase 6 bench results include structural/automated scores only; quality scores are `null` until the judge is operational.

## D-047: Quality Findings as Separate YAML Files

**Context:** Should quality findings (checklist results, severity classifications) be embedded in the main agent output files (review.md, requirements.md) or written to dedicated files?
**Decision:** Dedicated files: `state/tasks/{id}/findings/{agent}-{gate}.yaml`. Structured YAML format with machine-parseable verdict field.
**Alternatives rejected:**
- Inline in agent markdown output — requires parsing markdown for routing decisions, fragile
- Findings in status.yaml — bloats the per-task status file, mixes state with data
**Reasoning:** (1) Machine-parseable: YAML enables deterministic routing without markdown parsing. (2) Separation of concerns: detailed analysis in .md, routing data in .yaml. (3) Aggregation: quality.sh can scan the directory without understanding markdown structure. (4) Historical: findings persist for Reflector analysis in Phase 10.

## D-048: Bench Mode Gate Auto-Response

**Context:** Behavioral bench tests need to run Moira pipelines with predefined gate responses (from test case YAML). How should gates be handled during bench runs?
**Decision:** A `bench_mode` flag in `current.yaml`. When true, the orchestrator reads gate responses from the test case file instead of prompting the user. All gate decisions are still recorded in state files.
**Alternatives rejected:**
- Separate bench pipeline that skips gates — tests different behavior than production, defeats purpose
- External harness that intercepts and responds — duplicates orchestration logic, maintenance burden
**Reasoning:** Bench tests must exercise the ACTUAL pipeline to be meaningful. Auto-response reuses production code with a single flag check at each gate. Does not violate Art 4.2 because the user explicitly chose to run the bench test. Full traceability maintained (Art 3.1).

## D-049: QUALITY Line in Agent Response Contract

**Context:** How should the orchestrator determine quality gate verdict without reading the full findings file?
**Decision:** Add a `QUALITY` summary line to the agent response contract: `QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)`. The orchestrator reads the full findings file ONLY when presenting WARNING details to the user.
**Alternatives rejected:**
- Always read full findings file — wastes orchestrator context on every quality gate
- Parse findings inline from agent return text — fragile markdown parsing
**Reasoning:** Per D-001 (minimal orchestrator context), the QUALITY line provides routing signal in a single line. Full findings are file-based (D-002). The orchestrator reads findings only for WARNING gate presentation, not for pass/fail_critical routing.

## D-050: Deep Scan as Phase 6 Deliverable

**Context:** Phase 5 placed the deep scan trigger in the orchestrator but deferred agent instructions. When should deep scan templates be implemented?
**Decision:** Phase 6 implements deep scan agent instructions. Deep scan output is validated through the quality map system — scan results feed into the quality map with `medium` confidence, requiring 3+ task observations to reach `high` confidence (Art 5.2).
**Alternatives rejected:**
- Phase 5 — quality gates needed to validate deep scan output quality
- Phase 10 — too late, deep scan data feeds quality map which is needed earlier
**Reasoning:** Phase 6 provides quality gates. Deep scan results are structural knowledge (file lists, dependency graphs) validated by the quality map confidence system, not by LLM judgment. Phase 5 left the stub; Phase 6 completes it.

## D-051: Quality Map Evolution is Structural, Not Semantic

**Context:** How should quality map entries be updated based on Reviewer findings?
**Decision:** `moira_knowledge_update_quality_map` uses keyword matching and observation counting (shell-based), not LLM reasoning. Consistent with D-042 (structural consistency validation).
**Alternatives rejected:**
- LLM-based semantic analysis at write time — too expensive for every task completion
- No automated updates — quality map stagnates
**Reasoning:** Shell can catch keyword-level matches (same pattern name + location). Counting observations is trivial. Full semantic analysis of pattern quality is the Reflector's job (Phase 10). This keeps the write path cheap and deterministic.

## D-052: Fixture Projects are Minimal

**Context:** How large should bench fixture projects be?
**Decision:** Fixtures are intentionally small (3-25 files). They test Moira's pipeline behavior, not its ability to handle large codebases.
**Alternatives rejected:**
- Large realistic fixtures (100+ files) — slow to scan, expensive to reset, test the wrong thing
- Single fixture with flags — loses the greenfield/mature/legacy behavioral distinctions
**Reasoning:** Pipeline behavior (gate routing, quality checks, agent sequencing) doesn't depend on codebase size. Large codebase handling is tested via live telemetry on real projects (Phase 3). Minimal fixtures keep bench runs fast and token-efficient.

## D-053: WARNING Gate is a Conditional Gate Type

**Context:** Should quality warnings use an existing gate type or a new one?
**Decision:** WARNING gate is a new conditional gate type, distinct from required approval gates. It has different options (proceed/fix/details/abort) and is ONLY presented when warning findings exist.
**Alternatives rejected:**
- Reuse existing approval gate — different semantics (approval vs quality triage)
- Auto-proceed on warnings — violates Art 4.2 (user authority over quality decisions)
**Reasoning:** Required gates (classification, architecture, plan, final) are defined in pipeline YAML per Art 2.2. The WARNING gate is a conditional error-handling path, similar to E5-QUALITY retry. It doesn't violate Art 2.2 because it's not a pipeline-defined gate — it's a quality routing mechanism that only activates when warnings are present.

## D-054: Config Quality Fields Reconciled for Phase 6

**Context:** Phase 1 (D-029) created `quality.evolution_threshold` and `quality.review_severity_minimum` in config.schema.yaml based on early quality.md design. Phase 6 spec requires `quality.evolution.current_target` and `quality.evolution.cooldown_remaining` for EVOLVE mode lifecycle tracking.
**Decision:** Remove `quality.evolution_threshold` (superseded by hardcoded 3-observation rule per Art 5.2) and `quality.review_severity_minimum` (superseded by fixed severity routing: critical→retry, warning→gate, suggestion→log). Replace with `quality.evolution.current_target` (string) and `quality.evolution.cooldown_remaining` (number).
**Alternatives rejected:**
- Keep all fields — `evolution_threshold` conflicts structurally with `evolution.current_target` nesting, and configurable severity minimum contradicts the deterministic routing model (Art 2.1)
- Make evolution threshold configurable — Art 5.2 mandates 3+ observations, not user-configurable
**Reasoning:** The 3-observation threshold is a constitutional requirement (Art 5.2), not a tunable parameter. Severity routing is deterministic by design (Art 2.1). Configurable fields that contradict invariants create confusion about what the system actually does.

## D-055: Separate Budget Library

**Context:** Should budget functions live in state.sh or a dedicated module?
**Decision:** Dedicated `budget.sh` library, separate from `state.sh`. State handles transitions, budget handles estimation/tracking/reporting.
**Alternatives rejected:**
- Inline in state.sh — adds 9+ functions, violates Art 1.3 (no god components)
- Distributed across multiple modules — budget logic is cohesive, splitting it loses clarity
**Reasoning:** Single responsibility. Budget estimation is independently testable. state.sh remains focused on state transitions.

## D-056: Approximate Token Estimation

**Context:** How to estimate token counts without tokenizer access?
**Decision:** Use `file_size_bytes / 4` as token estimation ratio (industry-standard approximation for English/code).
**Alternatives rejected:**
- Exact tokenizer — not available in shell environment
- Character count only — tokens ≠ characters, ratio provides better approximation
- No estimation — budget system needs numbers to make split/no-split decisions
**Reasoning:** Sufficient for threshold decisions (below 50%, near 70%, above 70%). The 30% safety margin absorbs estimation errors. Precision is not needed — only directional correctness.

## D-057: Budget Config as Separate File

**Context:** Should budget allocations live in config.yaml or a dedicated file?
**Decision:** Separate `config/budgets.yaml` for per-project tuning. `config.schema.yaml` fields serve as fallback defaults.
**Alternatives rejected:**
- Inline in config.yaml — mixes general config with specialized tuning
- No project-level overrides — teams can't tune budgets for their codebase complexity
**Reasoning:** Budget allocations are the most likely config to need per-project tuning. Separation allows updating budgets without touching main config. Three-level lookup: budgets.yaml → config.yaml → schema defaults.

## D-058: Proxy-Based Orchestrator Context Estimation

**Context:** How to measure orchestrator token usage at runtime?
**Decision:** Proxy approach: base overhead (15k) + per-step processing (500/step) + gate interactions (2k/gate) + agent return summaries.
**Alternatives rejected:**
- Direct measurement — not feasible in Claude Code runtime
- No measurement — loses orchestrator health visibility
- Token counting hooks — hooks execute in separate processes, can't measure orchestrator context
**Reasoning:** Rough but sufficient for threshold-based decisions. The 25%/40%/60% thresholds have wide gaps specifically because estimation is approximate. Proxy is cheap to compute.

## D-059: Config-Driven MCP Token Estimates

**Context:** How to estimate MCP call token impact for budget calculations?
**Decision:** Static estimates from `budgets.yaml` (`mcp_estimates` section). Planner uses these estimates before calls happen.
**Alternatives rejected:**
- Runtime measurement — MCP call sizes only known after the call
- No MCP budgeting — MCP calls can be large (14k+ for context7), ignoring them risks budget overflow
- Hardcoded estimates — not tunable per project
**Reasoning:** MCP call sizes vary by query but have predictable ranges. Config-driven allows projects to tune based on actual usage patterns. Default values are conservative (14k for context7, 5k for unknown).

## D-060: Remove Stack Presets, Frontmatter Scanner Output, Directory Conventions in Structure Scanner

**Context:** Stack presets actively harm unknown stacks (SvelteKit matched react-vite preset, injecting React defaults). Bash grep/sed parsing of free-form markdown is fragile (backtick-wrapped values, "Not detected" strings, missing headers). See `design/reports/2026-03-13-init-bootstrap-bugs.md`.
**Decision:** Remove all stack presets. Scanners write YAML frontmatter (machine-readable) + markdown body (human-readable). Structure scanner detects `dir_*` file placement patterns for `conventions.yaml` `structure:` section. `project.stack` becomes free-form string.
**Alternatives rejected:**
- Add more presets — doesn't scale to every possible stack
- Keep presets + fix parsing — two-system complexity remains
- Dedicated architecture scanner for `dir_*` — future enhancement, not needed now (structure scanner already maps directory roles)
**Reasoning:** Frontmatter is trivially parseable in bash (read between `---` delimiters). No preset layer means no wrong defaults. Structure scanner already maps directories — `dir_*` detection is natural extension. Architecture scanner may take over `dir_*` responsibility in future.

## D-061: Two-Level Path Resolution (Global vs Project)

**Context:** First task execution on sveltkit-todos revealed that all pipeline skills (`task.md`, `orchestrator.md`, `dispatch.md`, `errors.md`, `bypass.md`) hardcoded `~/.claude/moira/state/` for state writes. This caused state to be written to the global directory instead of the project-local `.claude/moira/state/`, making init scans invisible to the orchestrator and breaking deep scan triggers. See `design/reports/2026-03-13-first-task-execution-sveltkit-todos.md`.
**Decision:** Two base paths, no resolution logic needed:
- **Global (read-only):** `~/.claude/moira/` — core rules, pipelines, templates, skills, lib
- **Project (read-write):** `.claude/moira/` — state, config, knowledge
All skills use `.claude/moira/` for state/config/knowledge and `~/.claude/moira/` for core definitions. Path Resolution section added to `orchestrator.md` Section 1.
**Alternatives rejected:**
- Runtime resolution (check project first, fallback to global) — unnecessary complexity, project dir always exists after init
- Single unified path — defeats purpose of global install (core shared across projects)
- Environment variable (`MOIRA_BASE`) — no mechanism to set env vars in skill context
**Reasoning:** `init.md` already used this pattern correctly (global for templates/core, project-local for output). The bug was inconsistency — other skills hadn't adopted the same convention. Simple path replacement in skills, no runtime logic needed.

## D-062: Classifier Does Not Return Pipeline Type

**Context:** First full task execution revealed Apollo returned `pipeline=single-agent` — a value not in the system. Orchestrator correctly used the mapping table as fallback, but the response contract allowed the invalid value.
**Decision:** Remove `pipeline=` from Classifier's response format. Classifier returns only `size=` and `confidence=`. Pipeline selection is exclusively the orchestrator's responsibility (Art 2.1 pure function).
**Alternatives rejected:**
- Add enum validation for pipeline value — pipeline selection is not the classifier's job; validating a field that shouldn't exist is wrong fix
- Keep pipeline as informational hint — creates ambiguity about who owns pipeline selection; no additional information vs the deterministic table
**Reasoning:** Art 2.1 defines pipeline selection as a pure function of size+confidence. Having the classifier also propose a pipeline violates single responsibility and creates a potential for contradictions. The mapping table in orchestrator.md Section 3 is the single source of truth.

## D-063: Implementer Post-Implementation Validation

**Context:** First task execution required orchestrator to run `svelte-kit sync` directly — violating Art 1.1 (orchestrator never runs bash). Root cause: SvelteKit needs type generation after code changes, and no pipeline step handled this.
**Decision:** Implementer runs post-implementation validation commands from `config.yaml` → `tooling.post_implementation[]` before returning STATUS: success. If commands fail, implementer fixes errors. If none configured, step is skipped.
**Alternatives rejected:**
- Separate pipeline step for validation — adds overhead (new agent dispatch) for every task, even when no validation needed
- Reviewer runs validation — wastes review dispatch if typecheck fails; better to catch earlier
- Orchestrator runs tooling commands — violates Art 1.1 (orchestrator never runs bash commands)
**Reasoning:** "Code compiles" is part of "code is written correctly." Running typecheck/lint is a natural extension of the implementer's responsibility, not a new responsibility. Config-driven approach makes it project-specific (SvelteKit projects add `svelte-kit sync`, Go projects add `go vet`, etc.). No NEVER constraints are weakened — implementer still never makes decisions about WHAT to build.

## D-064: Orchestrator Context Capacity 1M Tokens

**Context:** Models with 1M+ context window increased default context from 200k to 1M tokens. Orchestrator context budget thresholds were calibrated for 200k.
**Decision:** Update orchestrator context capacity to 1M. Keep percentage-based thresholds unchanged (<25% healthy, 25-40% monitor, 40-60% warning, >60% critical). Agent budgets remain at pre-1M allocations — they define maximum useful work per agent, not context limits.
**Alternatives rejected:**
- Increase agent budgets proportionally — agents don't need more context, their budgets reflect useful work scope
- Reduce orchestrator skill size for optimization — premature, 1M provides ample headroom; reducing skill size risks losing quality through less self-contained instructions
**Reasoning:** Percentage thresholds scale automatically. Agent budgets are task-scoped, not context-scoped — an explorer doesn't need 700k tokens for a small codebase just because it's available. The 1M headroom means orchestrator can handle Full pipeline with multiple retries without hitting warning thresholds.

## D-065: Enforcement Model — Three-Tier Trust Classification

**Context:** Architecture review (2026-03-13) identified that the design treats structural guarantees (allowed-tools) and behavioral rules (agent NEVER constraints) as equivalently reliable. They are not.
**Decision:** Add an Enforcement Model section to fault-tolerance.md classifying every constraint into three tiers: structural (platform-guaranteed), validated (behavioral + verification), behavioral (prompt-only). Reviewer and Reflector are reframed as primary behavioral defense, not secondary checks.
**Alternatives rejected:**
- Full subsystem document (enforcement-model.md) — over-engineering for pre-v1, medium variant provides 80% value
- Localized fix only (E6 parsing fallback) — doesn't address the systemic blind spot
**Reasoning:** The design must be honest about what is structurally enforced vs what depends on prompting. This informs where to invest in detection and defense layers.

## D-066: Monorepo Support — Bootstrap Detection + Package Map + Classifier Scoping

**Context:** Explorer has 140k budget. Monorepo with many packages won't fit breadth-first scan. Need a scoping strategy.
**Decision:** Bootstrap (init) detects monorepo (workspaces, lerna.json, packages/). Creates package map in knowledge (extension of project-model). Classifier uses package map to scope relevant packages per task. Explorer receives scoped instructions.
**Alternatives rejected:**
- Two-pass Explorer (scan structure first, then deep scan) — double dispatch overhead, Explorer making relevance judgments violates "reports facts only"
- No scoping, just increase budget — doesn't scale
**Reasoning:** Uses existing mechanisms (knowledge system, Classifier scope, E2-SCOPE recovery). No new agents or pipeline changes needed.

## D-067: Art 4.2 Amendment — Bench Mode Exception

**Context:** bench_mode (D-048) auto-responds to gates during testing. Art 4.2 says "no auto-proceed logic exists." This is a constitutional contradiction.
**Decision:** Amend Art 4.2 test clause to explicitly exempt bench mode (explicitly user-activated via /moira bench). Production pipeline gates remain fully user-controlled.
**Alternatives rejected:**
- Remove bench_mode from production schema — bench_mode was implemented intentionally and works correctly
- Leave as-is with D-048 reasoning — constitutional interpretation is not sufficient, explicit amendment needed
**Reasoning:** The constitution should be honest about what the system actually does. Bench mode is a deliberate, user-activated testing mechanism, not an erosion of user authority.

## D-068: Multi-Developer Locks Deferred to Post-v1

**Context:** Architecture review flagged the lock system (locks.yaml with TTL and stale detection) as over-engineering for pre-v1. Git branch isolation is sufficient for initial multi-developer use.
**Decision:** Defer lock system implementation. Phase 12 retains the design but marks it as post-v1. Branch-based isolation is the interim solution.
**Alternatives rejected:**
- Remove lock system from design entirely — the design is sound for future use
- Implement as planned — no evidence of need until multiple users exist
**Reasoning:** Implementation cost is high, value is advisory only (cannot prevent actual git conflicts). Branch isolation is free and sufficient for initial use.

## D-069: Tweak/Redo Stays in Phase 12

**Context:** Architecture review recommended moving basic Tweak to Phase 6-7 for usability. However, users won't interact with Moira until after Phase 12 — only the developer uses it for testing.
**Decision:** Keep Tweak/Redo in Phase 12 as originally planned.
**Alternatives rejected:**
- Move basic Tweak to Phase 6-7 — premature, no user demand yet
**Reasoning:** The recommendation assumed users are already working with the system. They aren't. Implementing Tweak early would be building for a scenario that doesn't exist yet.

## D-070: E2-SCOPE Extended with Monorepo Subtype

**Context:** E2-SCOPE is defined as "task is bigger/more complex than classified." Monorepo support needs a mechanism for when Explorer discovers that the scoped packages are insufficient. This is conceptually different from task size reclassification.
**Decision:** Add monorepo subtype to E2-SCOPE: "insufficient package scope." Same recovery flow (stop, present options, user decides) but options are scope-focused (add packages) rather than size-focused (upgrade pipeline).
**Alternatives rejected:**
- Reuse E2-SCOPE without subtype — semantic stretch, confusing
- New error code E12 — insufficient justification for a separate code when the recovery flow is identical
**Reasoning:** Same error family (scope), same recovery pattern, different trigger. Subtype preserves taxonomy coherence.

## D-071: Quick Pipeline Retry Limit Is 1

**Context:** Quick Pipeline (pipelines.md) says "max 1" retry. Fault-tolerance.md E5-QUALITY says "MAX RETRY: 2 attempts total." This is a contradiction.
**Decision:** Quick Pipeline keeps max 1. Fault-tolerance.md adds note that pipeline-specific limits may override the general default. The general default of 2 applies to Standard and Full pipelines.
**Alternatives rejected:**
- Change Quick to max 2 — Quick Pipeline is designed for speed, extra retry defeats the purpose
- Change general default to 1 — Standard/Full benefit from the second attempt
**Reasoning:** Quick Pipeline optimizes for speed. If the first retry fails, escalating to user is more efficient than a second retry for what should be a small task.

## D-072: Hooks as Lightweight Scripts (No Library Dependencies)

**Context:** Phase 8 hook scripts (guard.sh, budget-track.sh) fire on every PostToolUse event. Should they source Moira libraries for shared functionality?
**Decision:** Hook scripts do NOT source any Moira library files. They use only basic bash, grep, sed, and optionally jq. Guard.sh checks only Read/Write/Edit (not Grep/Glob as in self-monitoring.md example) because allowed-tools physically prevents the orchestrator from using Grep/Glob.
**Alternatives rejected:**
- Source yaml-utils.sh + state.sh for consistent state access — adds ~100ms+ startup time per tool call
- Source only a lightweight "hooks-common.sh" — still adds fork overhead, not justified for simple log appends
**Reasoning:** PostToolUse hooks fire after EVERY tool call — performance is critical (< 50ms). Hooks are separate processes that cannot share state with the orchestrator. Simple log file appends are sufficient. Complex analysis happens post-task.

## D-073: JSON Settings Merge with jq Fallback

**Context:** Phase 8 needs to inject hook configuration into .claude/settings.json. This requires JSON editing in bash.
**Decision:** Use jq when available, with a grep-based fallback for simple cases. For complex settings.json without jq: warn user and provide manual instructions.
**Alternatives rejected:**
- Require jq as dependency — violates D-020 (minimal dependencies)
- Python/Node fallback — introduces heavy dependencies for a one-time operation
- Always manual — poor UX for the common case
**Reasoning:** jq is widely available but not universal. The fallback handles ~90% of cases. This matches D-020 philosophy: works on any OS with Claude Code.

## D-074: Violation Log in State Directory (Gitignored)

**Context:** Where should guard.sh violation and tool-usage logs be stored?
**Decision:** Logs go in state/ (gitignored), not config/ (committed). violations.log, tool-usage.log, and budget-tool-usage.log are all per-developer ephemeral data.
**Alternatives rejected:**
- Store in config/ (committed) — creates noise in PRs, exposes per-developer tool usage
- Store in knowledge/ — violates knowledge integrity (Art 5.1, knowledge must be evidence-based)
**Reasoning:** Violations are per-developer, per-session. Raw logs are ephemeral; aggregated insights (from Reflector Phase 10, Audit Phase 11) are permanent and committed.

## D-075: Guard Hook Cannot Block (PostToolUse Limitation)

**Context:** Guard.sh fires after the tool call (PostToolUse), not before. Can it prevent violations?
**Decision:** Guard.sh can only detect and report, not prevent. Prevention is handled by allowed-tools (Layer 1). Guard.sh provides audit trail (Art 6.3) and injects warnings via hookSpecificOutput.
**Alternatives rejected:**
- Use PreToolUse hooks — Claude Code does not support them (confirmed in D-031)
- Reject tool output via hook — not supported by Claude Code hook API
**Reasoning:** Defense-in-depth: allowed-tools prevents, guard.sh detects, CLAUDE.md reinforces. The warning injected via hookSpecificOutput influences subsequent orchestrator behavior.

## D-076: Empty Log File Initialization in Bootstrap

**Context:** Guard.sh appends to log files. Should files be created lazily on first write or pre-created?
**Decision:** Log files are created empty during bootstrap (via moira_bootstrap_inject_hooks), not lazily. Scaffold creates directories only; bootstrap creates initial files — maintaining existing responsibility split.
**Alternatives rejected:**
- Lazy creation in guard.sh via >> — works but race condition risk if multiple hooks fire simultaneously
- Create in scaffold.sh — violates scaffold's documented contract (directories ONLY)
**Reasoning:** Pre-creating avoids race conditions. wc -l on empty file returns 0 (correct baseline). If log dir doesn't exist, guard.sh can use that as "not a Moira project" signal.

## D-077: Cross-Reference Manifest for Consistency Enforcement

**Context:** System audit (2026-03-14) found 58 inconsistencies, ~60% caused by the same value being defined in multiple files (budgets, knowledge access levels, enum values, file paths) without a mechanism to propagate changes. When an agent updates one file, dependent files silently drift.
**Decision:** Introduce a machine-readable cross-reference manifest (`src/global/core/xref-manifest.yaml`) that maps data dependencies between files. Agents consult the manifest before committing to identify all files affected by their changes. Tier 1 tests validate manifest entries against actual file content.
**Alternatives rejected:**
- Expand Tier 1 tests only (option A) — catches drift after the fact, doesn't prevent it
- Reduce duplication to single source of truth (option C) — ideal long-term but requires major design doc refactoring; can be done incrementally alongside the manifest
- No action — 58-finding audits will recur after every phase
**Reasoning:** The manifest is a pragmatic middle ground: it doesn't require restructuring existing documents but gives agents an explicit dependency map to follow. Combined with Tier 1 validation, it catches both forgotten updates (test) and prevents them (manifest lookup at commit time). Option C (deduplication) remains a complementary long-term goal.

## D-078: MCP Authorization via Prompting (Not Enforcement)

**Context:** MCP tools are available to all agents in the Claude Code environment. Moira needs a mechanism to control which agents use which MCP tools and when.
**Decision:** MCP tool authorization is enforced via agent instructions (prompting), not via `allowed-tools` or hooks. Agents receive explicit lists of authorized and prohibited MCP tools per step.
**Alternatives rejected:**
- Use `allowed-tools` to restrict MCP per step — Claude Code's `allowed-tools` is session-wide, cannot selectively allow MCP tools per step
- Use hooks to block unauthorized MCP calls — Claude Code hook API cannot reject tool output or block calls
**Reasoning:** Prompting-based authorization matches how we handle other agent constraints (NEVER rules). Reviewer (Themis) provides behavioral verification that MCP rules were followed. Consistent with D-031's defense-in-depth: prompting is Layer 3, behavioral review is additional validation.

## D-079: MCP Scanner as Hermes (Explorer) Dispatch

**Context:** MCP discovery needs to catalog available MCP servers and their tools during `/moira init`. Need to decide how this scanning is implemented.
**Decision:** MCP discovery uses the same Explorer agent pattern as other bootstrap scanners (tech, structure, convention, pattern). The scanner is a Layer 4 instruction template dispatched via Agent tool.
**Alternatives rejected:**
- New dedicated MCP agent type — violates Art 1.3 (no god components), unnecessary when Explorer already reads system state
- Shell-based discovery without agent — MCP tool classification requires LLM judgment (purpose, cost, reliability)
**Reasoning:** Consistent with existing scanner architecture (D-032). Explorer is the only agent that reads system state — MCP configuration is system state. Layer 4 instructions customize the Explorer for the specific scan type.

## D-080: Registry in Config (Committed), Not State (Gitignored)

**Context:** MCP registry needs a home in the project layer. Could live in `config/` (committed) or `state/` (gitignored).
**Decision:** MCP registry lives in `.claude/moira/config/mcp-registry.yaml` (committed) — same as `budgets.yaml` and `locks.yaml`.
**Alternatives rejected:**
- Store in `state/` (gitignored) — team members wouldn't share MCP classifications, user customizations lost on re-init
- Store outside `.claude/moira/` — breaks project layer containment
**Reasoning:** Registry is project configuration, not ephemeral state. Team members share the same MCP tool classifications. User customizations (editing when_to_use, adjusting token_estimates) persist across sessions. Already defined this way in `overview.md` file structure and `config.schema.yaml`.

## D-081: MCP Caching Structure Now, Logic Later

**Context:** MCP documentation caching can save significant tokens by avoiding repeated identical MCP calls. Need to decide how much caching infrastructure to build in Phase 9.
**Decision:** Phase 9 creates `knowledge/libraries/` directory and templates. Phase 10 (Reflector) implements the actual caching logic (repeated call detection, cache proposal, freshness management).
**Alternatives rejected:**
- Build full caching in Phase 9 — Reflector doesn't exist until Phase 10; caching logic belongs to the agent that tracks patterns
- Defer all caching to Phase 10 — would require Phase 10 to create directories and templates, mixing infrastructure with intelligence
**Reasoning:** Clean separation: Phase 9 = infrastructure, Phase 10 = intelligence. Creating structure now means Phase 10 has somewhere to write.

## D-082: Registry `tools` as Map (Not List-of-Maps)

**Context:** The design doc (`mcp.md`) shows registry tools as a YAML list-of-maps. Need to decide the canonical format.
**Decision:** Use a YAML map instead (tool name as key, metadata as value) for natural key-based lookups. Design doc (`mcp.md`) updated to match.
**Alternatives rejected:**
- Keep list-of-maps format from original design doc — requires iterating to find a tool by name, more complex shell parsing
**Reasoning:** Map format enables direct key lookup: `servers.context7.tools.query-docs`. Tool names are unique within a server — natural keys. Consistent with how `config.yaml` and `budgets.yaml` use map structures. Simpler parsing in shell scripts (grep for `tool_name:` indent level).

## D-083: `token_estimate` Numeric Field in Registry

**Context:** Budget system needs machine-readable token estimates for MCP calls. Design doc has `budget_impact` as a descriptive string.
**Decision:** Add a `token_estimate` (number) field per tool, extending the design doc's `budget_impact` (string) field. Both fields coexist: `budget_impact` for human display, `token_estimate` for budget calculations.
**Alternatives rejected:**
- Parse `budget_impact` string for numbers — fragile, format varies ("~5-20k", "high")
- Replace `budget_impact` with numeric only — loses human-readable context
**Reasoning:** D-059 specifies config-driven MCP token estimates — numeric field bridges registry with budget system. Fallback chain: registry `token_estimate` → `budgets.yaml` `mcp_estimates` → default 5000.

## D-084: Registry Merge Strategy on Refresh

**Context:** When `/moira:refresh` re-scans MCP servers, need to decide how new results merge with existing registry.
**Decision:** Merge strategy: add new servers, flag removed servers (set `removed: true`), preserve user customizations to existing tool entries.
**Alternatives rejected:**
- Overwrite entirely — loses user tuning of when_to_use, token_estimates, etc.
- Silently remove absent servers — user may have intentionally configured servers not currently running
- Append only (never remove) — stale entries accumulate forever
**Reasoning:** Users may edit `when_to_use`, `token_estimate`, etc. — overwriting loses their tuning. Flagging (not deleting) removed servers lets users decide. New servers always added — no reason to exclude available tools. Consistent with how `/moira:refresh` handles knowledge updates (additive, not destructive).

## D-085: Architecture Gate in Decomposition Pipeline

**Context:** System audit (2026-03-15) found that the decomposition pipeline dispatches Metis (architect) but has no approval gate after the architecture step. Standard and Full pipelines both have architecture gates. Epic tasks are the most expensive — an architectural error before decomposition wastes the entire Planner pass and cascades into all sub-tasks.
**Decision:** Add `architecture_gate` to the decomposition pipeline between the `architecture` and `decomposition` steps. This makes the decomposition pipeline gates: classification + architecture + decomposition + per-task + final. The architecture and decomposition results are shown in two separate gates (not merged) so the user can reject architecture before the Planner runs.
**Alternatives rejected:**
- No gate, document as intentional — user sees architecture only at decomposition_gate, mixed with plan output. Can't reject architecture without also discarding decomposition. Planner tokens wasted on bad architecture.
- Merged gate (show architecture + plan together) — same problem: can't reject architecture independently. User forced to parse two artifacts at once.
- Soft/optional gate — prohibited by Art 2.2 ("Gates MUST NOT be made optional")
**Reasoning:** Epic tasks are high-stakes. Architecture gate is cheap (one user confirmation), but catching a bad architecture before Planner runs saves significant token budget and prevents cascading errors through all sub-tasks. Consistent with standard/full pipelines. Requires Constitutional amendment to Art 2.2.

## D-086: Observations in Task State Files (Not Separate Database)

**Context:** Where should post-task reflection observations be stored?
**Decision:** Observations stored within each task's `reflection.md` file, tagged with pattern keys. Cross-task counting uses file scanning, not a separate database.
**Alternatives rejected:**
- Separate observation database — new state file format to maintain, breaks file-based communication principle
**Reasoning:** Leverages existing task state lifecycle. Pattern key registry provides index for efficient counting. Consistent with D-002.

## D-087: Judge as Agent Tool Call (Not Direct API)

**Context:** How should the LLM-judge be invoked?
**Decision:** LLM-judge invoked via Claude Code's Agent tool, not via direct API call.
**Alternatives rejected:**
- Direct API call — Moira has no direct API access, runs within Claude Code
**Reasoning:** Agent tool is the only mechanism for spawning separate Claude contexts. Judge independence (D-024) achieved by model tier selection. Consistent with agent-based architecture.

## D-088: Three Rubric Variants by Task Category

**Context:** Should there be one universal rubric or multiple variants?
**Decision:** Three rubric variants (feature/bugfix/refactor) with adjusted weights per task category.
**Alternatives rejected:**
- Single universal rubric — can't capture that a bugfix shouldn't restructure architecture or that a refactor shouldn't add features
**Reasoning:** Weight adjustment captures distinctions without changing criteria. Test case `meta.category` determines rubric — deterministic selection.

## D-089: Pattern Key Registry for Efficient Cross-Task Counting

**Context:** How to efficiently count observation patterns across tasks?
**Decision:** Maintain a lightweight `pattern-keys.yaml` registry that tracks observation counts, updated incrementally by Mnemosyne.
**Alternatives rejected:**
- Scan all task reflection files on every reflection — O(n) per reflection vs O(1) lookup
**Reasoning:** O(1) lookup for threshold checks. Full scan available for verification but not needed routinely. Registry is gitignored, rebuilt from task files if lost.

## D-090: `/moira health` as Separate Command (Not Bench Subcommand)

**Context:** Should health check be part of `/moira bench` or a standalone command?
**Decision:** `/moira health` is a standalone command, not a `bench` subcommand.
**Alternatives rejected:**
- `bench health` subcommand — health uses live telemetry, not bench fixtures; different audience (project devs vs Moira devs)
**Reasoning:** Different data sources (live telemetry vs bench fixtures). Different audience. Consistent with testing.md design.

## D-091: Libraries Knowledge Access Matrix

**Context:** Which agents should access the `libraries` knowledge type?
**Decision:** Mnemosyne=L2 (read+write), Hephaestus=L1, Daedalus=L0, Argus=L2 (read-only), all others=null.
**Alternatives rejected:**
- Universal access — most agents don't interact with external library docs
**Reasoning:** Mnemosyne manages cache. Hephaestus benefits from cached API reference. Daedalus needs to know what's cached for budget estimation. Explorer gets null because libraries are external, not project code.

## D-092: Periodic Deep Reflection Every 5 Tasks

**Context:** How to implement "Pattern analysis (per 5 tasks)" from roadmap?
**Decision:** Counter-based escalation: every 5th standard-pipeline task auto-escalates from `background` to `deep` template.
**Alternatives rejected:**
- Time-based triggers — inconsistent cadence depending on task frequency
**Reasoning:** Matches roadmap requirement. Counter in `state/reflection/deep-reflection-counter.yaml`. Only escalates background→deep (lightweight stays lightweight, epic stays epic). Acceptable cadence for richer analysis.

## D-093: Phase 11 Architectural Choices

**Context:** Phase 11 spec introduces several implementation decisions not covered by existing design docs.
**Decisions:**
- (a) Trend threshold for metric direction (↑/↓/→) is implementation-defined — `metrics.md` defines indicators but not the numeric threshold. Implementation will determine a reasonable default (e.g., 5% change).
- (b) Automatic audit triggers use flag-based deferred execution: `moira_metrics_collect_task` writes `audit_pending` flag at pipeline completion; orchestrator checks the flag at the START of the next pipeline and offers to run the audit. This avoids bloating the completing pipeline's context.
- (c) Only `rules-light` and `knowledge-light` audit templates exist. Light audits for agents, config, and consistency are omitted because surface checks for those domains require reading multiple cross-referenced files — not meaningfully lighter than standard.
- (d) Audit finding IDs use domain prefix + sequence number (R-01, K-03, A-02, C-01, X-05). Domain prefixes: R=rules, K=knowledge, A=agents, C=config, X=consistency.
- (e) Audit schema includes `_meta` block (`date`, `depth`, `domains`, `moira_version`) and `summary` block (`total`, `by_risk`, `by_domain`). Not specified in `audit.md` but consistent with its output examples.
- (f) Per-task records in monthly metrics include: `task_id`, `pipeline`, `size`, `first_pass`, `tweaked`, `redone`, `retries`, `orchestrator_pct`, `reviewer_criticals`, `by_agent`. The `metrics.md` design doc says "Per-task data also stored for drill-down" without specifying fields.
- (g) Agent pre-commit xref check deferred from mechanical enforcement to CLAUDE.md convention for Phase 11. Mechanical enforcement targeted for Phase 12 when the orchestrator skill gets checkpoint/resume updates and can incorporate xref verification.
**Alternatives rejected:**
- For (b): triggering audit inline at pipeline completion — would bloat orchestrator context during completion flow and provide no natural decision point for the user
- For (c): creating stub light templates for all 5 domains — adds files with no meaningful differentiation from standard templates
- For (g): implementing mechanical enforcement in Phase 11 — requires orchestrator skill changes that are better batched with Phase 12's orchestrator updates
**Reasoning:** Each choice balances architectural correctness with practical implementation scope. Flag-based deferred triggers follow the same pattern as deep scan checks. Light template reduction avoids maintaining templates that would be identical to standard versions.

## D-094: Formal Methods & Optimization Architectural Choices

**Context:** Cross-cutting enhancement integrating mathematical techniques into existing subsystems for improved efficiency and reliability.
**Decisions:**
- (a) Pipeline graph verification uses path enumeration (tractable for small graphs <20 nodes). Decomposition pipeline per-task gates treated as loop with verified loop-body gate.
- (b) CPM replaces 3-phase heuristic but preserves shared-file-last constraint. LPT splitting guarantees makespan ≤ (4/3) × optimal.
- (c) Adaptive margin formula uses μ + 2σ with 20% floor and 50% ceiling. Requires updating context-budget.md "UNTOUCHABLE" 30% hard rule to adaptive model (ORANGE change). Cold start: <5 obs → 30% default, 5-20 → μ + 3σ, 20+ → μ + 2σ.
- (d) SPRT uses α=0.05, β=0.10 as defaults, assumes normal distribution. User can always "run all tests anyway" override.
- (e) CUSUM coexists with zone system — adds DRIFT signal, does not replace WARN/ALERT. Accumulators self-reset after alarm.
- (f) BH chosen over Bonferroni for better power with controlled FDR (≤5% vs ~18.5% uncorrected with 4 metrics).
- (g) Exponential decay rates per knowledge type are initial estimates, tunable. Uses repeated multiplication (not Taylor series) for integer arithmetic stability. Requires updating knowledge.md freshness model (ORANGE change).
- (h) Markov retry model can recommend fewer retries than existing hard limits but never more. p2 only defined for error types permitting second retry. Uses EMA smoothing (α=0.8) for probability updates.
- (i) Deferred Tier C techniques (Bayesian rule induction, IRT, information-theoretic value, ADWIN, Thompson Sampling) documented in spec for post-v1.
**Alternatives rejected:**
- For (c): keeping fixed 30% — wastes 10-15% usable context for stable agents
- For (f): Bonferroni correction — too conservative with 4 metrics (each test needs p<0.0125)
- For (g): Taylor series for exp decay — integer overflow for large exponents
**Reasoning:** Each technique targets measurable improvements to efficiency (less waste, faster pipelines) and reliability (fewer false alarms, better regression detection, provable invariants). All changes are backward compatible with existing behavior during cold start.

## D-095: max_attempts Semantics Definition

**Date:** 2026-03-16
**Status:** Accepted
**Context:** Audit C-01 found that `max_attempts` in pipeline YAMLs was ambiguous — could mean total executions or retry count. errors.md described 2 escalating E5-QUALITY retry strategies requiring 3 total executions, but YAMLs had `max_attempts: 2`.
**Decision:** `max_attempts` means total executions including the original attempt. E5-QUALITY gets `max_attempts: 3` for Standard/Full/Decomposition (original + simple retry + architect rethink) and `max_attempts: 2` for Quick (original + simple retry). E6-AGENT gets `max_attempts: 2` everywhere (original + 1 retry).
**Consequences:** The architect-rethink escalation path in errors.md is now reachable. All pipeline YAMLs include a comment defining the semantics.

## D-096: Orchestrator State Management via Direct YAML Writes

**Date:** 2026-03-16
**Status:** Accepted
**Context:** Audit H-01 found that skills reference shell functions (moira_state_gate, moira_state_transition, etc.) as if the orchestrator calls them, but orchestrator.md Section 1 explicitly prohibits bash execution and allowed-tools excludes Bash.
**Decision:** The orchestrator manages state by directly reading and writing YAML files using Read/Write tools. Shell functions in lib/ serve as canonical reference for the logic (which fields, which values, which files). Skills that reference shell functions mean "perform the equivalent YAML writes."
**Consequences:** No new infrastructure needed. Shell functions remain single source of truth for state logic. Skills use consistent language pattern: "write the equivalent of function_name() updates."

*(D-097 reserved — unused, number skipped during Phase 12 planning)*

## D-098: Version Snapshot for Upgrade Three-Way Comparison

**Date:** 2026-03-16
**Status:** Accepted
**Context:** The upgrade system needs a way to perform three-way merge comparison between the user's current (possibly customized) files, the originally installed version, and the new version being upgraded to. Without a baseline snapshot of the installed version, there is no way to distinguish user customizations from original content.
**Decision:** Store a version snapshot at `~/.claude/moira/.version-snapshot/` containing a copy of installed files at install time. This snapshot serves as the common ancestor in three-way comparison during upgrades: snapshot (base) vs current (user's version) vs new (upgrade target).
**Alternatives rejected:**
- Diff-only approach (store diffs from each version) — requires maintaining diff chains, complex to reconstruct base state
- Git-based tracking — adds git dependency for global layer, overkill for simple version comparison
- No snapshot (two-way merge only) — cannot distinguish user customizations from original content, risks overwriting intentional changes
**Reasoning:** Three-way merge is the standard approach for upgrade systems that need to preserve user customizations. The snapshot is created once at install time and updated after each successful upgrade. Storage cost is minimal (copy of core files). Referenced in `design/architecture/overview.md` file structure.

## D-099: Post-Agent Guard Verification

**Date:** 2026-03-17
**Status:** Accepted
**Context:** F-002 from task pipeline testing revealed that PostToolUse hooks (`guard.sh`, `budget-track.sh`) fire only in the main orchestrator session. Agents dispatched via the Agent tool run as separate subprocesses that do not inherit parent hooks. This means Guard Layer 2 (D-031) is bypassed for all agent work — which is where ALL project file modifications happen. Budget tool-call tracking similarly has no data from agents.
**Decision:** Replace hook-based Layer 2 for agents with post-agent git diff verification. After each file-modifying agent (implementer, explorer) returns, the orchestrator runs `git diff --name-only` and checks modified files against a protected paths list. Violations block the pipeline via a Guard Violation Gate (revert/accept/abort). Guard.sh stays as Layer 2 for orchestrator-level violations. Two sub-decisions: (1) protected paths are defined inline in orchestrator.md (single source of truth alongside the check logic, not in a separate config file), (2) agent self-reporting via `moira_state_agent_done` is authoritative for budget tracking (hooks only log tool_name + file_path + file_size, not token counts).
**Alternatives rejected:**
- Inject hooks into agent prompts — unreliable, violates separation of concerns
- Agent worktree isolation — overhead on worktree create/cleanup, complex merge logic, breaks sequential agent visibility
- Project-level hooks propagation — depends on undocumented Claude Code behavior, not architecturally sound
- Accept limitation with no structural check — Art 6.3 (Invariant Verification) unsatisfied for agent work
**Reasoning:** Post-agent diff is strictly stronger than hooks: it can block the pipeline (D-075 confirms PostToolUse hooks can only detect, not prevent). More efficient (one git diff per agent vs dozens of per-tool-call hook invocations). Independent of Claude Code subprocess architecture. Satisfies Art 6.3 "verification agent" interpretation.
