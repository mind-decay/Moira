# Quality Enforcement System

## Principle: Quality Built In, Not Checked After

Quality is not a final gate. It's embedded at every pipeline level.

```
Requirements ──→ [Q1: Completeness] ──→ Architecture
Architecture ──→ [Q2: Soundness]    ──→ Plan
Plan         ──→ [Q3: Feasibility]  ──→ Implementation
Implementation → [Q4: Correctness]  ──→ Tests
Tests        ──→ [Q5: Coverage]     ──→ Done
```

## Quality Gates

### Q1: Requirements Completeness (Analyst)

```
- [ ] Happy path clearly defined
- [ ] Error cases enumerated
- [ ] Edge cases identified (empty state, max values, concurrent access)
- [ ] Input validation rules specified
- [ ] Output format defined (NOT assumed)
- [ ] Performance expectations stated or marked as "standard"
- [ ] Security implications assessed
- [ ] Backwards compatibility impact assessed

MISSING ITEMS → STATUS: blocked, ask user
```

### Q2: Architecture Soundness (Architect)

```
- [ ] Follows existing project patterns (or explicitly justified deviation)
- [ ] Single Responsibility — each component has one reason to change
- [ ] Open/Closed — extends without modifying existing contracts
- [ ] No circular dependencies introduced
- [ ] No God objects/functions (>200 lines = split)
- [ ] Data flow is unidirectional where possible
- [ ] External API contracts are VERIFIED (never assumed)
- [ ] Performance: no N+1 queries, no unbounded loops, no blocking I/O in hot paths
- [ ] Error boundaries defined
```

### Q3: Plan Feasibility (Planner)

```
- [ ] Every file in plan actually exists (or is explicitly new)
- [ ] Dependencies between steps are correctly ordered
- [ ] Context budget per step is within agent limits
- [ ] No step requires knowledge that previous steps don't produce
- [ ] Rollback path exists for each step
- [ ] Contract interfaces defined for parallel batches
```

### Q4: Code Correctness (Reviewer)

#### Correctness
```
- [ ] Implements exactly what plan specifies (no more, no less)
- [ ] All acceptance criteria from requirements are met
- [ ] Edge cases from requirements are handled
- [ ] Error handling matches architecture decision
```

#### Standards
```
- [ ] SOLID principles respected
- [ ] DRY — no copy-pasted logic (no premature abstractions either)
- [ ] KISS — simplest solution that works
- [ ] YAGNI — no code for unrequested future requirements
```

#### Performance
```
- [ ] No N+1 queries
- [ ] No synchronous operations that should be async
- [ ] No memory leaks (unclosed connections, growing arrays, unreleased listeners)
- [ ] No unbounded operations (pagination where needed)
- [ ] Database queries use indexes
```

#### Security
```
- [ ] No SQL/command injection (parameterized queries)
- [ ] No XSS (output encoding)
- [ ] No sensitive data in logs
- [ ] Input validation at system boundary
- [ ] Auth/authz checks where needed
```

#### Integration
```
- [ ] Imports resolve correctly
- [ ] Types match across file boundaries
- [ ] API contracts match between caller and callee
- [ ] No hardcoded values that should be config
```

#### Project Conventions
```
- [ ] Naming matches conventions
- [ ] File location matches structure
- [ ] Code style matches codebase
- [ ] Error handling pattern matches project pattern
```

Issue severity:
- **CRITICAL**: blocks pipeline, must fix
- **WARNING**: should fix, can proceed with user approval
- **SUGGESTION**: logged for reflection, doesn't block

**Cross-reference:** Q4 serves as the primary behavioral defense mechanism in the three-tier enforcement model (D-065). Behavioral constraints (NEVER rules, role boundaries, fabrication prohibition) cannot be structurally enforced — Reviewer's Q4 checklist is the primary per-task detection layer. See `fault-tolerance.md` § Enforcement Model for the full three-tier model.

### Q5: Test Coverage (Tester)

