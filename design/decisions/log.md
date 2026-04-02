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
**Decision:** Move locks.yaml to committed config zone (`.moira/config/locks.yaml`). Add TTL (`expires_at` field) for stale lock detection.
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

**Context:** First task execution on sveltkit-todos revealed that all pipeline skills (`task.md`, `orchestrator.md`, `dispatch.md`, `errors.md`, `bypass.md`) hardcoded `~/.claude/moira/state/` for state writes. This caused state to be written to the global directory instead of the project-local `.moira/state/`, making init scans invisible to the orchestrator and breaking deep scan triggers. See `design/reports/2026-03-13-first-task-execution-sveltkit-todos.md`.
**Decision:** Two base paths, no resolution logic needed:
- **Global (read-only):** `~/.claude/moira/` — core rules, pipelines, templates, skills, lib
- **Project (read-write):** `.moira/` — state, config, knowledge
All skills use `.moira/` for state/config/knowledge and `~/.claude/moira/` for core definitions. Path Resolution section added to `orchestrator.md` Section 1.
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
**Decision:** MCP registry lives in `.moira/config/mcp-registry.yaml` (committed) — same as `budgets.yaml` and `locks.yaml`.
**Alternatives rejected:**
- Store in `state/` (gitignored) — team members wouldn't share MCP classifications, user customizations lost on re-init
- Store outside `.moira/` — breaks project layer containment
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
**Status:** Accepted (reasoning corrected 2026-03-20, see D-116)
**Context:** F-002 from task pipeline testing observed that `settings.json` PostToolUse hooks (`guard.sh`, `budget-track.sh`) do not propagate to subagent sessions. Claude Code does support hooks in subagent frontmatter (PreToolUse, PostToolUse, Stop) — these fire during the subagent's own execution. However, Moira agents are dispatched via the Agent tool with dynamically constructed prompts, not as static `.claude/agents/` definitions with frontmatter. Adding hooks via frontmatter would require restructuring agent dispatch architecture.
**Decision:** Use post-agent git diff verification as the guard mechanism for agent work. After each file-modifying agent (implementer, explorer) returns, the orchestrator runs `git diff --name-only` and checks modified files against a protected paths list. Violations block the pipeline via a Guard Violation Gate (revert/accept/abort). Guard.sh stays as Layer 2 for orchestrator-level violations. Two sub-decisions: (1) protected paths are defined inline in orchestrator.md (single source of truth alongside the check logic, not in a separate config file), (2) agent self-reporting via `moira_state_agent_done` is authoritative for budget tracking (hooks only log tool_name + file_path + file_size, not token counts).
**Alternatives rejected:**
- Subagent frontmatter hooks — would require migrating Moira agents to static `.claude/agents/` definitions; current dynamic prompt construction is incompatible (see D-116 for future consideration)
- Agent worktree isolation — overhead on worktree create/cleanup, complex merge logic, breaks sequential agent visibility
- Accept limitation with no structural check — Art 6.3 (Invariant Verification) unsatisfied for agent work
**Reasoning:** Post-agent diff has architectural advantages regardless of hook availability: one git diff per agent vs dozens of per-tool-call hook invocations; can block the pipeline (unlike PostToolUse which fires after the fact — D-075); works with Moira's dynamic dispatch model without requiring agent definition restructuring. PreToolUse hooks in subagent frontmatter could provide real-time blocking but would require migrating to static agent definitions — a larger architectural change deferred per D-116.

## D-100: Project Graph — Structural Topology via Rust CLI

**Date:** 2026-03-17
**Status:** Accepted
**Context:** Agents (especially Explorer and Planner) spend significant tokens on blind file discovery — grep/glob searches that read many irrelevant files. There is no structural map of file dependencies, architectural layers, or module boundaries. Impact analysis (blast radius) requires reading and understanding code every time.
**Decision:** Introduce Project Graph — a deterministic structural topology map built by a standalone Rust CLI (`moira-graph`) using tree-sitter for language-agnostic import parsing. Graph stored as JSON (source of truth) with markdown views (L0/L1/L2) for agent consumption. Algorithms: Reverse BFS (blast radius), Brandes (betweenness centrality), Tarjan (SCC/cycle detection), Louvain (clustering), Topological Sort (architectural layers). Incremental updates via content hash delta. Integrated into init/refresh/status/health commands. Available as `/moira:graph` skill and standalone CLI.
**Alternatives rejected:**
- Agent-driven parsing (Hermes reads files) — expensive in tokens, non-deterministic, slow on large projects
- Regex-based parsing — fragile, doesn't scale across languages
- Language-specific tools (tsc, go vet, etc.) — requires each tool installed, inconsistent output formats
- SQLite storage (like Anamnesis) — unnecessary for deterministic data that doesn't need queries beyond what JSON provides
**Reasoning:** Tree-sitter provides accurate AST-based parsing for 100+ languages with zero LLM token cost. Rust gives single-binary distribution with fastest execution (3000 files in 1-3s). Graph is structural data, not knowledge — it doesn't learn or decay, just reflects current code. Clear separation from Anamnesis (future): graph = topology, Anamnesis = semantics.

## D-101: Project Graph Language Support via Tree-sitter Trait

**Date:** 2026-03-17
**Status:** Accepted
**Context:** Project Graph must work across any tech stack (JS/TS, Go, Python, Rust, C#, Java, and more). Need extensible language support without per-language complexity explosion.
**Decision:** Each language implements a `LanguageParser` trait (extensions, tree-sitter grammar, import/export extraction, path resolution). Tier 1 (initial): TypeScript/JavaScript, Go, Python, Rust, C#, Java. Tier 2 (future): Kotlin, Swift, C/C++, PHP, Ruby, Dart. Tier 3 (on demand): everything else. Adding a language = implementing one trait + adding grammar crate dependency.
**Alternatives rejected:**
- Universal regex parser — too fragile for edge cases (multi-line imports, string interpolation, comments)
- Single monolithic parser — violates extensibility, hard to test per-language
**Reasoning:** Trait-based design keeps each language isolated and testable. Tree-sitter grammars are maintained by language communities. 6 Tier 1 languages cover ~85% of projects.

## D-102: Project Graph — Graceful Degradation Without Binary

**Date:** 2026-03-17
**Status:** Accepted
**Context:** `ariadne` is an external Rust binary. Users may not have it installed. Moira should not break without it.
**Decision:** Moira checks for `ariadne` at init and reports status. If absent, all graph features are unavailable but Moira operates normally (agents work without graph data, just less efficiently). Installation instructions shown. Graph features are additive enhancement, not hard dependency.
**Alternatives rejected:**
- Require ariadne as hard dependency — blocks adoption
- Bundle ariadne with Moira — Moira is shell/markdown, can't bundle Rust binaries
**Reasoning:** Graceful degradation matches Moira's philosophy: system works at any capability level, additional tools enhance quality. Users adopt graph when ready.

## D-103: Project Graph — Future Anamnesis Integration Boundary

**Date:** 2026-03-17
**Status:** Accepted
**Context:** Anamnesis (neural knowledge graph) will eventually replace Moira's Knowledge System. Project Graph must not overlap or conflict with Anamnesis.
**Decision:** Clear boundary: Graph stores topology (files, imports, layers), Anamnesis stores semantics (patterns, decisions, failures). Graph domains/tags designed to be compatible with Anamnesis taxonomy format. Integration at query level only — each system maintains its own storage. Graph nodes can be referenced by Anamnesis engrams via file path.
**Alternatives rejected:**
- Merge graph into Anamnesis — mixes deterministic structure with probabilistic knowledge, violates single-responsibility
- Independent with no compatibility — makes future integration costly
**Reasoning:** Complementary layers with shared vocabulary enable future integration without coupling. Topology is deterministic (from code), knowledge is probabilistic (from experience) — fundamentally different update semantics.

## D-104: Project Graph as Separate Project (Ariadne)

**Date:** 2026-03-17
**Status:** Accepted
**Context:** `moira-graph` was originally designed as a subdirectory within the Moira repository. However, it's a standalone Rust binary with zero dependency on Moira's shell/markdown infrastructure. Different tech stack, different CI/CD, different release cycle.
**Decision:** The project graph engine is extracted into a separate project called **Ariadne** (Greek mythology — the thread through the labyrinth). Ariadne has its own repository, CI/CD, versioning, and roadmap. Moira's Phases 13-14 (graph engine + algorithms) move to Ariadne's Phases 1-2. Moira's Phase 15 (integration) becomes Moira's Phase 13. Ariadne has no knowledge of Moira. All references in Moira change from `moira-graph` to `ariadne`.
**Alternatives rejected:**
- Subdirectory in Moira repo — GitHub Actions doesn't work from nested `.github/`, `cargo install` doesn't work from subdirectory, Rust toolchain not needed for core Moira
- Git submodule — complexity without benefit
**Reasoning:** Clean separation enables: standard `cargo install ariadne`, native CI/CD, independent releases. The tool is useful beyond Moira — any system that needs structural code analysis can use it. Moira consumes Ariadne as an external binary via PATH, same as any other CLI tool.

## D-105: Moira Reads `.ariadne/` Directly (No Copy/Symlink)

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Ariadne writes output to `.ariadne/graph/` and `.ariadne/views/`. Moira needs to read this data. Two options: copy/symlink to `.moira/graph/`, or read from `.ariadne/` directly.
**Decision:** Moira reads from `.ariadne/` directly. No copying, no symlinking. The `.ariadne/` directory is committed to git (deterministic, reproducible output).
**Alternatives rejected:**
- Copy to `.moira/graph/` — creates duplication, stale copy risk, adds a sync step to init/refresh
- Symlink — adds complexity, may break on Windows, no benefit over direct reads
**Reasoning:** Ariadne owns `.ariadne/`. Moira is a consumer. Direct reads are simplest, avoid sync issues, and maintain clear ownership boundaries. Committed to git because graph output is deterministic and reproducible (same code = same graph).

## D-106: Graph Health as Subsection of Structural Score

**Date:** 2026-03-19
**Status:** Accepted
**Context:** `/moira:health` uses a composite score: Structural (30%) + Quality (50%) + Efficiency (20%). Graph health checks (cycles, bottlenecks, smells, monolith score) need a home in this scoring model.
**Decision:** Graph health is a subsection of Structural health (part of the 30% weight). If graph is unavailable, graph health items are skipped (not penalized). The structural score is computed from the remaining items.
**Alternatives rejected:**
- Separate top-level category — would require rebalancing all weights, over-engineering for an optional feature
- Part of Quality — graph health is structural (code topology), not quality (agent output)
**Reasoning:** Graph data is structural by nature (file dependencies, layers, coupling). Adding it to the structural category is semantically correct. Skipping when unavailable ensures users without Ariadne aren't penalized.

## D-107: Pre-Planning Agents Receive L0 Graph via Dispatch

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Pre-planning agents (Apollo, Hermes, Athena, Metis) run before Daedalus, so they can't receive graph data through instruction files. How should they get graph context?
**Decision:** Dispatch skill includes L0 graph index (`views/index.md`, ~200-500 tokens) in the dispatch context for pre-planning agents when `graph_available` is true. Daedalus receives the graph directory path instead, so it can run queries and build instruction files.
**Alternatives rejected:**
- No graph data for pre-planning agents — loses the benefit of graph-informed classification and exploration
- Full graph data in dispatch — too large, wastes context budget for agents that need minimal orientation
**Reasoning:** L0 is small (~200-500 tokens) and provides cluster overview + critical files — sufficient for classification complexity assessment and exploration targeting. Daedalus needs the path to query deeper data. Post-planning agents get full graph sections via instruction files.

## D-108: Ariadne MCP as Infrastructure Tool (Always Available)

**Date:** 2026-03-19
**Status:** Accepted
**Context:** During the first real Moira session, Ariadne's `serve` command (MCP server mode) was not registered in Claude Code settings. Agents could only use static pre-generated views, missing the main value of Ariadne integration — interactive graph queries (blast-radius, cycles, centrality, smells). The MCP design (mcp.md) treats all MCP tools uniformly as "managed resources" allocated per-step by Daedalus. But Ariadne is fundamentally different: it's read-only structural data, zero external API risk, near-zero cost, and the graph engine Moira itself depends on.
**Decision:** Ariadne MCP is classified as an **infrastructure MCP tool** — always registered during init (if binary supports `serve`), always available to graph-aware agents regardless of pipeline type. No per-step Daedalus authorization required. The orchestrator registers `ariadne serve` in `.mcp.json` (project root, D-134) during `/moira:init` (Step 4b) and adds Ariadne to the MCP registry with `infrastructure: true` flag. Infrastructure MCP tools bypass the planner authorization gate — they are authorized by default for all agents whose role definition includes graph capabilities.
**Alternatives rejected:**
- Treat Ariadne like any external MCP — requires Daedalus, breaks Quick Pipeline, adds ceremony for zero-risk queries
- Register manually (user responsibility) — defeats purpose of automated init, easy to forget
**Reasoning:** Ariadne is Moira's own structural engine. Requiring Daedalus authorization for read-only graph queries is like requiring permission to read your own config files. Infrastructure classification preserves the managed-resource principle for external tools (context7, figma) while making graph queries frictionless.

## D-109: Quick Pipeline Lightweight MCP Authorization

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Quick Pipeline has no Daedalus (planner) step, so MCP tools cannot be authorized via instruction files. This means Quick Pipeline agents have zero MCP access — even for infrastructure tools like Ariadne. For external MCP tools (context7, figma), this is acceptable for small tasks. But infrastructure MCP should always be available (D-108), and external MCP may occasionally be useful even in Quick Pipeline (e.g., looking up API docs for an unfamiliar library).
**Decision:** The dispatch skill's simplified assembly path (used by Quick Pipeline) includes an `## MCP Usage Rules` section constructed directly from the registry:
- **Infrastructure MCP** (e.g., Ariadne): always authorized, injected automatically
- **External MCP**: authorized based on registry `when_to_use` guidelines, with conservative budget guardrails (agent must verify need before calling)
The orchestrator constructs this section during dispatch — no Daedalus required. Reviewer (Themis) still checks MCP usage in Q4 review.
**Alternatives rejected:**
- No MCP in Quick Pipeline — loses Ariadne integration entirely for the most common pipeline type
- Add a lightweight planner step to Quick — adds latency and complexity, contradicts Quick Pipeline's purpose
- Auto-authorize everything — violates managed-resource principle
**Reasoning:** Quick Pipeline should be fast, not crippled. Infrastructure tools have near-zero risk. External tools need guardrails but not a full planning step — the registry's `when_to_use` / `when_NOT_to_use` guidelines provide sufficient guidance for agents.
**Superseded (infrastructure part):** D-115 extends infrastructure MCP injection to ALL pipelines, not just Quick. D-109 still governs external MCP in Quick Pipeline.

## D-110: Orchestrator Complexity Governance

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Architecture review (2026-03-19) found the orchestrator skill accumulates 7+ responsibilities (pipeline logic, gate presentation, error routing, budget checking, state management, agent dispatch, MCP authorization, graph data injection), approaching Art 1.3 (No God Components) violation. No decision or design constraint limits orchestrator scope.
**Decision:** Define governance metric for orchestrator complexity. The orchestrator skill's responsibility count is tracked. Current baseline: 8 core responsibilities (enumerated below). Threshold: if responsibilities exceed 10, a mandatory architectural review must determine whether to decompose or formally acknowledge the exception. Each phase that adds orchestrator responsibility must document which responsibility is added. Art 1.3's test for the orchestrator is: "orchestrator responsibilities are enumerated and bounded."

**Enumerated baseline responsibilities (8):**
1. **Pipeline logic** — reading pipeline YAML, executing steps in order, handling branching
2. **Gate presentation** — formatting and displaying approval gates, processing user decisions
3. **Error routing** — detecting error conditions, selecting recovery strategy per E1-E11
4. **Budget checking** — pre-execution estimation, orchestrator context threshold monitoring
5. **State management** — reading/writing current.yaml, status.yaml, manifest.yaml
6. **Agent dispatch** — constructing prompts, invoking Agent tool, parsing responses
7. **Post-agent verification** — git diff guard check, violation logging
8. **Analytical pipeline flow** — depth checkpoint looping, redirect handling, convergence tracking (added Phase 14)

**Threshold rationale:** 10 is chosen as ~25% growth from baseline 8. Below 10, the orchestrator remains a coordinator with bounded scope. Above 10, coordination overhead suggests some responsibilities should be factored into sub-skills or utility agents.
**Alternatives rejected:**
- Decompose now into multiple skills — coordination overhead between sub-skills outweighs current complexity
- No governance — complexity grows unbounded, Art 1.3 becomes unenforceable for the most critical component
**Reasoning:** The orchestrator is intentionally more complex than other components because it coordinates all pipeline flow. But "intentionally complex" still needs bounds. A governance metric with threshold creates a structural trigger for decomposition review without premature splitting.

## D-111: Formal Methods — Partially Implemented

**Date:** 2026-03-19
**Status:** Accepted (updated 2026-03-22: implementation diverged — exponential decay and adaptive margin were implemented during Phases 7/10/11, Markov retry remains deferred)
**Context:** Architecture review (2026-03-19) found D-094's formal methods suite (SPRT, CUSUM, BH correction, Markov retry, exponential decay) adds ~30% implementation surface to Phases 7, 10, and 11 for statistical techniques that require scale (hundreds of tasks, dozens of test cases) to provide value. Moira processes ~47 tasks/month. CPM (Critical Path Method) for batch scheduling is the exception — directly useful at any scale.
**Decision (original):** Defer SPRT, CUSUM, Benjamini-Hochberg correction, Markov retry optimization, and exponential knowledge decay to post-v1. Keep CPM for batch scheduling.
**Actual implementation:** During Phases 7, 10, and 11 implementation, exponential knowledge decay (`knowledge.sh`), adaptive budget margins (`budget.sh`), and Markov retry optimization (`retry.sh`) were all implemented with cold-start defaults that match simple behavior (30% margin, no decay with <5 observations, hard limits as upper bounds). These are now active subsystems.
**Current status of each technique:**
- CPM batch scheduling — implemented (as planned)
- Exponential knowledge decay — implemented (cold-start safe)
- Adaptive budget margin — implemented (cold-start safe)
- Markov retry optimizer — implemented (hard limits as upper bounds, EMA-smoothed probabilities)
- SPRT — deferred to post-v1
- CUSUM — deferred to post-v1
- Benjamini-Hochberg — deferred to post-v1

## D-112: Plan Gate Backward Flow (Rearchitect Option)

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Architecture review (2026-03-13, finding S-9, still unresolved in 2026-03-19 review) found that when user feedback at the plan gate implies architectural disagreement, the only options are "modify" (sends to Planner, who can't change architecture) or "abort" (loses all work). No controlled backward path to the Architect exists.
**Decision:** Add a "rearchitect" option at the plan gate (and decomposition gate) that routes the pipeline back to the Architecture step. The Architect receives the original architecture + user's feedback. After revised architecture, the architecture gate is re-presented. Then the Planner runs with the new architecture. Maximum 1 rearchitect per pipeline execution to prevent infinite loops.
**Alternatives rejected:**
- No backward path — forces abort on architectural disagreement, wastes all prior work
- Let Planner handle architectural changes — violates Art 1.2 (Planner never makes architectural decisions)
- Unlimited rearchitects — risk of infinite loop
**Reasoning:** The plan gate is the first point where the user sees the concrete consequences of architectural decisions. Discovering architectural issues at this stage is common and legitimate. A single rearchitect is cheap (one Architect + one Planner dispatch) compared to full abort and restart.

## D-113: Instruction Size Validation Before Agent Dispatch

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Architecture review (2026-03-19) found that assembled agent instructions (Layers 1-4 + knowledge + graph + MCP rules) have no size limit or validation. If the Agent tool platform has a message size limit, trailing instructions (Layer 4 task-specific — the most important part) could be silently truncated.
**Decision:** Add instruction size estimation before dispatch. If total exceeds 50k tokens (estimated via byte count / 4), reduce knowledge and graph data to lower levels (L2→L1→L0) until instructions fit. Layer 4 (task-specific) instructions are never truncated — they are placed last in assembly but are the highest priority. The reduction order is: graph extras first, then knowledge L2→L1, then graph L1→L0.
**Alternatives rejected:**
- No validation — silent truncation of critical instructions
- Hard fail on oversized instructions — blocks legitimate large-context agents like Explorer
**Reasoning:** Graceful degradation (reduce context richness) is better than silent truncation or hard failure. Layer 4 priority ensures task-specific instructions are always preserved. The 50k threshold is conservative — it leaves room for the Agent tool's own overhead.

## D-114: Mid-Pipeline State Protection

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Architecture review (2026-03-19) found three mid-pipeline state consistency gaps: (1) external file mutations during pipeline go undetected (S-4), (2) pipeline state transitions are behavioral, not validated (S-5), (3) state YAML writes are not atomic (S-6).
**Decision:** Three mitigations: (a) At each pipeline step boundary, perform a quick `git status` check. If modified files overlap with the pipeline's working set, pause and present options (accept/re-explore/abort). (b) Validate each state transition against the pipeline YAML definition — check that step Y is a valid successor of step X. Invalid transitions are logged and blocked. (c) All state YAML writes use atomic write pattern (write to temp file, then rename). Manifest maintains a one-back backup (manifest.yaml.bak) for recovery.
**Alternatives rejected:**
- No mid-pipeline protection — compounds three low-probability risks into meaningful exposure
- Full file-system watchers — over-engineering for the actual risk level
- Lock files during pipeline execution — prevents legitimate human edits
**Reasoning:** Each mitigation is lightweight (git status, YAML lookup, temp-file rename) and addresses a distinct failure mode. Combined, they close the mid-pipeline state consistency gap without adding significant overhead.

## D-115: Infrastructure MCP Universal Injection

**Date:** 2026-03-20
**Status:** Accepted
**Context:** Ariadne MCP server was registered as infrastructure MCP (D-108) and marked "always available to graph-aware agents regardless of pipeline type." However, dispatch only injected MCP instructions for Quick Pipeline agents (D-109) and Daedalus. Pre-planning agents in Standard/Full/Decomposition pipelines received L0 graph data as static text but had no MCP instructions — meaning they didn't know they could call Ariadne tools interactively. In practice, this led to zero MCP calls across all agents: Hermes read 46 files sequentially instead of using `ariadne_file`/`ariadne_subgraph` for targeted navigation. Claude Code subagents inherit MCP servers from the parent session, so the tools were technically available but agents were never told about them.
**Decision:** Infrastructure MCP tools are injected into ALL agent prompts in ALL pipelines via a new dispatch step 4c. Dispatch appends an `## Infrastructure Tools (Always Available)` section listing all infrastructure MCP tools from the registry. This applies to pre-planning agents, Daedalus, and post-planning agents equally. External MCP authorization remains unchanged (Quick Pipeline: registry-based guidelines; Standard/Full: Daedalus per-step authorization).
**Alternatives rejected:**
- CLI fallback (agents use `ariadne query` via Bash instead of MCP) — unnecessary indirection; subagents already inherit MCP servers
- Orchestrator-mediated queries only (orchestrator pre-fetches and passes as context) — removes interactive capability; agents can't drill down on demand
- Keep current design (static L0 only) — proven ineffective; zero MCP calls, 72k tokens wasted on sequential file reads
**Reasoning:** The gap was between design intent (D-108: "always available") and dispatch implementation (MCP instructions only for Quick Pipeline). Subagents inherit MCP servers from the parent session — the infrastructure tools are callable, agents just need to be told about them. Universal injection closes this gap with minimal change: one new dispatch step, one new prompt section.

## D-116: Subagent Frontmatter Hooks — Platform Capability Acknowledged

**Date:** 2026-03-20
**Status:** Accepted
**Context:** F-002 (2026-03-17) concluded that "PostToolUse hooks don't fire for subagent tool calls — architectural limitation of Claude Code." This was factually incorrect. Claude Code supports hooks defined in subagent frontmatter (`PreToolUse`, `PostToolUse`, `Stop`) that fire during the subagent's own execution. What does NOT happen is automatic propagation of `settings.json` hooks to subagent sessions. Additionally, `SubagentStart`/`SubagentStop` events in `settings.json` fire in the main session when subagents start/stop. Plugin-provided subagents are the only exception — their `hooks`, `mcpServers`, and `permissionMode` fields are ignored for security.
**Decision:** (1) Correct all design docs that claim hooks cannot fire for subagents. (2) Retain D-099 post-agent git diff as the chosen guard mechanism — it has architectural merits independent of hook availability. (3) Note subagent frontmatter hooks as a future migration path: if Moira agents are restructured as static `.claude/agents/` definitions (instead of dynamic prompt construction via dispatch.md), guard and budget hooks can be defined directly in agent frontmatter, enabling real-time PreToolUse blocking within agent sessions.
**Alternatives rejected:**
- Immediate migration to frontmatter hooks — requires restructuring agent dispatch architecture (dynamic prompts → static definitions), too large a change for a factual correction
- Keep incorrect docs — factual errors in design docs violate knowledge integrity
**Reasoning:** Design docs must be factually accurate about the platform they build on. The post-agent diff approach remains sound on its own merits (efficiency, blocking capability, compatibility with dynamic dispatch). Acknowledging the platform capability opens a future optimization path without forcing immediate architectural change.

## D-117: Two-Dimensional Classification (Mode + Size)

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Moira's classification is one-dimensional (size: small/medium/large/epic), forcing all tasks through code-producing pipelines. Analytical tasks (architecture review, audits, documentation, weakness analysis) don't produce code and need a different pipeline structure.
**Decision:** Apollo classifies on two dimensions: `mode` (implementation | analytical) and `size`/`subtype`. Implementation mode uses existing size-based pipeline selection. Analytical mode routes to a new Analytical Pipeline regardless of task complexity — depth is handled dynamically within the pipeline via progressive depth gates rather than upfront sizing.
**Alternatives rejected:**
- Separate classifier for analytical tasks — violates D-028 (Classifier as single agent), adds complexity
- Size-based analytical pipelines (quick-analytical, full-analytical) — analytical task complexity is hard to estimate upfront; progressive depth handles this better
- Mode as a pipeline modifier on existing pipelines — too many code-oriented steps would need conditional skipping, resulting in messy conditionals rather than clean design
**Reasoning:** Two-dimensional classification is the minimal extension that supports analytical tasks without disrupting existing implementation pipelines. Art 2.1 determinism preserved: same classification → same pipeline.

## D-118: Calliope (Scribe) as 11th Agent

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Analytical pipelines produce markdown documents, not code. Someone needs to synthesize analysis findings into coherent deliverables. Hephaestus (implementer) writes code — using it for document synthesis would violate Art 1.2 (single responsibility) or require a fuzzy dual-role definition.
**Decision:** New agent Calliope (Καλλιόπη, Muse of epic poetry). Single responsibility: synthesize structured findings into markdown documents. Reads existing docs + findings, writes/updates markdown. Never analyzes, never decides what to include, never writes code.
**Alternatives rejected:**
- Hephaestus with analytical mode — blurs "writes code" responsibility, two fundamentally different skill profiles in one agent
- Analysis agents write their own documents — merges analysis and synthesis responsibilities, producing either shallow analysis or poorly structured documents
- No dedicated writer (orchestrator presents findings directly) — loses the synthesis step that turns raw findings into actionable, well-structured documents
**Reasoning:** Art 1.2 requires single responsibility per agent. Writing code and writing analytical documents are different skills requiring different instructions, different quality criteria, and different tool access. A dedicated scribe agent maintains clean separation.

## D-119: Analytical Pipeline with Progressive Depth

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Unlike code tasks where size is estimable upfront (file count, scope), analytical task depth is unknown until investigation begins. A fixed-size pipeline either over-engineers simple research questions or under-serves deep audits.
**Decision:** Single Analytical Pipeline with progressive depth controlled by depth checkpoint gates. Analysis runs in passes; after each pass, user decides: sufficient (proceed to synthesis), deepen (another pass with expanded scope), or redirect (re-scope). Convergence metrics (CS-1: fixpoint, CS-2: coverage) inform the decision but don't control it.
**Alternatives rejected:**
- Multiple analytical pipeline sizes (light/standard/deep) — requires upfront estimation of analytical depth, which is the exact problem we're solving
- Automatic deepening without gates — violates Art 4.2 (user authority)
- Single-pass only with optional re-run — loses continuity between passes, each pass starts from scratch
**Reasoning:** Progressive depth turns "we don't know how deep to go" from a problem into a feature. Each pass builds on previous findings. Convergence metrics give the user data to make informed depth decisions. Art 2.2 compliance: gates are structurally fixed (classify, scope, depth checkpoints, final) even though depth checkpoints may repeat.

## D-120: Ariadne Level C Integration for Analytical Pipeline

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Ariadne provides structural analysis data (smells, coupling, metrics, cycles, layers, spectral analysis). For analytical tasks, this data is primary input rather than supplementary context. Need to decide integration depth.
**Decision:** Two-tier integration. Tier 1 (Gather phase): fixed baseline queries run automatically — overview, smells, metrics, layers, cycles, clusters. Results written to state file, available to all subsequent agents. Tier 2 (Analysis phase): Metis/Argus have direct access to Ariadne MCP tools for targeted, hypothesis-driven queries during their analysis passes.
**Alternatives rejected:**
- Tier 1 only (fixed queries) — too rigid, agents can't follow investigation threads
- Tier 2 only (agent-driven) — agents might miss important data they didn't think to query; baseline ensures consistent foundation
- Ariadne as separate pipeline step with dedicated agent — over-engineering; Ariadne is a tool, not an analytical actor
**Reasoning:** Baseline queries ensure every analysis starts with the same structural foundation (deterministic). Agent-driven queries enable hypothesis-testing and deep investigation (flexible). The combination maximizes Ariadne's value without making the pipeline Ariadne-dependent (graceful degradation per D-102 still applies).

## D-121: Six CS Methods for Analytical Rigor

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Analytical quality is harder to assess than code quality. Code either compiles or doesn't, tests pass or fail. Analysis can be superficial, biased, incomplete, or poorly structured without any obvious "failure" signal. Need formal methods to ensure analytical rigor.
**Decision:** Six CS methods embedded in the analytical pipeline: (1) Fixpoint convergence — formal termination criterion for depth, (2) Graph-based coverage — completeness metric using Ariadne as coverage space, (3) Hypothesis-driven analysis — scientific method structure for findings, (4) Abductive reasoning — competing explanations for architectural symptoms, (5) Information gain — prioritization for deepening direction, (6) Lattice-based organization — partial order on findings for document structure.
**Alternatives rejected:**
- Informal quality criteria only ("be thorough", "check alternatives") — unenforceable, degrades over time
- Subset of methods (e.g., only convergence + coverage) — each method addresses a distinct failure mode; removing any leaves a gap
- Additional methods (e.g., formal model checking) — over-engineering for LLM-based analysis; these six cover the practical failure modes
**Reasoning:** Each method solves a specific analytical failure mode: convergence prevents endless deepening, coverage prevents blind spots, hypothesis-driven prevents unsupported claims, abduction prevents shallow analysis, information gain prevents wasted effort, lattice prevents disorganized output. Together they make analytical quality as measurable as code quality (through QA1-QA4 checklists).

## D-122: Analytical Quality Gates QA1-QA4

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Code pipelines use Q1-Q5 quality gates (completeness, soundness, feasibility, correctness, coverage). These don't apply to analytical tasks — there's no code correctness to check, no test coverage to measure.
**Decision:** Four analytical quality gates: QA1 (Scope Completeness — structural coverage, all questions answered), QA2 (Evidence Quality — hypothesis-evidence-verdict format, concrete citations), QA3 (Actionability — concrete recommendations, justified priorities), QA4 (Analytical Rigor — competing explanations, no confirmation bias, cross-validation). Severity classification same as code review: critical/warning/suggestion.
**Alternatives rejected:**
- Reuse Q1-Q5 with modifications — too much doesn't apply; forced mapping produces meaningless checks
- Single quality gate ("is the analysis good?") — too vague, no actionable feedback on what's wrong
- Six gates (one per CS method) — methods overlap with gates; four gates that reference multiple methods is cleaner
**Reasoning:** QA1-QA4 are designed to catch real analytical weaknesses: incomplete scope, unsupported claims, impractical recommendations, shallow reasoning. Each gate is actionable — a QA2 failure tells Metis/Argus exactly what needs more evidence. The gates reference CS methods (QA1→CS-2, QA2→CS-3, QA4→CS-4) but aren't 1:1 with them.

## D-123: Conditional Branching via Gate next_step Fields

**Date:** 2026-03-22
**Status:** Accepted
**Context:** The analytical pipeline's depth checkpoint can loop back to analysis or scope, unlike linear existing pipelines. Need a branching mechanism.
**Decision:** Gates with `branching: true` flag carry `next_step` fields on their options. The orchestrator reads the user's chosen option and jumps to the specified step. This is a targeted extension to the gate system, not a pipeline engine refactor.
**Alternatives rejected:**
- Step-level `next` field map — breaks pattern of flow control on gates, not steps
- Generic pipeline engine refactor — over-engineering, high risk, violates scope discipline
**Reasoning:** Gate decisions already determine what happens next. Adding `next_step` to gate options is the minimal extension that enables non-linear flow while keeping the gate as the decision point.

## D-124: Apollo SUMMARY Format Extension with Mode Prefix

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Apollo needs to output both mode (implementation/analytical) and size/subtype dimensions.
**Decision:** Extend SUMMARY format: `mode=implementation, size=X, confidence=Y` for implementation; `mode=analytical, subtype=X, confidence=Y` for analytical. Backward compatible — missing `mode=` prefix treated as implementation.
**Alternatives rejected:**
- Separate mode field outside SUMMARY — breaks response contract
- Separate classifier for analytical — violates D-028 (single classifier)
**Reasoning:** Extending the existing SUMMARY line preserves the response contract while adding the mode dimension. Backward compatibility ensures existing pipelines continue to work.

## D-125: Ariadne Baseline via Hermes (Not Separate Action Step)

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Design doc shows Ariadne baseline as a parallel `action` step alongside Hermes in gather. But the orchestrator cannot run Bash, and all pipeline steps are agent dispatches.
**Decision:** Hermes executes Ariadne baseline queries as part of the gather step. Hermes writes both `exploration.md` and `ariadne-baseline.md`. If Ariadne unavailable, Hermes notes it and continues.
**Alternatives rejected:**
- New "action" step type — introduces new execution concept not present in existing pipelines
- Separate lightweight agent for Ariadne queries — unnecessary agent for 6 CLI calls
**Reasoning:** Hermes already runs CLI commands during exploration. Adding 6 Ariadne queries is a natural extension of the explorer role. Single agent writing two artifacts is simpler than inventing a new step type.

## D-126: Simplified Assembly for All Analytical Pipeline Agents

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Implementation pipelines use Daedalus to assemble instructions. Analytical pipeline has no planner step.
**Decision:** All analytical pipeline agents use simplified assembly (the fallback path already used for pre-planning agents and Quick pipeline). CS method instructions are embedded in agent role YAMLs under `analytical_mode` sections.
**Alternatives rejected:**
- Add a planning step to analytical pipeline — unnecessary, analytical tasks don't need implementation plans
- Have scope step assemble instructions — scope is about analysis scope, not instruction assembly; violates single responsibility
**Reasoning:** Simplified assembly already works for all pre-planning agents in all pipelines. The analytical pipeline doesn't generate code, so there's no implementation plan to assemble from. CS method templates in role YAMLs are activated conditionally by the orchestrator when pipeline=analytical.

## D-127: CS Method Tiering (Tier A/B)

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Architecture review (2026-03-22) found that 4 of 6 CS methods (CS-1, CS-2, CS-4, CS-5) depend on Ariadne for their primary value, while CS-3 (hypothesis-driven) and CS-6 (lattice organization) work without Ariadne. Implementing all six adds prompt complexity with uncertain v1 value for the Ariadne-dependent methods.
**Decision:** Two tiers: Tier A (v1 operational, no Ariadne dependency) = CS-3 and CS-6. Tier B (activate when Ariadne analytical integration is validated) = CS-1, CS-2, CS-4, CS-5. Tier B methods are fully designed but included in agent instructions conditionally — they activate only when Ariadne is available and indexed. Without Ariadne, depth checkpoint convergence uses simple finding count delta.
**Alternatives rejected:**
- Implement all six unconditionally — CS-1/2/4/5 without Ariadne degrade to prompt decoration (vague guidance without concrete metrics)
- Defer Tier B design entirely — the methods are sound and will be needed once Ariadne analytical integration matures
**Reasoning:** CS-3 and CS-6 change agent behavior in directly verifiable ways (structured finding format, hierarchical document structure) without any external dependency. CS-1/2/4/5 are formal methods that require concrete data (centrality, coverage, smell density) to be meaningful. Conditional activation avoids dead prompt complexity while preserving the design for when Ariadne provides that data.

## D-128: Art 2.2 Amendment — Analytical Pipeline Gates

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Architecture review (2026-03-22) found that CONSTITUTION.md Art 2.2 enumerated gates for only four pipeline types. The Analytical Pipeline's variable-count depth checkpoints didn't fit the enumeration, causing constitutional verification to produce false results.
**Decision:** Amend Art 2.2 to add: "Analytical: classification + scope + depth checkpoint(s) + final." Note that depth checkpoints may repeat (progressive depth per D-119) but MUST NOT be skipped. Also amend Art 2.1 to add: "Analytical (any subtype) → Analytical Pipeline." Update the Invariant Verification Checklist accordingly.
**Alternatives rejected:**
- Annotate gate enumeration as implementation-pipeline-specific — creates a class of pipelines exempt from constitutional verification, undermining Art 2.2's purpose
**Reasoning:** The Constitution should be honest about what the system actually does. The Analytical Pipeline has deterministic gates — the gate types are fixed, only the depth checkpoint count varies by user decision (Art 4.2). This is consistent with Art 2.2's intent: gates are structural and cannot be skipped.

## D-129: QA1-QA4 Ariadne Items Conditional on Availability

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Architecture review (2026-03-22) found that QA1 and QA2 checklist items explicitly required Ariadne data ("Ariadne data consulted for structural coverage verification", "Ariadne metrics cited with concrete numbers"). Without Ariadne, these items would produce systematic CRITICAL failures, making the analytical pipeline unusable — contradicting D-102 (graceful degradation).
**Decision:** Mark Ariadne-dependent QA items as conditional: "if Ariadne available." Without Ariadne, coverage is assessed from explored file set, and evidence uses code-level references instead of structural metrics.
**Alternatives rejected:**
- Keep items unconditional — makes analytical pipeline a hard Ariadne dependency, contradicts D-102
- Remove Ariadne items entirely — loses the structural coverage value when Ariadne IS available
**Reasoning:** The analytical pipeline should work at any capability level, consistent with Moira's philosophy (D-102). Ariadne enhances analytical quality but shouldn't be a gate blocker. Conditional items preserve the value when available without creating false failures when absent.

## D-130: Redirect Limit and State Preservation

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Architecture review (2026-03-22) found that the depth checkpoint `redirect → scope` path had no specification of finding preservation, no redirect limit, and no definition of what context Athena receives when re-scoping.
**Decision:** (a) Prior analysis-pass-N.md files are preserved on redirect — NOT deleted. (b) Maximum 1 redirect per pipeline execution (matches rearchitect limit in D-112). (c) Athena receives prior findings as context when re-scoping. (d) Post-redirect analysis continues pass numbering (no reset).
**Alternatives rejected:**
- Unlimited redirects — risk of infinite loops between scope and analysis
- Discard prior findings on redirect — loses valid analysis work, wastes tokens
- Fresh pass numbering after redirect — breaks convergence tracking continuity
**Reasoning:** Findings from prior passes are valid data regardless of scope change. Preserving them gives Athena context for better re-scoping and maintains convergence tracking. The 1-redirect limit mirrors the rearchitect pattern — a single controlled backward step, not unlimited looping.

## D-131: Themis Dual-Role in Analytical Pipeline — Acknowledged Exception

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Architecture review (2026-03-22) found that Themis performs two structurally different tasks in the Analytical Pipeline: convergence analysis at depth checkpoints and QA1-QA4 document review at the final gate. This stretches Art 1.2 (single responsibility).
**Decision:** Acknowledge as a documented design exception. Both tasks are quality review with different focus (analytical output quality vs document output quality). A separate agent for convergence analysis is not warranted.
**Alternatives rejected:**
- Separate convergence agent — over-engineering; convergence computation is a subset of Themis's quality assessment, not a distinct skill
- Assign convergence to Athena — Athena formalized the scope but shouldn't judge whether the analysis of that scope is sufficient (conflict of interest)
**Reasoning:** Themis reviews quality. Convergence assessment is "is the analytical quality sufficient to stop?" — a quality judgment. Document review is "does the synthesized document meet quality standards?" — also a quality judgment. Different templates and output files maintain clear separation within the same agent role. The alternative of a 12th agent adds coordination overhead for a task that fits naturally within Themis's existing expertise.

## D-132: Metis as Universal Organizer for CS-6 Lattice

**Date:** 2026-03-22
**Status:** Accepted
**Context:** Architecture review (2026-03-22) found the organize step's agent assignment was ambiguous ("metis or athena depending on subtype") and not specified in the agent_map, forcing an implicit orchestrator decision (Art 2.3 violation).
**Decision:** Metis is the universal organizer for all analytical subtypes. The agent_map is not extended with an organize field — instead, the organize step always dispatches Metis regardless of subtype.
**Alternatives rejected:**
- Per-subtype organize agent — unnecessary complexity; lattice construction is structural reasoning regardless of analytical subtype
- Athena as organizer — Athena's role is scope formalization, not structural organization of findings
**Reasoning:** Lattice construction requires reasoning about causal relationships, scope containment, and dependency between findings — structural reasoning that is Metis's core competency. Using the same agent for all subtypes makes the organize step deterministic (Art 2.1) without needing agent_map lookup.

## D-133: Hybrid Completion Processor (Shell + LLM Agent)

**Date:** 2026-03-22
**Status:** Accepted
**Context:** The orchestrator's Section 7 completion flow (~30 sub-steps in the `done` block) was never fully executing. By the time the orchestrator reached the final gate, LLM context pressure caused it to stop before executing telemetry writes, status finalization, and reflection dispatch. Evidence: task-2026-03-22-001 completed with `completion.action: done` but had no `telemetry.yaml`, no `status: completed`, and no `reflection.md`.
**Decision:**
- (a) Extract the completion flow from orchestrator Section 7 into a dedicated completion processor dispatched as a foreground agent. The orchestrator's `done` block shrinks from ~30 steps to 4 (record action, dispatch processor, handle result, cleanup).
- (b) The completion processor uses a hybrid architecture: a shell script (`lib/completion.sh`) executes mechanical steps 1-17 (telemetry, status, quality aggregation, metrics, cleanup) in a single Bash call (~2 seconds), and the LLM agent handles only step 18 (reflection dispatch — requires Agent tool for Mnemosyne).
- (c) Rename `templates/reflection/standard.md` to `background.md` to match pipeline YAML level names.
**Alternatives rejected:**
- Pure LLM completion agent (all 18 steps) — worked but consumed ~60k tokens and ~4.5 minutes for mechanical YAML operations
- Prompt engineering (emphasize MUST in Section 7) — does not address structural root cause
- Post-hook trigger — hooks cannot dispatch agents
- Separate `/moira:complete` command — UX regression, manual step
- Simplify Section 7 in-place — defers telemetry, loses data
**Reasoning:** The hybrid approach gives structural reliability (fresh context window) with minimal cost (shell for mechanics, LLM only where needed). Expected cost: ~5-10k tokens and ~30 seconds vs 60k tokens and 4.5 minutes for the pure LLM approach. The shell script reuses all existing `moira_*` library functions — no new infrastructure needed.

## D-134: MCP Servers in .mcp.json, Not .claude/settings.json

**Date:** 2026-03-23
**Status:** Accepted
**Context:** Claude Code reads MCP server definitions from `.mcp.json` in the project root, NOT from `.claude/settings.json`. Moira was writing Ariadne MCP configuration to `.claude/settings.json` during `/moira:init` Step 4b.3 — this caused Claude Code to silently ignore the MCP server. The server was functional (responded correctly to JSON-RPC via stdio) but its tools never appeared in Claude Code sessions.
**Decision:** MCP server definitions are written to `.mcp.json` at the project root. `.claude/settings.json` is reserved for hooks, permissions, and other Claude Code settings. New functions `moira_settings_merge_mcp()` and `moira_settings_remove_mcp()` in `settings-merge.sh` handle `.mcp.json` read/write. Init Step 4b.3 updated to target `.mcp.json`. D-108 updated: "registers in `.mcp.json`" replaces "registers in Claude Code settings."
**Alternatives rejected:**
- Keep writing to `.claude/settings.json` — Claude Code does not read MCP servers from there
- Write to `~/.claude/settings.json` (user-level) — per-project MCP should be project-scoped
**Reasoning:** This is a Claude Code platform requirement, not a design choice. `.mcp.json` is the designated file for project-scoped MCP server configuration.

## D-135: Post-Pipeline Terminal State, Classification Validation, Step Enforcement

**Date:** 2026-03-23
**Status:** accepted
**Context:** Three categories of orchestrator violations in task-2026-03-23-002: (1) post-analytical pipeline, orchestrator executed implementation directly instead of requiring new task; (2) Apollo returned invalid size=XL, accepted without validation; (3) Themis skipped at depth_checkpoint and review steps.
**Decision:** (a) After any pipeline reaches `completed` status, orchestrator enters terminal state — further action requires new `/moira:task` or `/moira bypass:`. (b) Classification values are validated against enums at orchestrator level after Apollo returns, with lowercase normalization, E6 retry, and manual fallback. (c) Analytical pipeline tracks completed steps in `current.yaml analytical.completed_steps[]`, verified before final gate. (d) Case normalization applied to classification values before validation.
**Alternatives rejected:**
- Converting analytical pipeline to mechanical iterator — rejected because non-linear flow (deepen/redirect loops) is better expressed as narrative
- Adding `required: true` markers to individual steps — rejected because all steps are already required by default; redundant markers imply unmarked steps are optional
- Strict exact-case matching for classification — rejected because normalize-then-compare is simpler and LLMs naturally vary case
**Reasoning:** Defense-in-depth: each fix operates at multiple layers (agent constraint + orchestrator validation + anti-rationalization rules). Structural fixes (terminal state, step tracking) are the primary enforcement; prompt-level rules are secondary defense.

## D-136: Gate Input Classification — 5-Category Taxonomy

**Date:** 2026-03-24
**Status:** implemented (task-2026-03-24-002)
**Context:** Users provide diverse input at gates — not just menu selections but feedback, questions, instructions, and typos. The orchestrator needs a classification layer to handle all input types.
**Decision:** Classify all gate input into exactly 5 categories: menu selection, feedback-as-selection, question, contextual instruction, ambiguous/typo. Classification is uniform across all gate types using a single gate-aware classifier.
**Alternatives rejected:** Per-gate classifiers (13+ classifiers, unmaintainable). Single classifier without gate awareness (cannot handle variable option lists in selection gates).
**Reasoning:** One classifier to maintain. Gate-aware design requires passing option list to classifier. All non-menu categories route through store-and-reprompt.

## D-137: Gate Routing — Store-and-Reprompt Pattern

**Date:** 2026-03-24
**Status:** implemented (task-2026-03-24-002)
**Context:** When users provide non-menu input at gates, the system must handle it without making implicit gate decisions.
**Decision:** All non-menu input is stored as context and the gate menu is re-presented. Gate decisions result ONLY from explicit menu selection. Re-presentation follows the existing `details` display-only precedent.
**Alternatives rejected:** Classify-then-confirm (Art 2.3 risk — system proposes decision). Auto-classify (violates Art 2.3 directly). Ignore non-menu input (poor UX, discards feedback).
**Reasoning:** Users must always make an explicit menu selection. Feedback and instructions are preserved for the modify flow. No implicit decisions.

## D-138: Gate Recording — Two-Layer (State Content, Telemetry Enums)

**Date:** 2026-03-24
**Status:** implemented (task-2026-03-24-002)
**Context:** Gate input classification and routing events need recording for traceability (Art 3.1) without putting content strings in telemetry (D-027).
**Decision:** Two-layer recording. State (status.yaml) stores full content — input text, feedback, notes. Telemetry (telemetry.yaml) stores only enums (`input_category`) and integers (`reprompt_count`).
**Alternatives rejected:** Single-layer in state only (loses aggregate metrics). Single-layer in telemetry (violates D-027).
**Reasoning:** Two files updated per gate interaction. Telemetry remains aggregatable without content leakage.

## D-139: Gate Re-prompt — Soft Bound of 3

**Date:** 2026-03-24
**Status:** implemented (task-2026-03-24-002)
**Context:** Users might repeatedly provide non-menu input, creating indefinite re-prompt loops. A bound is needed, but forcing a decision would violate Art 4.2 (user authority).
**Decision:** Soft bound of 3 re-prompts. After 3 non-menu inputs, present explicit numbered options. Counter resets on menu selection or `details` display. Bound is soft — user is not forced to select.
**Alternatives rejected:** Hard bound (forces decision, violates Art 4.2). No bound (infinite re-prompt loops). Higher bound (delays helpful guidance).
**Reasoning:** Users receive clear guidance after 3 attempts. No forced decisions. Counter reset prevents accumulation across distinct interaction phases.

## D-140: Feedback Buffer — Accumulated Free-Form Input Enriches Modify Flow

**Date:** 2026-03-24
**Status:** implemented (task-2026-03-24-002)
**Context:** Users often provide feedback at gates before selecting `modify`. This feedback should not be lost — it should inform the modification.
**Decision:** Maintain a transient, in-memory feedback buffer during gate interaction. Feedback-as-selection and contextual instruction inputs are accumulated. When user selects `modify`, buffer contents become the feedback payload. Buffer cleared on: modify dispatch, task completion, explicit user clear.
**Alternatives rejected:** Discard non-menu input (loses valuable context). Immediately trigger modify on feedback (violates Art 2.3). Persist buffer across gates (scope creep, unclear semantics).
**Reasoning:** Modify flow receives richer context. No new gate structures required. Buffer is transient — no persistence complexity.

## D-141: Completion Processor Dispatch Must Be Executable

**Date:** 2026-03-24
**Status:** accepted
**Context:** D-133 created `completion.md` as a dedicated agent to handle finalization + reflection dispatch. But orchestrator Section 7 `done` action only said "Dispatch completion processor (foreground) with task context" — without specifying how: no skill file path, no Agent tool instruction, no Input Contract format. The orchestrator literally could not execute this instruction, so reflection (Mnemosyne) never ran. Additionally, `dispatch.md` Special Dispatch Cases table listed Mnemosyne and Argus but omitted the completion processor.
**Decision:** (a) Section 7 `done` action now has explicit 3-step dispatch: (1) Read `~/.claude/moira/skills/completion.md`, (2) prepend Input Contract values (all 9 fields) to skill content, (3) dispatch via Agent tool (foreground). (b) Completion processor added to `dispatch.md` Special Dispatch Cases table. (c) Orphaned failure handler (`STATUS: failure` block after `Post-Pipeline State` subsection) moved back into `done` action.
**Alternatives rejected:** None — the existing instruction was simply not executable.
**Reasoning:** Every dispatch instruction in the orchestrator must be mechanically executable: specify the source file, how to construct the prompt, and which tool to use. Vague instructions like "dispatch X with Y" are ignored by the LLM under context pressure.

## D-142: Pre-Commit Hook Architecture

**Date:** 2026-03-24
**Status:** accepted
**Context:** Constitution Art 6.3 requires verification before commits. No pre-commit hook existed.
**Decision:** Two-stage deployment: install.sh copies to $MOIRA_HOME/hooks/, moira init copies to .git/hooks/pre-commit. Fail closed on verification failures, fail open on internal errors. Runs on all commits. Source at src/global/hooks/pre-commit.sh.
**Alternatives rejected:** Single-stage install (wrong scope), symlinks (fragile), hook manager (external dependency), Moira-files-only scope (Art 6.3 says "any system change").

## D-143: Log Rotation Strategy

**Date:** 2026-03-24
**Status:** accepted
**Context:** Three log files (violations.log, tool-usage.log, budget-tool-usage.log) grow without limit.
**Decision:** Rotate at task start, 5000-line threshold (configurable), move-then-create pattern, archive to state/archive/. New lib: src/global/lib/log-rotation.sh.
**Alternatives rejected:** Rotate at task end (data may be needed by reflection), size-based trigger (mid-task race conditions), copy+truncate (race condition risk).

## D-144: F-002 (.version File) Resolution

**Date:** 2026-03-24
**Status:** accepted
**Context:** Audit finding F-002 reported .version file missing. Explorer verified src/.version exists with content 0.2.0 and install.sh reads it correctly.
**Decision:** No implementation needed. Finding was inaccurate.

## D-145: Response Contract Normalization Strategy

**Date:** 2026-03-24
**Status:** accepted
**Context:** Response contract text exists in 14 files with textual divergences. Canonical source is response-contract.yaml.
**Decision:** Normalize all copies to match canonical source exactly. Keep duplication as intentional defense-in-depth. Role-specific variants (apollo classifier format, calliope scribe format) are accepted as intentional.
**Alternatives rejected:** Reference-only in role YAMLs (YAML has no native include), remove from role YAMLs entirely (incomplete specs), templatize with sed (over-engineering).

## D-146: Orchestrator Budget Formula — Agent Tokens Decoupling

**Date:** 2026-03-24
**Status:** accepted
**Context:** Orchestrator context budget check summed `total_agent_tokens` (cumulative subagent usage) into the orchestrator context estimate. Subagents run in separate context windows; their tokens do not accumulate in the orchestrator. This caused premature threshold warnings (688k reported vs ~150k actual).
**Decision:** Replace `agent_tokens` in the orchestrator formula with `history_count * _MOIRA_BUDGET_ORCH_PER_AGENT_RETURN` (500 tokens per step). Keep `total_agent_tokens` in state for cost tracking. Add cost visibility line to budget report.
**Alternatives rejected:** Remove agent tracking entirely (still useful for cost), per-message counting (not accessible from bash), fixed overhead increase (doesn't scale with steps).

## D-149: Completion Processor Enforcement — 3-Layer Defense-in-Depth

**Date:** 2026-03-25
**Status:** accepted
**Context:** Despite D-133 (dedicated completion processor) and D-141 (executable dispatch instructions), the orchestrator still skipped completion processor dispatch after final_gate "done" during a decomposition pipeline. Root cause: two independent cleanup paths existed — Section 2 line 177 (general rule: "at completion or abort → delete locks") and Section 7 (specific: dispatch completion processor → then cleanup). Under context pressure in long conversations, the orchestrator followed the simpler Section 2 path, bypassing telemetry, metrics, and reflection.
**Decision:** 3-layer defense-in-depth: (1) Eliminate dual cleanup path — Section 2 now forwards completion to Section 7, keeps only abort cleanup direct; (2) State-based pre-condition — `completion_processor.status` field (required→completed) must be set before cleanup proceeds; completion.sh writes `completed`, orchestrator checks before deleting session lock; (3) Anti-rationalization rules — two new rules targeting the specific "just clean up" and "skip telemetry" thought patterns.
**Alternatives rejected:** Guard.sh post-completion check (violates guard.sh purpose — scope enforcement, not pipeline flow), completion-as-cleanup (violates SRP, creates deadlock risk if processor crashes before cleanup, violates C-01), pure anti-rationalization alone (D-133 proved prompt-only enforcement insufficient), state gate alone without eliminating dual path (ambiguous Section 2 rule still reachable under extreme context pressure).
**Reasoning:** Prompt compliance degrades under context pressure. D-133 and D-141 were necessary but insufficient — they made the dispatch executable but couldn't force the orchestrator to execute it. Structural enforcement (eliminating the competing path + machine-verifiable state pre-condition) does not degrade with context length.

## D-150r: Pre-Planning Agents Use ariadne_context (Alt B Reversal)

**Date:** 2026-03-25
**Status:** accepted (reverses D-150)
**Context:** D-150 decided to keep raw L0 views for pre-planning. User selected Alt B for full efficiency.
**Decision:** Pre-planning agents use `ariadne_context` (budget_tokens: 1000, task: "understand") with L0 view fallback.
**Alternatives rejected:** (a) Keep L0 views only (Alt A) — user wants full integration.
**Reasoning:** `ariadne_context` provides task-aware, relevance-ranked context that is more useful than static L0 views. Fallback ensures zero regression risk.

## D-151r: Analytical Baseline References Phase 4/5 Tools (Alt B Reversal)

**Date:** 2026-03-25
**Status:** accepted (reverses D-151)
**Context:** D-151 decided to keep CLI baseline as-is. User selected Alt B.
**Decision:** `moira_graph_analytical_baseline()` updated to inform agents about available Phase 4/5 MCP tools. CLI baseline queries unchanged (MCP unavailable in shell context).
**Reasoning:** Shell function cannot call MCP, but can document available tools for agents.

## D-153: Phase 4/5 Ariadne Tools as Infrastructure MCP

**Date:** 2026-03-25
**Status:** accepted
**Context:** 9 new tools from Ariadne Phases 4 (symbols) and 5 (context engine).
**Decision:** All 9 tools registered as infrastructure MCP (D-108 criteria met).
**Reasoning:** Read-only, zero external risk, near-zero token cost, Moira-essential, always appropriate.

## D-154: Knowledge Access Matrix Symbol Extras

**Date:** 2026-03-25
**Status:** accepted
**Context:** Phase 4 adds symbol-level data accessible via MCP tools.
**Decision:** Document symbol access levels as extras in knowledge-access-matrix.yaml comments.
**Reasoning:** Symbol access is mediated through MCP tools, not knowledge files. Follows existing extras pattern.

## D-155: Dispatch ariadne_context Integration

**Date:** 2026-03-25
**Status:** accepted
**Context:** Alt B requires dispatch step 4b to use ariadne_context for pre-planning agents.
**Decision:** Step 4b calls ariadne_context with budget_tokens: 1000, task: "understand". Falls back to L0 view on failure.
**Reasoning:** Provides task-relevant context to pre-planning agents instead of generic project overview.

## D-156: Plan Mode Override Resistance (Layer 3 Defense)

**Date:** 2026-03-25
**Status:** accepted
**Context:** When Claude Code's plan mode activates during an active Moira pipeline, it injects a system-reminder containing behavioral restrictions ("MUST NOT make any edits", "READ-ONLY actions"). This externally injected directive conflicts with the orchestrator's pipeline execution directives, causing the orchestrator to abandon pipeline execution and write plan files instead.
**Decision:** Add plan mode override resistance at two prompt injection points: (1) `src/global/skills/orchestrator.md` Section 1 — primary defense with pattern-based recognition, priority declaration, and scope limiter; (2) `.claude/CLAUDE.md` — secondary reinforcement within moira markers. Defense uses pattern-based recognition (not exact string matching) and explicit priority hierarchy: user gates > pipeline directives > external behavioral restrictions. Document threat in `design/subsystems/self-monitoring.md` as an Environmental Interference Pattern.
**Alternatives rejected:**
- Guard.sh modification — plan mode failure is omission (not dispatching), not commission; guard.sh fires on tool calls so cannot detect inaction.
- Single defense point — CLAUDE.md loads before skill, provides baseline defense for EC-1 (plan mode before pipeline start).
- Blanket "ignore all system-reminders" — would cause orchestrator to miss legitimate tool availability updates.
**Reasoning:** The defense must be present at every point where the orchestrator processes instructions. There are exactly two such points: CLAUDE.md and the orchestrator skill. Both already contain anti-rationalization language. Pattern-based recognition is resilient to wording changes while remaining specific enough to avoid false positives. This is a Layer 3 (behavioral) defense — the limitation that it cannot structurally prevent system-reminder injection is acknowledged.

## D-157: Phase 6 Annotation/Bookmark Tools — Infrastructure with Role-Level Write Restriction

**Date:** 2026-03-26
**Status:** accepted
**Context:** Phase 6 adds 6 tools including write operations (annotate, bookmark) to `.ariadne/` files. D-108 infrastructure criteria require read-only, but these writes are to Ariadne's own metadata (not project files), have zero external API risk, near-zero cost.
**Decision:** Classify all Phase 6 tools as infrastructure MCP, extending D-108. Restrict write tool usage via agent role definitions: only Mnemosyne may call `ariadne_annotate`, only Daedalus may call `ariadne_bookmark`. READ tools unrestricted.
**Alternatives rejected:**
- Classify writes as external MCP requiring Daedalus authorization — adds ceremony for zero-risk writes
- Split Phase 6 into infrastructure (reads) and managed (writes) — complicates registry
**Reasoning:** The D-108 "read-only" criterion targets external side-effects. Annotation/bookmark writes are local, deterministic, reversible, confined to `.ariadne/`. Role-level restriction provides sufficient control.

## D-158: MCP Resources/Prompts — Document Availability, Defer Integration

**Date:** 2026-03-26
**Status:** superseded by D-162, D-163
**Context:** Phase 6 adds 6 MCP resources and 4 MCP prompts. Original decision incorrectly assumed Claude Code may not support MCP resource subscriptions.
**Decision:** ~~Document only, defer integration.~~ **Superseded:** Claude Code fully supports MCP resources via `@server:protocol://path` syntax and MCP prompts via `get_prompt` RPC. See D-162 (resources) and D-163 (prompts) for replacement decisions.
**Post-mortem:** The premise "Claude Code's MCP client may not fully support resource subscriptions" was fabricated by the architect agent without verification. This violated INV-001 (never fabricate). Detected during post-task audit.

## D-159: Temporal Availability — Derived from ariadne_overview at Bootstrap

**Date:** 2026-03-26
**Status:** accepted
**Context:** Moira needs to know if temporal data is available to condition agent guidance and status output.
**Decision:** Add `temporal_available` boolean in `current.schema.yaml`. Set during orchestrator bootstrap: if `graph_available` is true, query `ariadne_overview` — if response contains `temporal` field, set true. One-time check at task start.
**Alternatives rejected:**
- Derive at each usage point — N+1 queries, wastes budget
- Always assume available when graph available — incorrect for non-git projects
- Shell-level git check in graph.sh — duplicates Ariadne's detection logic
**Reasoning:** Single-point detection keeps flag consistent. Using `ariadne_overview` delegates detection to Ariadne's own logic.

## D-160: Bookmark Lifecycle — Completion Processor Cleanup

**Date:** 2026-03-26
**Status:** accepted
**Context:** Daedalus creates task-scoped bookmarks during planning that should be cleaned up at task completion.
**Decision:** Completion processor responsible for cleanup. Calls `ariadne_remove_bookmark` for bookmarks with task ID prefix. Naming convention: `task-{task_id}-{name}`. Cleanup failure logs warning, does not block completion.
**Alternatives rejected:**
- No cleanup — degrades UX over time
- Guard.sh enforcement — wrong mechanism (monitors tool calls, not MCP state)
- TTL-based expiry — requires Ariadne-side changes
**Reasoning:** Completion processor already handles end-of-task housekeeping (D-133, D-149). Task-ID prefixed names make cleanup deterministic and safe.

## D-161: Phase 7 Temporal Tools — Infrastructure Classification

**Date:** 2026-03-26
**Status:** accepted
**Context:** Phase 7 adds 5 read-only temporal analysis tools.
**Decision:** Classify all 5 as infrastructure MCP, extending D-153. Meet all D-108 criteria: read-only, zero external risk, near-zero token cost.
**Reasoning:** Same rationale as D-108/D-153. Temporal tools query local git history processed by Ariadne.

## D-162: MCP Resources Integration — Active Use in Agent Dispatch

**Date:** 2026-03-26
**Status:** accepted
**Supersedes:** D-158 (resources portion)
**Context:** Claude Code supports MCP resources via `@server:protocol://path` syntax. Resources are automatically fetched and included as attachments when referenced. Ariadne provides 6 resources: ariadne://overview, ariadne://file/{path}, ariadne://cluster/{name}, ariadne://smells, ariadne://hotspots, ariadne://freshness.
**Decision:** Integrate Ariadne MCP resources into agent dispatch. Resources provide zero-cost context injection — they are declarative data subscriptions, not tool calls. Include resource references in agent prompts where appropriate: ariadne://overview for bootstrap context, ariadne://smells for review context, ariadne://freshness for staleness checks. Resources complement (not replace) tool calls — tools provide on-demand queries, resources provide ambient context.
**Alternatives rejected:**
- Continue deferring — wastes available capability based on false premise
- Replace all tool calls with resources — resources are read-only snapshots, tools provide parameterized queries
**Reasoning:** Resources are free, always-current context that agents can reference without consuming tool call budget. Claude Code's `@` syntax makes them trivially accessible.

## D-163: MCP Prompts Integration — Available for Agent Workflows

**Date:** 2026-03-26
**Status:** accepted
**Supersedes:** D-158 (prompts portion)
**Context:** MCP prompts are server-side templates callable via `get_prompt` RPC method. Ariadne provides 4 prompts: explore-area (path), review-impact (paths), find-refactoring (scope?), understand-module (module). Each returns structured context combining graph data with analysis guidance.
**Decision:** Document MCP prompts as available workflow accelerators. Prompts are callable through the MCP protocol and can be used by agents that have MCP access. Primary use cases: Hermes can use `explore-area` for structured exploration, Themis can use `review-impact` for change analysis, Metis can use `find-refactoring` for architectural assessment. Prompts are not registered in mcp-registry.yaml (they are a separate MCP primitive, not tools).
**Alternatives rejected:**
- Register prompts as tools — conflates MCP primitives, prompts have different invocation semantics
- Ignore prompts — wastes available capability
**Reasoning:** Prompts provide pre-built, graph-enriched analysis templates that save agent tokens compared to manual tool-call sequences.

## D-164: Pre-Architecture Documentation Fetch

**Date:** 2026-03-26
**Status:** Accepted
**Context:** D-158 — Metis fabricated claims about Claude Code MCP capabilities because it had no documentation. INV-001 existed but was violated.
**Decision:** Modify dispatch system to add step 4f — scan upstream artifacts for external system references, fetch documentation via Context7 MCP, inject into Metis prompt with closed-world constraint. Max 3 systems, 3-15k tokens each.
**Alternatives rejected:**
- Separate verification agent (too expensive)
- Metis calls Context7 directly (agent doesn't know what it doesn't know)
- User flags external systems (shifts responsibility)
**Reasoning:** Primary structural fix. Agent fabricated because it lacked data. Injecting documentation at dispatch time provides facts before reasoning begins.

## D-165: Closed-World Constraint for External Claims

**Date:** 2026-03-26
**Status:** Accepted
**Context:** No boundary between facts the agent knows and facts it generates.
**Decision:** Add never rule to metis.yaml: can only make claims about external systems whose documentation is in ## External Documentation section. Also add documentation grounding capability.
**Alternatives rejected:**
- Add to base.yaml (only Metis makes these claims)
- Soft guidance (failed in D-158)
**Reasoning:** Checkable invariant — D-166 can verify whether documentation was cited, not just whether the agent was told to be honest.

## D-166: Deterministic Post-Architecture Checks

**Date:** 2026-03-26
**Status:** Accepted
**Context:** Prompt rules alone cannot prevent fabrication (D-158). LLM-based verification shares the same failure mode.
**Decision:** Add deterministic pattern-matching checks to orchestrator gate protocol: hedge phrase detection, closed-world violation detection, missing epistemic section detection. Zero LLM tokens.
**Alternatives rejected:**
- LLM evaluation (same blindness)
- Rely on Themis (too late — runs after implementation)
- Hedge phrases only (misses confident false claims)
**Reasoning:** Pattern matching cannot be persuaded by fluent text. Checks structural properties, not truth claims.

## D-167: Conditional Escalation at Architecture Gate

**Date:** 2026-03-26
**Status:** Accepted
**Context:** D-166 produces flags. System needs response protocol balancing safety and usability.
**Decision:** WARNING flags (hedge, missing section) shown as advisory. BLOCK flags (closed-world violation) trigger automatic documentation fetch + Metis re-dispatch before presenting gate. Fallback: convert to WARNING if fetch fails.
**Alternatives rejected:**
- Always block (too strict)
- Never block (defeats purpose)
- Block without fetch (wastes user time)
**Reasoning:** Cost scales with severity. Clean architectures: zero overhead. Ungrounded: automatic remediation.

## D-168: Root Cause to Mechanism Mapping Table

**Date:** 2026-03-26
**Status:** Accepted
**Context:** First architecture version proposed prompt rules to fix prompt rule failure. No mechanism to type-check solution fit.
**Decision:** Required architecture section for failure-driven tasks. Table with: Root Cause, Mechanism, Decision, Mechanism Type (structural/deterministic/prompt/visual), Why It Works.
**Alternatives rejected:**
- Require for all tasks (overhead for feature work)
- Have Themis check instead (value is in forcing architect to think)
**Reasoning:** Makes logical contradictions visible. "Root cause: prompts fail / Mechanism: prompt" is self-evidently wrong.

## D-169: Pre-Mortem Section

**Date:** 2026-03-26
**Status:** Accepted
**Context:** First architecture self-assessed Q2=pass with 0 critical findings without questioning effectiveness.
**Decision:** Required architecture section for ALL tasks: how could this fail, what assumptions could be wrong, failure modes, conditions for ineffectiveness.
**Alternatives rejected:**
- Make optional (skipped when most needed)
- Separate agent (adds complexity)
**Reasoning:** LLMs are poor at spontaneous self-critique but good at structured adversarial analysis when prompted.

## D-170: Effectiveness Simulation at Architecture Gate

**Date:** 2026-03-26
**Status:** Accepted
**Context:** When architecture addresses a known incident, system should replay that incident against proposed solution.
**Decision:** Orchestrator performs lightweight check before architecture gate (only for incident-driven tasks). Reads Root Cause → Mechanism Mapping, checks mechanism types against root cause types. Produces PREVENTS/PARTIALLY_PREVENTS/DOES_NOT_PREVENT per mechanism.
**Alternatives rejected:**
- Full agent-dispatch replay (too expensive)
- Skip for non-incident tasks (this IS the decision)
**Reasoning:** Catches meta-failure of proposing solutions that wouldn't solve the problem they address.

## D-171: Themis Epistemic Integrity Review

**Date:** 2026-03-26
**Status:** Accepted
**Context:** Themis checks conformance but not premises. Secondary defense — D-164/D-166 are primary.
**Decision:** Add epistemic_integrity section to q4-correctness.yaml (Q4-E01 through Q4-E05). Add epistemic integrity entry to themis.yaml upstream_verification.
**Alternatives rejected:**
- Themis as primary defense (runs too late)
- Separate epistemic agent (unnecessary complexity)
**Reasoning:** Defense-in-depth. Catches what primary mechanisms miss.

## D-172: Gate Epistemic Flags

**Date:** 2026-03-26
**Status:** Accepted
**Context:** Gates present all claims uniformly. User cannot distinguish verified from assumed.
**Decision:** Add EPISTEMIC FLAGS section to architecture gate (between details and health report) when flags exist. Plan gate inherits unresolved flags. Max 5 displayed.
**Alternatives rejected:**
- Full epistemic section in gate (too verbose)
- No gate display (defeats gate purpose)
**Reasoning:** Makes epistemic quality visible at the decision point.

## D-173: Verified Facts in Knowledge Base

**Date:** 2026-03-26
**Status:** Accepted
**Context:** Verified claims should be cached for future tasks to avoid re-fetching.
**Decision:** Add verified_facts subcategory under libraries knowledge type. Entry format: claim, verified_date, evidence_source, task_id, expiry_hint. Subject to E8-STALE detection.
**Alternatives rejected:**
- New top-level knowledge type (ORANGE risk)
- Store in decision log (wrong concept)
**Reasoning:** Reduces cost of D-164 pre-fetch over time. First verification costs one Context7 call; subsequent tasks get it free.

## D-175: Pipeline Compliance Hooks — Deterministic Step Enforcement

**Date:** 2026-03-27
**Status:** Accepted
**Context:** Orchestrator at 15% context usage skipped sub-pipeline execution for decomposition pipeline — dispatched Hephaestus directly for each sub-task without Themis (reviewer) or Aletheia (tester). Anti-rationalization rules and orchestrator skill instructions failed to prevent this. Root cause: LLM non-compliance with procedures, not context exhaustion or forgetfulness.
**Decision:** Add three deterministic hooks that enforce pipeline step ordering:
- `pipeline-compliance.sh` (PreToolUse, Agent): DENY wrong agent dispatches. Enforces review-after-implementation, test-after-review, classifier-first-in-decomposition.
- `pipeline-tracker.sh` (PostToolUse, Agent): Tracks dispatch sequence in `pipeline-tracker.state`, injects next-step guidance via `additionalContext`.
- `pipeline-stop-guard.sh` (Stop): Blocks pipeline completion while review or testing is pending.
Hooks are installed automatically via `install.sh` and `settings-merge.sh`. No user configuration required.
**Alternatives rejected:**
- Prompt-based enforcement (anti-rationalization rules) — already proven insufficient at 15% context
- Per-step procedure loading — addresses forgetting, not compliance
- Inlining all instructions in skill file — same problem (LLM may ignore inline instructions too)
- Agent-based hooks (type: "agent") — too slow, unnecessary complexity for deterministic checks
**Reasoning:** Only code executing outside the LLM provides structural guarantees. Shell hooks fire deterministically on every tool call and cannot be "rationalized away" by the LLM. Defense-in-depth: Layer 1 (prompt) tells the LLM what to do, Layer 4 (hooks) blocks it from doing the wrong thing.

## D-176: Extended Hook Suite — Full Lifecycle Enforcement

**Date:** 2026-03-29
**Status:** Accepted
**Context:** D-175 hooks cover pipeline step ordering. Analysis of remaining failure modes reveals additional gaps: boundary violation prevention (guard.sh is detection-only), context loss after compaction, agent prompt quality, and agent output format compliance.
**Decision:** Extend the hook suite with 4 additional hooks + upgrade compliance/tracker to full transition tables:
- `guard-prevent.sh` (PreToolUse, Read|Write): DENY orchestrator access to project files. Upgrades guard.sh from detection to prevention.
- `compact-reinject.sh` (SessionStart, compact): Re-injects pipeline state after context compaction.
- `agent-inject.sh` (SubagentStart): Injects response contract and inviolable rules into every subagent.
- `agent-output-validate.sh` (SubagentStop): BLOCK agents that don't produce STATUS line in output.
- `pipeline-compliance.sh` upgraded: full per-pipeline transition tables (quick/standard/full/decomposition/analytical).
- `pipeline-tracker.sh` upgraded: subtask_mode tracking, architect/planner reset review/test pending.
Total: 9 hooks across 6 event types (PreToolUse, PostToolUse, Stop, SessionStart, SubagentStart, SubagentStop).
**Alternatives rejected:**
- MCP Channels for monitoring (overkill — hooks are simpler and synchronous)
- CronCreate for periodic self-checks (prompt-based, not structural)
- Skill frontmatter hooks (cleaner scoping but requires refactoring install process — deferred)
**Reasoning:** Each hook addresses a specific failure mode with the minimum mechanism that provides structural guarantees. Guard-prevent closes the last detection-only gap. Compact-reinject prevents drift after compaction. Agent-inject ensures minimum prompt quality. Agent-output-validate enforces response contract.

## D-177: Orchestrator Context — Real Token Usage from Transcript

**Date:** 2026-03-29
**Status:** accepted
**Context:** Moira's orchestrator context percentage diverged from the Claude Code statusline (~50% reported vs ~7-15% actual). Root cause: the orchestrator LLM used `total_agent_tokens` (cumulative subagent cost metric) as context usage instead of `orchestrator_percent` computed by the proxy formula. D-146 decoupled agent tokens from the formula, but the behavioral bug persisted. Additionally, the proxy formula (D-058) gives ~3% for typical pipelines — also inaccurate, just in the other direction.
**Decision:** Read real context usage from the session transcript JSONL. The `budget-track.sh` PostToolUse hook receives `transcript_path`, extracts `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` from the last assistant message, and writes to `context-actual-tokens.txt`. `moira_budget_orchestrator_check()` reads this file first, falls back to the D-058 proxy formula when no transcript data is available. Orchestrator prompt updated to explicitly use script-computed `orchestrator_percent`, never self-compute from `total_agent_tokens`.
**Alternatives rejected:**
- Recalibrate proxy formula constants — still an approximation, can't match statusline across varying workloads
- Remove context tracking entirely — loses checkpoint/warning functionality
- Parse transcript in budget.sh directly — budget.sh doesn't have transcript path, hooks do
**Reasoning:** The transcript already contains the exact same API usage data that the statusline displays. Extracting it via the existing PostToolUse hook is minimal additional work and gives ground-truth values instead of estimates.

## D-178: State Management Automation — Hook-Driven State Writes

**Date:** 2026-03-29
**Status:** accepted
**Context:** The orchestrator spends ~12-18k tokens per pipeline on mechanical YAML Read/Write operations for state management. Shell libraries (state.sh, budget.sh) define canonical state logic, but the orchestrator cannot call them (Bash is not an allowed tool — Art 1.1). Instead, it reads .sh files as reference and reproduces the same logic via Read/Write — a fragile, error-prone, context-expensive pattern.
**Decision:** Move mechanical state operations into Claude Code hooks that fire automatically:
- `task-submit.sh` (UserPromptSubmit): detects `/moira:task` prefix, scaffolds task directory and all initial state files (manifest.yaml, status.yaml, input.md, current.yaml, session-lock, guard-active) via `task-init.sh` shell library. Injects task_id into orchestrator context.
- `pipeline-dispatch.sh` (PreToolUse:Agent): replaces `pipeline-compliance.sh` — validates step transitions (L1/L2/L3 as before) AND auto-writes step/step_status to current.yaml via state.sh. Writes `dispatched_role` to tracker state for agent-done.sh.
- `agent-done.sh` (SubagentStop): reads dispatched_role from tracker, extracts STATUS/SUMMARY from agent output, records completion in current.yaml history and budget via `moira_state_agent_done()`. Injects budget state (orchestrator_percent, warning_level) as additionalContext.
- `session-cleanup.sh` (SessionEnd): cleans up session-lock, guard-active, pipeline-tracker.state on completed/checkpointed exit. Marks lock as stale on abnormal exit.
Gate recording stays manual — no hookable event for user gate decisions. Open question resolution: SubagentStop fires before PostToolUse(Agent), so pipeline-dispatch.sh writes `dispatched_role` in PreToolUse for agent-done.sh to read in SubagentStop. pipeline-compliance.sh merged into pipeline-dispatch.sh to avoid two PreToolUse(Agent) processes.
**Prerequisites fixed:** Two latent bugs in `moira_yaml_block_append` — AWK `-v` newline limitation (replaced with ENVIRON) and `[]` not replaced before append (added sed pre-processing). Both were latent (no runtime caller used block_append) but blocked the automation work.
**Alternatives rejected:**
- Prompt-based hooks (type: "prompt") for state decisions — state writes are deterministic, not judgmental
- MCP server for state management — overkill; hooks are simpler and synchronous
- Keep all state manual — wastes ~12k tokens/pipeline on mechanical bookkeeping
**Reasoning:** Hooks provide structural guarantees that prompts cannot. State transitions always happen correctly regardless of orchestrator context quality. Saves ~12k tokens per pipeline (~25% of a quick pipeline budget). The orchestrator focuses on decisions (gates, errors, routing) while hooks handle bookkeeping.

## D-179: Permission Auto-Registration for Subagent Access

**Date:** 2026-03-29
**Status:** accepted
**Context:** Background subagents (launched via `run_in_background: true` in refresh/init) silently failed when writing scan results to `.moira/` or reading role files from `~/.claude/moira/`. Permission prompts cannot be displayed for background agents, causing silent denials. Additionally, `settings-merge.sh` was out of sync with the actual hook set — missing 6 hooks and referencing non-existent `pipeline-compliance.sh`.
**Decision:**
- **Project-level permissions** (`settings-merge.sh` → `.claude/settings.json`): auto-inject `Read(/.moira/**)`, `Write(/.moira/**)`, `Edit(/.moira/**)` using correct `Tool(specifier)` format with `/` prefix (project-root-relative, not CWD-relative).
- **Global permissions** (`moira_settings_register_global_permissions()` → `~/.claude/settings.json`): auto-inject `Read(~/.claude/moira/**)` so subagents can read role definitions, templates, pipelines from the global install.
- **Full hook sync**: `settings-merge.sh` now injects all 13 hooks across 9 event types, matching the actual hook set. Removed stale `pipeline-compliance.sh` reference (merged into `pipeline-dispatch.sh` per D-178).
- **No Bash permission**: `Bash(bash ~/.claude/moira/**)` was removed — real commands use `bash -c 'source ~/.claude/moira/...'` which doesn't match that pattern.
**Alternatives rejected:**
- Running scanner agents in foreground (sequential) — slower, defeats parallelism
- Adding permissions only to Moira repo — consumers would hit the same issue
**Reasoning:** Permissions are structural (like hooks) — they must be injected automatically at install time, not rely on users configuring them manually. Two-layer approach (project + global) mirrors the two-layer file architecture (project-local state + global install).

## D-180: Standalone CLI for Read-Only Commands

**Date:** 2026-03-29
**Status:** Accepted
**Context:** Six Moira commands (`status`, `help`, `knowledge`, `metrics`, `graph`, `health`) are fully mechanical — they read YAML files, call ariadne CLI, and format output. Invoking them via `/moira:<cmd>` wastes LLM tokens and adds latency for what is essentially shell scripting.
**Decision:** Create a standalone shell CLI at `src/cli/moira` (installed to `~/.claude/moira/bin/moira`, symlinked to `~/.local/bin/moira`). The CLI sources existing libraries from `~/.claude/moira/lib/` and provides instant, LLM-free access to read-only commands. LLM-requiring commands (`task`, `init`, `audit`, `resume`, `bypass`, `refresh`, `bench`) remain as `/moira:<cmd>` skills.
**Alternatives rejected:**
- Replace skill files with CLI — would break existing `/moira:<cmd>` UX for users who prefer Claude Code integration
- Separate binary per command — unnecessary fragmentation, harder to maintain
- Node.js/Python CLI — adds runtime dependency, Moira's principle is bash-only
**Reasoning:** The CLI reuses 100% of existing shell libraries (yaml-utils, knowledge, metrics, graph). No code duplication. Users get sub-second response for status checks instead of waiting for LLM. The skill files remain for backward compatibility and for users who prefer the integrated experience.

## D-181: Per-Subtask State Isolation in Pipeline Tracker

**Date:** 2026-03-30
**Status:** accepted
**Context:** The pipeline tracker used a single global state file (`pipeline-tracker.state`) with one set of `last_role`, `review_pending`, `test_pending` flags. In decomposition pipelines with sequential (or parallel) sub-tasks, one sub-task's `review_pending=true` would block unrelated dispatches for another sub-task. E5-QUALITY retry paths (`reviewer �� implementer`) were also blocked across all 4 non-analytical pipelines because the Layer 3 transition tables didn't include implementer as a valid successor to reviewer/tester.
**Decision:**
- **Per-subtask state files**: When `subtask_mode=true`, each sub-task gets `pipeline-tracker-sub-{N}.state` for `last_role`, `review_pending`, `test_pending`. Global tracker retains pipeline-level fields (`pipeline`, `subtask_mode`, `subtask_counter`, `current_subtask`).
- **E5-QUALITY transitions**: `reviewer → implementer` added to quick, standard, full, decomposition_sub transition tables. `tester → implementer` added to standard.
- **Guard-prevent Edit coverage**: Added `Edit` to PreToolUse matcher (was only `Read|Write`), closing a boundary enforcement gap.
- **TERMINAL sentinel**: Explicit terminal states use `valid="TERMINAL"` (deny all) vs `valid=""` (no rule = allow).
**Alternatives rejected:**
- Sections in one file — race conditions on concurrent write, complex parsing
- Relax Layer 1/2 for decomposition — trades enforcement correctness for simplicity
**Reasoning:** Per-subtask files are atomic (one writer per file), use the same `grep/cut` parsing as existing code, and scale to arbitrary subtask counts. The approach adds ~20 lines to each hook without architectural changes.

## D-183: Subagent Bypass in Guard Hooks via agent_id

**Date:** 2026-03-30
**Status:** accepted
**Context:** Dispatched subagents (Hermes, Hephaestus, Themis, etc.) read CLAUDE.md at startup and see the "Orchestrator Boundaries" section which says "NEVER read project files". Some agents started applying these restrictions to themselves, refusing to Read/Edit project files — even though the rules are meant only for the orchestrator. Additionally, `guard-prevent.sh` (PreToolUse) and `guard.sh` (PostToolUse) were blocking/logging violations for subagent file operations, producing false positives. The problem was intermittent: agents sometimes "obeyed" the orchestrator rules and sometimes didn't, depending on how strongly the LLM weighted the CLAUDE.md instructions vs the agent prompt.
**Decision:**
- **Hook-level bypass**: `guard-prevent.sh` and `guard.sh` now check the `agent_id` field in hook input JSON. This field is present only in subagent contexts (set by Claude Code harness). When `agent_id` is non-empty, the hook exits immediately (exit 0), allowing subagents to freely access project files. This is structural — cannot be rationalized away by the LLM.
- **Agent role injection**: `agent-inject.sh` (SubagentStart) now includes an `AGENT ROLE` line explicitly stating the agent is NOT the orchestrator and MUST use Read/Edit/Write/Grep/Glob/Bash on project files. This counters CLAUDE.md instructions at the prompt level.
- **CLAUDE.md scope marker**: Added explicit scope declaration to the Orchestrator Boundaries section: "If you are a dispatched agent, IGNORE this entire section." Defense-in-depth at the prompt layer.
- **Dispatch template**: Added `## Agent Role Clarification` section to the dispatch prompt template and pre-assembled instruction file prepend path.
**Alternatives rejected:**
- Prompt-only fix (CLAUDE.md + dispatch template) — doesn't guarantee compliance per D-174 (feedback: prompt rules don't guarantee compliance)
- Removing orchestrator boundaries from CLAUDE.md entirely — would weaken orchestrator enforcement
- Separate CLAUDE.md for subagents — Claude Code doesn't support per-agent CLAUDE.md
**Reasoning:** Three-layer defense: (1) hook-level `agent_id` bypass is structural and deterministic, (2) `agent-inject.sh` role clarification reinforces at prompt level, (3) CLAUDE.md scope marker provides guidance if agent reads it. The hook layer is the primary enforcement; prompt layers are defense-in-depth.

## D-184: Gate Output Contracts with Mechanical Enforcement

**Date:** 2026-03-31
**Status:** Accepted
**Context:** Gates are passive summaries — agent does work, gate shows "Summary + Key points + Impact", user approves. This creates three problems: (1) agents optimize for "pass pipeline" not "solve problem well" — minimum viable output that fills the template, (2) users can't make informed decisions because gates don't present alternatives, trade-offs, or uncertainty, (3) no cross-gate traceability — scope defined at classification is never mechanically checked at plan or final, allowing silent scope drift. Additionally, epistemic enforcement (D-165, D-172) only covers architecture gate — fabrication at plan or implementation steps goes undetected until review.
**Decision:** Three-layer enforcement system:

**Layer 1 — Output contracts (per-role required artifact sections):**
- Apollo: `## Problem Statement`, `## Scope` (In/Out), `## Acceptance Criteria` (mechanical, testable)
- Metis: `## Alternatives` (min 2 with trade-offs, for ALL pipelines not just Full), `## Recommendation` (with reasoning), `## Assumptions` (Verified/Unverified/Load-bearing subsections), `## Verification Plan`
- Daedalus: `## Scope Check` (vs classification — Added/Removed with justification), `## Acceptance Test` (from classification criteria), `## Risks` (blocking risks with plan B), `## Unverified Dependencies` (conditional — required when architecture has UNVERIFIED items)
- Final gate (orchestrator-assembled): `## Acceptance Results` (per-criterion pass/fail + evidence), `## Scope Delivery` (delivered vs deferred), `## Deferred Items` (each justified), `## Epistemic Status` (UNVERIFIED resolution chain)

**Layer 2 — Mechanical validation hook (`artifact-validate.sh`, SubagentStop):**
- Parses role from agent description, reads artifact file from ARTIFACTS line
- Per-role lookup table of required section headers
- `grep` for `^## Section Name` — mechanical, not LLM judgment
- Missing sections → `decision: "block"` with specific feedback listing missing sections
- Structural checks: `## Alternatives` must contain ≥2 `### Alternative` subsections; `## Assumptions` must contain `### Unverified` (even if empty — explicit "nothing unverified")
- Conditional checks: `## Unverified Dependencies` required in Daedalus artifact only when Metis artifact contains "UNVERIFIED"

**Layer 3 — Cross-gate context injection (extends `agent-inject.sh`):**
- At SubagentStart, hook reads previous gate artifacts and injects focused traceability context as `additionalContext`
- Injection map: Metis receives classification scope + acceptance criteria; Daedalus receives classification scope + criteria + architecture recommendation + assumptions; Hephaestus receives acceptance criteria + UNVERIFIED list; Themis receives acceptance criteria + full UNVERIFIED list for verification audit
- Injected as `## TRACEABILITY CONTEXT (system-injected)` — targeted extraction of key fields, not full artifact dump
- UNVERIFIED claims propagate through entire pipeline: architecture → plan (must address each) → implementation (must verify or mark) → review (must audit) → final gate (resolution status)

**Alternatives rejected:**
- Prompt-only enforcement (tell agents to write better artifacts) — proven insufficient (D-175: prompts don't guarantee compliance)
- LLM-based validation (dispatch reviewer to check artifact quality) — expensive, unreliable, adds latency
- Template-filling approach (agents fill structured YAML) — too rigid, inhibits natural reasoning; section headers are the right granularity
- Epistemic enforcement only at architecture gate — leaves plan/implementation/final unprotected against fabrication
**Reasoning:** Required sections are the minimum granularity that forces real thinking without being so rigid that agents game the template. Grep-based validation is zero-cost and deterministic. Context injection makes traceability structural — agents can't ignore scope/criteria when they're injected into their context. The UNVERIFIED propagation chain extends D-165/D-172 epistemic enforcement from architecture-only to full pipeline coverage. Each layer reinforces the others: contracts define what's needed, hooks enforce it exists, injection ensures agents have the data to fill it honestly.

## D-185: Craftsmanship Identity — Quality Ownership by Agents

**Date:** 2026-03-31
**Status:** Accepted
**Context:** Agent prompts are constraint-heavy (34 NEVER rules across all agents) but quality-light. Agents have detailed instructions on what NOT to do, but minimal guidance on what GOOD work looks like. This creates checkbox mentality: agents produce minimum viable output that satisfies constraints and passes checklists, then exit. Hephaestus's identity is "implement EXACTLY what the plan specifies — no more, no less" — the identity of a bureaucrat, not a craftsman. The implementer has `quality_checklist: null`. Themis checks correctness but has no mechanism to distinguish "correct but mediocre" from "correct and well-crafted". KISS (Q4-S03) and YAGNI (Q4-S04) exist without counterbalance — they're interpreted as license for minimal effort rather than discipline against scope creep.
**Decision:** Three changes:

**1. Quality stance in agent identity (all executing agents):**
Each agent gets a `quality_stance` section in its role definition that defines what quality means for THAT role. Not a checklist — a mindset directive. Scope remains controlled by plan; quality is owned by the agent.

- Hermes: "Thoroughness — report the full picture, not just the first matches. A context report that misses key files wastes downstream budget."
- Athena: "Precision — requirements that leave ambiguity create implementation guesswork. Every criterion must be mechanically testable."
- Metis: "Seek the best solution, not the first valid one. Alternatives exist to be genuinely evaluated, not to fill a template. Pre-mortem must find real weaknesses."
- Daedalus: "A plan that enables quality implementation — include context that helps Hephaestus write better code, not just correct code."
- Hephaestus: "You own the quality of HOW code is written. The plan controls WHAT you build; you control the craftsmanship — clarity, efficiency, maintainability. Code should be good enough that you wouldn't need to explain it with comments."
- Themis: "Distinguish adequate from excellent. Correct code that is poorly structured, hard to read, or fragile is a WARNING, not a pass."
- Aletheia: "Tests that only verify happy path are incomplete. Tests that test implementation details are brittle. Find the balance."

**2. Craftsmanship section in Q4 checklist (Themis):**
New `craftsmanship` section in q4-correctness.yaml:
- Q4-F01: "Solution approach is appropriate for the problem complexity — not over-engineered, not under-engineered" (required)
- Q4-F02: "Code is readable without requiring comments to explain intent — clear naming, linear flow, small functions" (required)
- Q4-F03: "Error handling is meaningful — errors are specific, actionable, and propagated appropriately, not swallowed or generically caught" (required)
- Q4-F04: "No unnecessary complexity — no premature abstractions, no wrapper functions that add no value, no indirection without purpose" (required)

Severity: WARNING (not CRITICAL). These don't block the pipeline but are reported and tracked.

**3. Reframe Hephaestus identity:**
Change from "implement EXACTLY what the plan specifies — no more, no less" to "implement the plan faithfully with craftsmanship. The plan defines WHAT to build; you own HOW it's built — code clarity, efficiency, and maintainability. Do not add scope beyond the plan, but within scope, write code you'd be proud of."

**Alternatives rejected:**
- Quality checklist only (no identity change) — checklists are checkboxes; LLMs can pass them without changing behavior
- Detailed quality rubrics with scoring — too rigid, creates gaming behavior
- Separate quality review agent — adds pipeline latency and budget; Themis already reviews
- Remove YAGNI/KISS — wrong direction; they're correct principles, they just need counterbalance
**Reasoning:** LLM agents optimize for what the prompt emphasizes. Currently prompts emphasize constraints (NEVER) and compliance (checklists). Adding quality stance to identity shifts the optimization target. The dual approach (identity for motivation + checklist for verification) mirrors how human teams work: craftsman culture + code review standards. Scope discipline (YAGNI) and quality (craftsmanship) are not in conflict — YAGNI means don't add unnecessary features, craftsmanship means write the necessary features well.

## D-186: Structural Quality Delta — Ariadne-Based Quality Measurement

**Date:** 2026-03-31
**Status:** Accepted
**Context:** Quality assessment in Themis is currently subjective — checklist items like "SOLID principles respected" and "KISS — simplest solution that works" are prompt-level judgments that LLMs can satisfy superficially. There's no objective before/after measurement of whether code quality improved or degraded. Ariadne already provides structural metrics (smells, cycles, coupling, Martin metrics) and is used by Themis for regression checks (ariadne_diff, ariadne_cycles, ariadne_smells), but only to detect new problems — not to measure quality delta. `ariadne_refactor_opportunities` is available but unused by any agent.
**Decision:** Three-phase structural quality measurement integrated into the pipeline:

**Phase 1 — Baseline capture (Daedalus, during planning):**
When graph data is available, Daedalus captures structural baseline for files in scope:
- Current smell count and types in affected area (from `ariadne_smells`)
- Martin metrics for affected clusters (from `ariadne_metrics`)
- Known refactoring opportunities in affected area (from `ariadne_refactor_opportunities`)
Baseline is recorded in the plan artifact as `## Structural Baseline` section and propagated to Hephaestus and Themis instruction files as structural context.

**Phase 2 — Structural awareness (Hephaestus, during implementation):**
Hephaestus receives structural baseline in instructions. This is active context, not passive info:
- Files with existing smells → don't make worse, improve if natural
- Clusters in Zone of Pain → minimize new coupling when writing code
- High-churn files (already in capabilities) → extra care confirmed by baseline data
No additional Ariadne queries required from Hephaestus — baseline context is sufficient.

**Phase 3 — Quality delta measurement (Themis, during review):**
After graph auto-updates post-implementation, Themis computes structural quality delta:
- `ariadne_diff` → new/resolved smells, cycles, edges (already used, now framed as delta)
- `ariadne_refactor_opportunities` scoped to changed area → new refactoring needs introduced
- Compare against baseline from plan: smell delta, cycle delta, coupling changes
- Report as `## Structural Quality Delta` in review artifact

**Delta verdict classification:**
- `improved` — resolved smells/cycles, no new ones → no action
- `neutral` — no structural change → no action
- `degraded:minor` — minor coupling increase, no new smells → WARNING
- `degraded:major` — new smells, new cycles, or new refactoring needs → WARNING with details
- Structural degradation is WARNING severity, not CRITICAL — sometimes degradation is justified by the task. But it's always reported and tracked.

**Alternatives rejected:**
- Automated quality scoring formula (composite number) — creates Goodhart's Law risk; agents optimize for the score, not actual quality
- CRITICAL severity for any degradation — too rigid; some tasks legitimately increase complexity
- Hephaestus running its own Ariadne queries for quality — burns implementer budget on metrics; better to receive baseline from planner
- Skipping baseline (only measure after) — without baseline, can't distinguish "was already bad" from "made it bad"
**Reasoning:** Ariadne data is objective, mechanical, and unfakeable — LLMs cannot negotiate with graph metrics. Before/after comparison provides clear signal. WARNING severity means the pipeline reports degradation without blocking — the user decides whether it's acceptable. Daedalus captures baseline once, downstream agents reuse — no duplicated graph queries. The key insight: quality is not just "no new bugs" — it's "the codebase is at least as healthy as before."

## D-187: Graph-First Navigation — Ariadne as Primary Context Source

**Date:** 2026-03-31
**Status:** Accepted
**Context:** Agents spend significant budget on "orientation" — grep/glob searches to find files, manual import tracing to understand dependencies, breadth-first directory scanning to map project structure. Ariadne already indexes all of this (symbols, dependencies, clusters, reading order, context assembly) and agents have these tools listed in capabilities, but they're framed as optional alternatives ("Use ariadne_X when..."). LLMs default to familiar patterns (grep/glob/read) when the alternative is presented as equivalent. Estimated budget waste: Hermes ~40-50%, Hephaestus ~25-35%, Themis ~15-20% spent on search that Ariadne can answer in one call. This budget waste directly reduces capacity for quality work (D-185).
**Decision:** Three changes to make Ariadne the primary navigation tool:

**1. Hermes exploration strategy — graph-first:**
Redefine exploration workflow:
- Step 1: `ariadne_context(seed_files, task_type, budget)` → ranked file list with relevance scores. This replaces the breadth-first directory scan.
- Step 2: Read files by relevance ranking from ariadne_context, not by directory structure.
- Step 3: For deeper exploration, use `ariadne_subgraph` / `ariadne_callees` / `ariadne_reading_order` instead of grep-based import tracing.
- Step 4: Grep/glob as FALLBACK — for non-structural queries (text in comments, config values, string literals) or when graph data is unavailable.
Identity update: "You navigate the codebase graph-first. Ariadne gives you the map — use it before exploring blind."

**2. Daedalus pre-assembled context in instruction files:**
Daedalus already uses `ariadne_context` for budget estimation. Extend: include the context assembly result directly in Hephaestus instruction files as `## Pre-assembled Context`:
- Ranked file list with relevance scores and token estimates
- Key symbols per file (from `ariadne_symbols` via context output)
- Dependency relationships (from `ariadne_subgraph`)
This means Hephaestus starts with a structural map instead of discovering it through grep.

**3. Capability language — PREFER over WHEN:**
Change all agent Ariadne capability descriptions from "Use ariadne_X when..." to "PREFER ariadne_X over grep/glob for...". Specific changes:
- Hermes: "PREFER ariadne_symbol_search over grep for finding functions, classes, or types"
- Hermes: "PREFER ariadne_dependencies over manual import tracing for mapping file relationships"
- Hephaestus: "PREFER ariadne_symbols over Read+grep for finding symbol locations and verifying exports"
- Hephaestus: "PREFER ariadne_callers over grep for finding all usage sites of a changed function"
- Themis: "PREFER ariadne_diff over manual comparison for detecting structural changes"

**Fallback clause:** All agents retain full grep/glob/read access. Graph-first is the preferred strategy, not the only one. When graph data is unavailable (no .ariadne/ directory), agents fall back to traditional exploration. When searching for non-structural content (string literals, comments, config values), grep is the correct tool.

**Alternatives rejected:**
- Remove grep/glob from agent capabilities — too extreme; some searches are genuinely non-structural
- Mandatory Ariadne-only (fail if no graph) — graph may not exist for new projects or unsupported languages
- Full context pre-assembly by orchestrator — violates D-001 (orchestrator never executes); Daedalus is the right agent for this
- Ariadne queries at every step — over-querying wastes MCP budget; one context call + targeted follow-ups is optimal
**Reasoning:** The budget freed by graph-first navigation directly enables quality craftsmanship (D-185). Estimated savings: Hermes 25-30k tokens, Hephaestus 20-25k tokens, Themis 10-15k tokens per task. Pre-assembled context in instructions follows the existing pattern (Daedalus already writes instruction files) — it's a natural extension, not a new mechanism. PREFER language is proven more effective than WHEN for LLM behavior — it creates a default, not an option.

## D-188: Ariadne-Driven Bootstrap — Mechanical Knowledge Population

**Date:** 2026-03-31
**Status:** Accepted
**Context:** Three bugs in init/refresh quality-map connectivity:
1. **Keyword matching trap:** `_moira_bootstrap_gen_quality_map()` classifies patterns by searching scanner text for subjective words ("consistent" → Strong, "broken" → Problematic), but scanners are explicitly prohibited from using subjective language ("NO opinions, NO recommendations"). Quality-map after init is empty or random.
2. **Append-only quality-map:** `moira_knowledge_update_quality_map()` adds new entries but never updates existing ones (IF FOUND → NO ACTION). Observation counts don't accumulate, evidence doesn't grow.
3. **No category migration:** Entries never move between Strong/Adequate/Problematic regardless of evidence. A pattern classified as Adequate at init stays Adequate forever.

Additionally, Ariadne builds a full project graph during init (step 4b) but this data never flows into the knowledge base — it's only available per-task via MCP queries. Agents start their first task with an empty quality-map and no structural intelligence in knowledge.

**Decision:** Replace keyword-based quality-map population with mechanical Ariadne-to-knowledge pipeline. Three layers:

**Layer 1 — Ariadne → Knowledge (bash/jq, 0 LLM tokens):**
New bash function `moira_graph_populate_knowledge()` runs after `moira_graph_build()` during init. Queries Ariadne CLI with `--json` and transforms results via jq:
- `ariadne query smells` → quality-map Problematic entries (with smell type, file, description)
- `ariadne query cycles` → quality-map Problematic entries (with cycle members)
- `ariadne query refactor-opportunities` → quality-map Problematic entries (with Pareto rank, effort/impact)
- `ariadne query hotspots` → quality-map Problematic entries (churn × complexity, if temporal available)
- `ariadne query coupling` → quality-map Adequate/Problematic entries (above threshold, if temporal)
- `ariadne query centrality` → project-model (bottleneck files, structural importance)
- `ariadne query layers` → project-model (architectural layer map)
- `ariadne query metrics` → project-model (Martin metrics per cluster: instability, abstractness, distance)
- `ariadne query boundaries` → enriches boundaries.yaml (structural boundaries supplement scanner-detected ones)
- `ariadne query overview` → project-model (node/edge/cluster/cycle/smell counts)
Graceful degradation: if Ariadne binary absent, skip entirely — quality-map starts empty (honest) instead of keyword-guessed (misleading).

**Layer 2 — Ariadne diff at refresh (bash/jq, 0 LLM tokens):**
New bash function `moira_graph_diff_to_knowledge()` runs after `moira_graph_update()` during refresh:
- `ariadne query diff` → new smells appended to quality-map as Problematic; resolved smells trigger migration to Strong
- Existing entries: increment observation count, append evidence (task ID / refresh date)
- Category migration: 3+ observations of failure → demote (Strong → Adequate → Problematic); smell resolved in diff → promote

**Layer 3 — Hybrid scanners (bash pre-collect + lighter agents):**
- **Tech scanner:** Bash pre-collects all config files (package.json, tsconfig, CI, Dockerfile, etc.) into a single `raw-configs.md`. Agent receives pre-collected data, interprets without Read calls. Budget: ~50k (was 140k).
- **Structure scanner:** Ariadne clusters/layers/overview + bash `ls` → `raw-structure.md`. Agent interprets structural map. Budget: ~50k (was 140k).
- **Convention/Pattern scanners:** Unchanged (need LLM for semantic code reading). Budget: 100k each.
- **Deep scanners:** Receive Ariadne pre-context file (`ariadne-context.md`) with overview, clusters, cycles, boundaries. Focus budget on semantics (business logic, data flow, API contracts) instead of structure discovery. Graceful fallback: if pre-context file absent, scan as before.

**Quality-map lifecycle fix (in `moira_knowledge_update_quality_map`):**
- IF FOUND: increment `Observation count`, append evidence, update timestamp (was: NO ACTION)
- Category migration: 3+ failed findings on Strong → demote to Adequate; 3+ on Adequate → Problematic; 3+ consecutive passes without failures → promote one level
- Freshness: update `<!-- moira:freshness -->` tag on every modification

**Alternatives rejected:**
- Pure bash for all scanners — fragile for framework detection (LLM understands "next" in package.json means Next.js; bash needs hardcoded heuristics per framework)
- Dispatch extra Ariadne-analysis agent — wastes tokens on data transformation that's pure jq
- Keep keyword matching with expanded word list — fundamental design flaw (objective scanner + subjective keywords = unreliable)
- Quality-map populated by LLM interpretation of Ariadne JSON — unnecessary; structured data transforms mechanically

**Reasoning:** Ariadne data is structured JSON with stable schema — transforming it to markdown via jq is reliable and costs 0 LLM tokens. This replaces the most fragile part of bootstrap (keyword heuristics) with the most robust data source (static analysis). Token savings: ~220k per init (~46% reduction) from hybrid scanners. Quality-map starts with real structural evidence instead of empty templates. The 3-observation migration threshold reuses the existing Art 5.2 pattern (evidence-based change), maintaining consistency with rule proposal system.

## D-189: Pipeline Token Optimization — Merged Research Step

**Date:** 2026-04-01
**Status:** Accepted
**Context:** Phase 15 execution consumed ~1.1M tokens and ~115 minutes for ~1,780 lines of output (~730 tokens/line). Analysis revealed systematic waste: duplicate file reading across agents (~50-80k), per-batch review/test overhead (8 dispatches = ~384k for work a single review could cover), and 17 total dispatches generating ~174k orchestrator overhead. Comparable system GSD achieves similar quality with ~5-7 dispatches per task by front-loading quality in planning and embedding verification in execution.

In the current Full pipeline, Hermes (explorer) and Athena (analyst) run in parallel. Hermes reads the codebase and reports facts. Athena formalizes requirements and runs Q1 completeness analysis. In practice, Athena's Q1 analysis depends on what Hermes finds — but Athena doesn't see Hermes's output (they run in parallel). This means Athena works from the task description alone, producing gap analysis that may miss codebase-specific edge cases.

**Decision:** Expand Hermes's exploration instructions to include Q1 gap analysis as part of fact-gathering. Hermes already reports "what it found AND what it looked for but didn't find" — Q1 gap analysis ("these edge cases are not covered, these error paths are missing") is a natural extension of this reporting role. Hermes produces `exploration.md` that includes a `## Gap Analysis` section covering the Q1 completeness checklist items.

Athena remains as a defined agent for cases where complex requirements formalization is needed (e.g., user explicitly requests detailed requirements, or classification indicates requirements ambiguity). In Standard and Full pipelines, Athena is no longer dispatched by default — Hermes handles gap analysis. Athena can be dispatched on-demand via plan gate `rearchitect` flow or when Hermes reports STATUS: blocked on requirements.

This saves one agent dispatch (~56k tokens) and eliminates the parallel-but-disconnected problem where Athena and Hermes independently analyze the same task.

**Constitutional impact:** Art 1.2 lists Analyst as a separate role. Hermes's expanded scope remains within "reads code, reports facts" — gap analysis is fact-reporting ("this edge case has no handler"), not requirements proposal. Athena's role definition is unchanged — she's available but not default-dispatched. No Art 1.2 violation.

**Alternatives rejected:**
- Merge Hermes and Athena into a single agent — violates Art 1.2 (agent single responsibility). Hermes explores, Athena analyzes requirements. Keeping them separate preserves the option to dispatch Athena independently.
- Keep parallel dispatch but pass Hermes output to Athena — adds sequential dependency, eliminating the parallelism benefit that justified the separation. If they must be sequential, Hermes should just do both.
- Remove Athena entirely — loses the ability to handle complex requirements scenarios where dedicated analysis is needed.
**Reasoning:** The parallel Hermes+Athena dispatch was designed for independence, but Q1 analysis is more valuable when informed by codebase facts. Moving gap analysis into exploration produces better Q1 output and saves a dispatch. Athena remains available as a specialist tool.

## D-190: Pipeline Token Optimization — Plan Validation Step

**Date:** 2026-04-01
**Status:** Accepted
**Context:** In Phase 15, per-batch code review (Themis × 4 = 264k tokens) caught one real bug (tr no-op in Batch C) and generated mostly suggestions/warnings. The bug would have been caught equally well in a single final review. GSD's approach: validate the PLAN before execution (plan-checker), not the CODE after execution. Catching issues in a 2k plan is cheaper than catching them in 50k of implemented code.

**Decision:** Add a plan validation step after Daedalus produces the plan. Themis is dispatched in a lightweight "plan-check" mode that validates:
1. Scope alignment — plan covers all acceptance criteria from classification
2. File existence — every file in plan exists (or is explicitly new)
3. Dependency ordering — no step requires output from a later step
4. Contract completeness — batch interfaces are fully specified
5. Verification coverage — every task has a concrete `<verify>` command
6. Budget feasibility — no batch exceeds agent limits

This is a ~40k dispatch that catches planning errors before they become expensive implementation bugs. It replaces the need for per-batch review by ensuring the plan is solid upfront.

Plan-check findings are presented at the plan gate alongside the plan summary. If plan-check finds critical issues, Daedalus is re-dispatched with feedback (same as current plan gate `modify` flow).

**Alternatives rejected:**
- Separate plan-checker agent — new agent violates Art 1.3 (no unnecessary components). Themis already reviews artifacts; plan-check is a review variant.
- Skip plan validation, keep per-batch review — empirically shown to cost 3x more for marginal quality gain.
- Automated plan validation only (no agent) — can check structural properties (file exists, dependency DAG valid) but can't assess semantic correctness (does this plan actually solve the problem?).
**Reasoning:** Quality is cheaper to ensure at planning time than at implementation time. A 40k plan-check replaces 264k of per-batch review. Themis already has the review skillset — plan-check is a mode, not a new capability.

## D-191: Pipeline Token Optimization — Embedded Task Verification

**Date:** 2026-04-01
**Status:** Accepted
**Context:** Aletheia (tester) was dispatched 4 times in Phase 15 = 120k tokens. Each dispatch mostly runs `run-all.sh` and greps the output — a bash operation costing ~0 tokens when done mechanically. GSD embeds verification commands directly in task definitions: each task has `<verify>` (command to run) and `<done>` (success criteria). The executor runs verification itself.

**Decision:** Two changes:

**1. Embedded verification in Hephaestus tasks:**
Daedalus includes a `<verify>` field in each task within the plan. Hephaestus runs the verify command after completing each task. If verification fails, Hephaestus fixes the issue (up to 2 attempts) before proceeding. Verification results are recorded in implementation.md.

Format in plan:
```
### Task 1: Implement populate_knowledge()
Files: src/global/lib/graph.sh
Action: ...
Verify: bash src/tests/tier1/test-ariadne-knowledge-pipeline.sh
Done: All 34 tests pass, function exists and is callable
```

**2. Post-implementation build/test step (bash):**
After all implementation batches complete and BEFORE final review, a bash step runs build and test commands from `config.yaml → tooling.post_implementation[]`. Results written to `tasks/{id}/test-results.md`. If build/tests fail → Hephaestus retry with failure context (max 2 attempts, then escalate to user).

If `tooling.post_implementation[]` is empty or missing, the step is skipped — embedded per-task `<verify>` commands are the only test coverage. The onboarding flow (`/moira:init`) prompts users to configure their build/test commands.

**3. Aletheia removed from Standard/Full pipelines (D-194):**
Aletheia's responsibilities are redistributed:
- "Run tests" → bash step (mechanical operation, 0 tokens)
- "Write new tests" → Hephaestus (tests are code; Daedalus includes test tasks in plan)
- "Build check" → bash step
- Ad-hoc testing at final gate → Hephaestus dispatch (not a separate tester)

Aletheia remains as an agent definition for Decomposition pipeline (cross-task integration testing) and specialized scenarios. But it is no longer part of Standard or Full pipeline flows.

**Constitutional impact:** Art 2.2 gate list — "per-phase" gate in Full pipeline changes. Previously: implement → review → test → gate. Now: implement (with embedded verify) → build/test (bash) → review → gate. Requires Art 2.2 amendment. Art 1.2 — Tester remains a defined agent role; it's simply not dispatched in Standard/Full pipelines (same pattern as Analyst per D-189).

**Alternatives rejected:**
- Keep Aletheia for all testing — empirically costs 120k for what bash does in 0 tokens.
- Aletheia fallback when no tests configured — adds conditional complexity for marginal benefit. Embedded `<verify>` covers per-task correctness; build step covers compilation. If users want comprehensive testing, they configure `tooling.post_implementation`.
- Embedded verify only, no build/test step — misses regression testing and build verification.
**Reasoning:** Testing decomposes into two operations: running tests (mechanical, bash) and writing tests (creative, code). Running tests doesn't need an agent. Writing tests is implementation work — Hephaestus already writes code per plan. A separate tester agent is an unnecessary intermediary.

## D-192: Pipeline Token Optimization — Analysis Paralysis Guard

**Date:** 2026-04-01
**Status:** Accepted
**Context:** In Phase 15, Daedalus's first dispatch hung for 21 minutes (likely in an exploration loop). GSD includes an explicit guard: "If 5+ consecutive Read/Grep/Glob calls occur without Edit/Write/Bash action: STOP. State the blocker in one sentence." This prevents agents from entering infinite investigation loops.

**Decision:** Add analysis paralysis guard to all implementation-phase agents (Hephaestus, Themis, Daedalus). Injected as a base rule addition:

```
ANALYSIS PARALYSIS GUARD: If you make 5+ consecutive read-only tool calls (Read, Grep, Glob)
without a write action (Edit, Write, Bash), STOP. State the blocker in one sentence, then
either write code or report STATUS: blocked with what specific information is missing.
```

For exploration agents (Hermes), the threshold is higher (10+ consecutive reads) since their role IS exploration. But even Hermes should not loop indefinitely.

This is a prompt-level behavioral guard, not a structural enforcement. Its effectiveness depends on LLM compliance — but it addresses the most common failure mode (agent enters an investigation spiral) with zero implementation cost.

**Alternatives rejected:**
- Hook-based enforcement (count tool calls, kill agent) — too aggressive, may kill agents doing legitimate deep exploration.
- No guard (rely on budget limits) — budget limits catch the problem eventually but waste tokens in the process. A prompt guard catches it early.
- Strict enforcement per tool call — requires shell hook complexity for marginal benefit over prompt guard.
**Reasoning:** Zero implementation cost, addresses the most expensive failure mode (Daedalus 21-min hang). Even partial compliance saves significant tokens and time.

## D-193: Pipeline Token Optimization — Optimized Full Pipeline Structure

**Date:** 2026-04-01
**Status:** Accepted
**Context:** The Full pipeline currently runs 17 dispatches for a large task. After D-189 through D-192, the pipeline structure changes significantly. This decision captures the complete optimized pipeline definition.

**Decision:** Optimized Full Pipeline:

```
classify(Apollo) → [GATE: classification] →
research(Hermes, expanded with Q1 gap analysis) →
architect(Metis) → [GATE: architecture] →
plan(Daedalus, with embedded verify fields) →
plan-check(Themis, lightweight plan validation) → [GATE: plan] →
[per-batch: implement(Hephaestus, with embedded verify)] →
  [GATE: mid-point review — only for >2 batches, after ~50% complete] →
final-review(Themis, comprehensive) →
test-hook(bash) →
[GATE: final]
```

**Gate changes from current:**
- Current: classification + architecture + plan + per-phase (repeating) + final
- New: classification + architecture + plan + mid-point (conditional, for >2 batches) + final

The per-phase gate (after every batch) is replaced by a conditional mid-point gate and a final gate. This reflects the shift from "catch issues per batch" to "prevent issues through plan validation + catch remaining issues in final review."

**Batch count guidance:**
- Default: 2 batches (natural split by dependency layers)
- Maximum: 3 batches before mid-point gate triggers
- Split threshold: if any batch exceeds ~120 tool uses (estimated), auto-split

**Estimated token budget:**
| Step | Agent | Tokens |
|------|-------|--------|
| Classify | Apollo | ~26k |
| Research | Hermes (expanded) | ~100k |
| Architect | Metis | ~100k |
| Plan | Daedalus | ~60k |
| Plan-check | Themis | ~40k |
| Implement × 2 | Hephaestus | ~200k |
| Final review | Themis | ~80k |
| Test hook | bash | ~0k |
| Orchestrator | — | ~60k |
| **Total** | | **~666k** |

With leaner prompts and artifact chain: **~530-570k** (vs 1.1M current = ~50% reduction).

**Standard pipeline changes (symmetric):**
- Athena no longer default-dispatched (D-189)
- Aletheia removed from pipeline, build/test via bash (D-191, D-194)
- Standard estimated budget: ~350-400k (vs current ~400-500k)

**Alternatives rejected:**
- Merge Metis + Daedalus into single dispatch — violates Art 1.2 (Architect "Does NOT decompose into tasks", Planner "Does NOT make architectural decisions"). The role boundary is meaningful.
- Single batch for all work — risk of context overflow in Hephaestus for large tasks (>120 tool uses).
- No mid-point gate — for 3+ batch tasks, user loses visibility until the end.
- Remove final review entirely (rely only on embedded verify) — embedded verify catches task-level issues but misses cross-task architectural concerns. Final Themis review remains valuable.

**Constitutional impact:** Art 2.2 amendment required — Full pipeline gate list changes from "classification + architecture + plan + per-phase + final" to "classification + architecture + plan + mid-point (conditional) + final".

**Reasoning:** The optimization targets are achieved through three mechanisms: (1) fewer dispatches (17 → ~8), (2) front-loaded quality (plan-check instead of per-batch review), (3) mechanical verification (embedded verify + bash build/test instead of agent dispatches). Quality signals are preserved — Q1 through Q5 all still happen, just more efficiently.

## D-194: Aletheia Removed from Standard/Full Pipelines

**Date:** 2026-04-01
**Status:** Accepted
**Context:** During D-191 design, Aletheia was initially kept as a fallback for projects without configured test commands. But analysis shows Aletheia's responsibilities decompose into two categories: (1) running tests — a mechanical bash operation, (2) writing tests — implementation work that Hephaestus already does. A separate tester agent is an unnecessary intermediary in both cases.

**Decision:** Remove Aletheia from Standard and Full pipeline flows entirely:
- **Running tests/build** → bash step using `tooling.post_implementation[]`. If empty, step skipped (embedded `<verify>` provides per-task coverage).
- **Writing tests** → Hephaestus. Tests are code. Daedalus includes test tasks in the plan with `Verify:` and `Done:` fields like any other task.
- **Ad-hoc testing at final gate** → Hephaestus dispatch (user says "run these tests" → implementer runs them).

Bash build/test step runs BEFORE final review (Themis). This ensures Themis reviews code that is known to compile and pass tests — better quality signal than reviewing potentially broken code.

Pipeline flow becomes:
```
implement (Hephaestus, with embedded verify) →
build/test step (bash, tooling.post_implementation[]) →
  if fail → Hephaestus retry (max 2) →
final review (Themis, reviews working code) →
final gate
```

Aletheia remains as an agent definition but is not dispatched by default in any pipeline. Available for explicit user request for specialized test work.

**Constitutional impact:** Art 1.2 — Tester remains a defined agent role. Not dispatching it is the same pattern as Analyst (D-189): role exists, dispatch is conditional on need.

**Alternatives rejected:**
- Keep Aletheia as fallback for unconfigured projects — adds conditional branching complexity. Embedded `<verify>` + build step covers correctness; full Aletheia dispatch for "discover and run tests" is overkill when the plan already specifies what to test.
- Move test-writing to Themis — violates Art 1.2 (Reviewer "Does NOT fix code"). Writing tests is writing code.
**Reasoning:** Agent dispatch should match the complexity of the work. Running `npm test` doesn't need 30k tokens of agent context. Writing tests is writing code — Hephaestus's job. The tester role served a separation-of-concerns purpose in the original design, but in practice it's a tax on every pipeline run for work that's either mechanical (bash) or already covered (implementer).

## D-195: Aletheia Removed from Decomposition Pipeline

**Date:** 2026-04-01
**Status:** Accepted
**Context:** D-194 removed Aletheia from Standard/Full pipelines but kept it in Decomposition for "cross-task integration testing." However, integration testing decomposes the same way as regular testing: running integration tests is bash, writing them is Hephaestus. The Decomposition pipeline already executes each sub-task through Standard/Full pipelines which now include build/test steps. Cross-task integration is either: (1) running an integration test suite (bash), or (2) writing integration tests as part of the final sub-task (Hephaestus).

**Decision:** Remove Aletheia from Decomposition pipeline. Replace integration step with:
- Bash build/test step using `tooling.post_implementation[]` (same as Standard/Full)
- If integration tests need to be written, Daedalus includes them as tasks in the final sub-task's plan

Aletheia agent definition remains in the system for explicit user dispatch but is no longer part of any default pipeline flow.

**Alternatives rejected:**
- Keep Aletheia for Decomposition only — inconsistent with D-194 reasoning. Same work, same solution.
- Remove Aletheia agent definition entirely — may be useful for future specialized scenarios.
**Reasoning:** Consistency with D-194. Integration testing is either mechanical (bash) or implementation (Hephaestus). No pipeline needs a dedicated tester agent by default.

## D-196: Role File Schema with Mechanical Validation

**Date:** 2026-04-01
**Status:** Accepted
**Context:** 11 agent role files in `src/global/core/rules/roles/` evolved across phases 2-14. Each has a different set of top-level keys. `quality_stance` exists in 9/11 files. `capabilities` missing from Mnemosyne. `response_format` missing from Calliope. No schema file validates role structure — `test-agent-definitions.sh` checks some keys but not completeness.

**Decision:** Create `src/schemas/role.schema.yaml` defining role file structure. Required keys: `_meta` (name, role, purpose, budget), `identity`, `capabilities`, `never`, `knowledge_access`, `response_format`. Optional keys documented with purpose: `quality_stance`, `quality_checklist`, `artifact_contract`, `write_access`, `analytical_mode`, `analysis_paralysis_guard`, `embedded_verification`. All 11 role files normalized to include all required keys. Validated by tier1 test.

**Alternatives rejected:**
- Keep role files ad-hoc, document conventions only — role files are consumed by scripts (rules.sh) and LLM prompts; inconsistency causes silent bugs when scripts expect keys that don't exist.
- JSON Schema validator — adds external dependency; custom YAML schema system already exists and works.
**Reasoning:** Role files are the most-read configuration files in the system — every agent dispatch assembles from them. Inconsistency between files is a source of subtle bugs. Schema + validation catches drift early.

## D-197: Artifact Contracts for All Pipeline Agents

**Date:** 2026-04-01
**Status:** Accepted
**Context:** D-184 introduced artifact output contracts for Apollo, Metis, and Daedalus — the three agents where wrong output is most costly. `artifact-validate.sh` enforces these via blocking SubagentStop hook. But 8 other agents (Hermes, Athena, Hephaestus, Themis, Aletheia, Calliope, Mnemosyne, Argus) have no mechanical validation of their artifact structure. Missing sections in exploration.md or review.md cause silent downstream failures.

**Decision:** Define artifact section contracts for all pipeline agents. Extend `artifact-validate.sh` to validate all agents that produce artifacts (not just 3). Required sections per agent documented in `design/architecture/agents.md`. Validation is structural only (section headers exist) — same pattern as D-184. Agents not dispatched by default (Aletheia, Athena) still have contracts for when they are dispatched on-demand.

Contracts are intentionally minimal — only sections that downstream consumers depend on. The goal is catching structural omissions, not enforcing quality (that's the quality gate system's job).

**Alternatives rejected:**
- Validate only agents dispatched by default — on-demand agents (Athena, Aletheia) still produce artifacts consumed by the pipeline. Missing sections cause the same problems.
- Deep content validation (check section has N+ lines) — too fragile; sections vary by task complexity. Header-presence is the right mechanical boundary.
**Reasoning:** Extending the proven D-184 pattern to all agents. artifact-validate.sh already handles the blocking/retry cycle. Adding more role cases is low-risk, high-value.

## D-198: Pipeline Tracker Consolidation

**Date:** 2026-04-01
**Status:** Accepted
**Context:** Pipeline state is tracked in two files: `current.yaml` (YAML, has schema, managed by state.sh) and `pipeline-tracker.state` (custom key=value format, no schema, separate parser). Both store pipeline name and overlap on state. Hooks read from both, creating dual source of truth. `pipeline-tracker.state` also spawns per-subtask variants (`pipeline-tracker-sub-{N}.state`).

**Decision:** Eliminate `pipeline-tracker.state`. Merge all its fields into `current.yaml`: `last_role`, `review_pending`, `test_pending`, `dispatched_role`, `subtask_mode`, `current_subtask`, `subtask_counter`. Per-subtask state moves to `state/subtasks/{N}.yaml` using the same schema fields. All hooks updated to read/write `current.yaml` via `moira_yaml_get`/`moira_yaml_set`. Single file, single format, single parser, single schema.

**Alternatives rejected:**
- Keep pipeline-tracker.state, add schema — still two files, two parsers, two sources of truth. Complexity not justified.
- Move everything to pipeline-tracker.state — would mean abandoning the YAML schema system that validates current.yaml.
**Reasoning:** Dual state tracking is the #1 source of potential state inconsistency. YAML with schema validation is strictly better than ad-hoc key=value. Migration eliminates an entire class of bugs (state desync between files).

## D-199: Preflight Context Injection

**Date:** 2026-04-01
**Status:** Accepted
**Context:** Phase 16 (D-178) eliminated orchestrator state WRITES via hooks. But the orchestrator still performs ~10 Read operations at pipeline start to determine graph availability, quality mode, bench mode, audit-pending, checkpointed state, stale knowledge, and stale locks. These are pure lookups with deterministic logic — no LLM judgment needed. Each Read costs ~200 tokens of context narration + tool call overhead, totaling ~2000 tokens and ~10 tool calls before the first agent dispatch.

**Decision:** Extend `task-submit.sh` hook to gather all preflight context after task scaffold and inject it via `additionalContext` in `hookSpecificOutput`. The orchestrator receives a structured `MOIRA_PREFLIGHT:` block containing: `graph_available`, `graph_stale`, `quality_mode`, `evolution_target`, `bench_mode`, `deep_scan_pending`, `audit_pending` (+ depth), `checkpointed` (+ task_id + step), `stale_knowledge_count`, `stale_locks` list, `orphaned_state`. Values are written to `current.yaml` by the hook (graph_available, temporal_available remain false — temporal requires MCP). Orchestrator reads 0 files for init; handles only interactive flags (checkpointed redirect, audit prompt) and temporal MCP check.

**Fallback:** If `additionalContext` is empty or missing `MOIRA_PREFLIGHT:` marker, orchestrator falls back to manual reads (current behavior). This makes the optimization non-breaking.

**Alternatives rejected:**
- Separate preflight.yaml file — duplicates state already in current.yaml and config.yaml. Adds a file to maintain.
- `!`command`` in orchestrator.md skill — executes at skill load time, not per-task. Can't access task_id.
- SessionStart hook — fires before task is known; no task context available.
**Reasoning:** `task-submit.sh` already runs at the right moment (after scaffold, before orchestrator), already uses `additionalContext`, and has access to all state files. Extending it is the minimal change. Fallback ensures zero risk.

## D-200: Pre-planning Instruction Assembly

**Date:** 2026-04-01
**Status:** Accepted
**Context:** `moira_rules_assemble_instruction()` in `rules.sh` builds complete agent instruction files. Daedalus writes instruction files for post-planning agents (Hephaestus, Themis, Aletheia). But pre-planning agents (Apollo, Hermes, Athena) use "simplified assembly" — the orchestrator reads 5-8 files per agent (role YAML, base rules, response contract, task context, quality checklist, traceability) and assembles the prompt inline. This costs ~500-800 tokens per agent in Read operations, ~3000-5000 tokens total for pre-planning dispatch.

**Decision:** Generate instruction files for pre-planning agents using `moira_rules_assemble_instruction()`:
- **Apollo:** Generated by `task-submit.sh` hook immediately after scaffold. Apollo's inputs are fully known at task start (input.md, no prior artifacts). Instruction file written to `.moira/state/tasks/{task_id}/instructions/apollo.md`.
- **Hermes, Athena:** Generated by a new shell function `moira_preflight_assemble_exploration()` called after classification gate. At that point classification.md exists and pipeline type is known. Orchestrator calls one Bash-equivalent (or a hook on gate completion triggers it). Instruction files written to `instructions/{agent}.md`.
- **Metis, Daedalus:** Continue using simplified assembly (they need upstream artifacts that aren't available until their step).

Orchestrator dispatch path: check for instruction file → if exists, 1 Read → if not, fallback to simplified assembly. Same logic already in `dispatch.md` for post-planning agents.

**Alternatives rejected:**
- `updatedInput` in PreToolUse hook to inject assembled prompt — replaces entire Agent tool input, orchestrator loses visibility into what agent receives. Debugging becomes opaque.
- Assemble all agents at task start — impossible; Hermes needs classification.md, Metis needs exploration.md.
- Generate in SubagentStart hook — hook fires too late (agent already starting), can't modify prompt.
**Reasoning:** Unified instruction file mechanism for all agents. `rules.sh` already handles the assembly logic with conflict detection, size validation, and MCP injection. Pre-planning agents are the last gap. Fallback to simplified assembly means zero risk if file generation fails.

## D-201: Gate Data Collection and Input Pre-classification

**Date:** 2026-04-01
**Status:** Accepted
**Context:** At each approval gate, the orchestrator reads 5-6 files to render the gate frame: agent artifact (extract required sections), current.yaml (budget, history, step progress), violations.log (count), status.yaml (gates passed, retries). Then it classifies user input against gate options — exact matches (numbers, "proceed", "abort") are trivially deterministic but still consume LLM inference. With 3-5 gates per standard pipeline, this is ~3000-5000 tokens on reads + ~500-1500 on classification overhead.

**Decision:** Create `gate-context.sh`, a `UserPromptSubmit` hook that activates when `gate_pending` is set in `current.yaml`:

**Data collection:** Extract artifact required sections via `moira_md_extract_section()` (new utility function). Compute health metrics (context percent, violations, agents dispatched, gates passed, retries, progress). Assemble into structured `GATE_DATA:` block injected via `additionalContext`.

**Input pre-classification:** Classify user input deterministically:
- Numeric input matching option count → `INPUT_CLASS: menu_selection:{N}`
- Exact keyword match (proceed/abort/details/modify/checkpoint/rearchitect, case-insensitive) → `INPUT_CLASS: menu_selection:{keyword}`
- "clear feedback" → `INPUT_CLASS: clear_feedback`
- Input ending with `?` → `INPUT_CLASS: question`
- Everything else → `INPUT_CLASS: needs_llm`

Orchestrator receives pre-collected data + pre-classified input. For `menu_selection` and `clear_feedback` — zero LLM classification needed. For `question` and `needs_llm` — orchestrator classifies from ready data (no file reads needed). Gate rendering stays in orchestrator (LLM formats from data, per "shell collects, LLM formats" principle).

**New utility:** `moira_md_extract_section()` in `lib/markdown-utils.sh` — extracts text between `## Section` and next `## ` or EOF. Handles edge cases: nested `###`, empty sections, sections at EOF. Tested in tier1.

**Fallback:** If `GATE_DATA:` missing from context, orchestrator reads files manually. If `INPUT_CLASS:` missing, orchestrator classifies input itself. Both paths already work today.

**Alternatives rejected:**
- Shell renders full gate frame (Unicode art) — fragile; formatting is LLM's strength. Shell can't adapt to varying content lengths.
- `context: fork` skill for gate evaluation — adds a subagent dispatch overhead per gate. More tokens, not fewer.
- PreToolUse hook on Write to intercept gate recording — circular; we're trying to help the orchestrator, not intercept it.
**Reasoning:** "Shell collects data, LLM formats" is the robust split. Deterministic input classification handles the ~70% happy path (user types a number or keyword). Gate data collection eliminates 5-6 Reads per gate. Combined savings: ~4000-6000 tokens per pipeline.

## D-202: Project State Directory — .moira/ instead of .moira/

**Context:** Claude Code has hardcoded sensitive file protection for `.claude/` directory. Any Write/Edit/Bash operation on files inside `.claude/` triggers a permission prompt that cannot be overridden by `permissions.allow` rules in settings.json. Only `.claude/commands/`, `.claude/agents/`, and `.claude/skills/` are exempt. This blocks Moira's subagents from writing state, knowledge, and config files without manual approval on every operation.

**Decision:** Move project-level Moira directory from `.moira/` to `.moira/` (top-level dotdir). Global install stays at `~/.claude/moira/`.

**Alternatives rejected:**
- Keep `.moira/` and accept permission prompts — breaks agent autonomy, every write needs manual approval
- Move into `.claude/agents/moira/` or `.claude/skills/moira/` — abuses exempt directories for wrong purpose, fragile if Claude Code changes exemptions
- Use `bypassPermissions` mode — disables ALL safety checks, too broad
- Use PreToolUse hook to auto-approve — hooks can't override the sensitive file check (it's a separate layer)

**Reasoning:** `.moira/` is outside `.claude/` sensitive boundary, so standard `permissions.allow` patterns work. Simpler permission patterns (no absolute path hacks needed). Clean semantic separation: `.claude/` = Claude Code config, `.moira/` = Moira runtime. Global install (`~/.claude/moira/`) is unaffected — it's user-level, not project-level.

## D-203: Structural Enforcement for Orchestrator-Inline Steps

**Date:** 2026-04-02
**Status:** Accepted
**Context:** Real-world testing revealed that the orchestrator skips non-blocking intermediate steps that are described in orchestrator.md prose but have no structural hook enforcement. Out of 10 steps the orchestrator skipped in a real task session, 8 had no hooks — they relied on the LLM remembering prose instructions. The root cause is overconfidence: the orchestrator reads the skill once, then follows the happy path (dispatch agent → get result → next dispatch), dropping all between-dispatch checks.

Pattern confirmed: **everything automated via hooks works; everything relying on "orchestrator should do X" gets skipped.**

**Decision:** Convert 4 categories of orchestrator-inline steps to structural hook enforcement:

### Change 1: Passive audits + agent guard check → `agent-done.sh` (SubagentStop)

After each agent returns, `agent-done.sh` now automatically runs:
- **Knowledge drift check (e1b):** After explorer role — compares exploration summary against `.moira/knowledge/project-model/summary.md`. Logs `knowledge_drift` warning to `status.yaml` if contradictions found. Non-blocking.
- **Convention drift check (e1c):** After reviewer role — compares review findings against `.moira/knowledge/conventions/summary.md`. Logs `convention_drift` warning. Non-blocking.
- **Agent guard check (d1):** After implementer role — runs `git diff --name-only` against protected paths (`design/CONSTITUTION.md`, `design/**`, `.moira/core/**`, `src/global/**`). Logs violations to `violations.log`. Injects additionalContext warning if violations found.

These checks are now automatic — the orchestrator doesn't need to remember them.

### Change 2: Completion processor enforcement → `pipeline-stop-guard.sh` (Stop)

Extended to check: if pipeline is active AND `step_status` is not `completed`/`checkpointed` AND no completion processor has been dispatched (tracked via `completion_dispatched` field in current.yaml) → `decision: "block"` with reason to dispatch completion processor.

The `completion_dispatched` field is set to `true` by `pipeline-tracker.sh` when it detects a completion processor dispatch (role detection via description pattern).

### Change 3: Bash boundary → `guard-prevent.sh` (PreToolUse)

Matcher expanded from `Read|Write|Edit` to `Read|Write|Edit|Bash`. For Bash tool calls:
- If command operates on `.moira/` paths → allow (orchestrator manages state via Bash)
- If command is anything else → deny with "Orchestrator cannot use Bash on project. Dispatch an agent instead."
- Subagent bypass preserved (agents can use Bash freely).

Settings.json matcher updated from `"Read|Write|Edit"` to `"Read|Write|Edit|Bash"`.

### Change 4: Workspace change detection → `pipeline-dispatch.sh` (PreToolUse on Agent)

Before each agent dispatch, checks `git status --porcelain` for external changes since last agent completed. If changes detected → injects additionalContext warning listing changed files. Advisory only (does not block) — user decision required for re-exploration.

Previous git status snapshot stored in `.moira/state/.git-snapshot` by `agent-done.sh` after each agent.

**Alternatives rejected:**
- Stop hook with agent type for verification — costs extra tokens per stop, 60s timeout risk. Command-type hooks are sufficient for deterministic checks.
- New pipeline-state.json file — `current.yaml` already tracks all needed state; adding another file would duplicate state (lesson from D-198).
- Making passive audits blocking — they are informational (knowledge/convention drift). Blocking would halt pipeline for warnings. Instead, they inject context so the orchestrator is aware.

**Reasoning:** The system already has 12 structural hooks covering agent ordering, artifact validation, state transitions, etc. The 4 remaining gaps are all cases where the orchestrator was expected to self-enforce prose instructions. Converting them to hooks follows the proven pattern: hooks handle deterministic checks, LLM handles judgment calls.