```
- [ ] Happy path tested
- [ ] Each error case from requirements has a test
- [ ] Edge cases have tests
- [ ] Integration points tested
- [ ] Tests actually run and pass
- [ ] No brittle tests (testing implementation details)
- [ ] Tests match project testing patterns
```

## Quality Criteria — Good vs Bad Code

### What Makes Code GOOD

**Correctness (non-negotiable)**
- Does exactly what requirements specify
- Handles all enumerated edge cases
- No runtime errors on valid input
- No silent failures

**Readability (high priority)**
- Names describe WHAT, not HOW
- Functions do ONE thing (≤30 lines preferred, ≤50 max)
- No nested ternaries beyond 1 level
- No boolean params that change behavior (use separate functions or options)
- Linear control flow (early returns > nested if/else)

**Maintainability (high priority)**
- Changes to requirement X affect ≤3 files
- No hidden coupling
- No magic numbers/strings
- Types/interfaces at boundaries

**Performance (context-dependent)**
- No O(n²) where O(n) is possible
- No N+1 database queries
- No synchronous blocking in async context
- No unbounded growth

**Security (non-negotiable)**
- All external input validated at boundary
- No string concatenation for queries/commands
- No secrets in code
- Auth checks on protected resources

### What Makes Code BAD

**Absolute red flags (always flag)**
- Fabricated APIs/URLs/schemas
- Error swallowing (catch with no handling)
- eval() or dynamic code execution
- Hardcoded credentials
- SQL/command injection vectors

**Context-dependent flags**
- Inconsistency with project patterns (unless pattern is in 🔴 quality-map)
- Over-engineering for current requirement
- Under-engineering for known scale requirements

## Quality Map

Generated at bootstrap, evolved over time. Three categories:

### ✅ Strong Patterns (follow as-is)
Proven patterns with evidence. Implementer copies approach exactly.

### ⚠️ Adequate Patterns (follow, note limitations)
Working but imperfect. Implementer follows them. Limitations documented for future evolution.

### 🔴 Problematic Patterns (don't replicate)
Known bad patterns. Implementer does NOT extend these to new code. Uses correct pattern for new code, adds TODO comment for migration.

## Code Quality Evolution

### Two Modes

**CONFORM (default):** Follow existing patterns, even if imperfect. Consistency > perfection.

**EVOLVE (explicit):** Improve a pattern systemically. Only when explicitly requested or when system has accumulated sufficient evidence.

### Evolution Lifecycle

```
Discovery → Documentation → Accumulation → Proposal → Approval → Execution
```

1. **Discovery**: Reviewer/Explorer notices pattern issue. Tag: 🆕 NEW
2. **Documentation**: Issue seen again. Tag: ⚠️ CONFIRMED
3. **Accumulation**: Impact measured. Tag: 📊 MEASURED
4. **Proposal**: 3+ issues from same pattern → propose evolution to user
5. **Approval**: User approves evolution as dedicated task
6. **Execution**: Task runs through Full Pipeline in EVOLVE mode

### Anti-Chaos Safeguards

1. **One evolution at a time** — complete current before starting next
2. **Scope lock** — no "while we're at it" expansions
3. **Regression detection** — full test suite after evolution, rollback if breaks
4. **Cooldown period** — 5 tasks in CONFORM mode after evolution, monitor results

---

## Analytical Quality Gates (QA1-QA4)

For analytical tasks (Analytical Pipeline, D-119), code-oriented Q1-Q5 gates are replaced by QA1-QA4. Full specification in [analytical-pipeline.md](../architecture/analytical-pipeline.md#analytical-quality-gates).

| Gate | Focus | CS Methods Referenced |
|------|-------|---------------------|
| **QA1: Scope Completeness** | All questions answered, structural coverage, no blind spots | CS-2 (graph coverage) |
| **QA2: Evidence Quality** | Hypothesis-evidence-verdict format, concrete citations, calibrated confidence | CS-3 (hypothesis-driven) |
| **QA3: Actionability** | Concrete recommendations, justified priorities, effort/impact estimates | — |
| **QA4: Analytical Rigor** | Competing explanations, no confirmation bias, cross-validation, convergence | CS-1 (fixpoint), CS-4 (abduction) |
