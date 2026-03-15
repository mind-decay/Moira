---
name: moira:bench
description: Run Moira behavioral tests
argument-hint: "[tier1|tier2|tier3|report|compare|calibrate]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---

# /moira:bench — Behavioral Test Runner

Run behavioral bench tests against fixture projects.

## Usage

Parse the argument to determine subcommand:

- **No args**: Auto-detect tier from git diff. Scan changed files, suggest relevant tests, ask user.
- **`tier1`**: Run Tier 1 structural tests only (via `run-all.sh`).
- **`tier2 [filter]`**: Run targeted bench tests matching optional filter.
- **`tier3`**: Run all bench tests.
- **`report`**: Display latest bench results summary.
- **`compare <run1> <run2>`**: Compare two run directories (structural metrics only).
- **`calibrate`**: Run judge calibration against known examples.

## Execution

1. Source `~/.claude/moira/lib/bench.sh`
2. Route to appropriate function based on subcommand
3. Display formatted results

### Auto-detect (no args)

1. Run `git diff --name-only` to find changed files
2. Match changed files against fixture test case triggers
3. Suggest matching test cases
4. Ask user to confirm or select tier

### Report

1. Find latest `bench/results/run-*` directory
2. Call `moira_bench_report` on it
3. Display formatted summary

### Compare

1. Read `summary.yaml` from both run directories
2. Show side-by-side structural metrics
3. Highlight regressions (lower pass counts)

### Calibrate

1. Source `~/.claude/moira/lib/judge.sh`
2. Read calibration examples from `~/.claude/moira/tests/bench/calibration/`
3. For each example directory (good-implementation, mediocre-implementation, poor-implementation):
   a. Assemble judge prompt using `moira_judge_invoke` with the example directory and default rubric (`~/.claude/moira/tests/bench/rubrics/feature-implementation.yaml`)
   b. Dispatch Agent with the assembled prompt (model tier: default)
   c. Parse returned YAML evaluation
   d. Compare returned scores against `expected.yaml` (tolerance: ±1 per criterion)
4. Display per-example results with pass/fail
5. Display overall calibration status
6. If any example fails tolerance: warn "Judge may be unreliable — consider re-running after model update"

Recalibration triggers:
- Rubric version change
- Judge model change
- Every 20 bench runs

## Budget Guards

- Tier 2: max 5 tests, warn at 4
- Tier 3: max 30 tests, warn at 20
- Token-based guards deferred to Phase 7

## Notes

- Tier 2/3 tests include LLM-judge invocation after structural checks
- Judge prompts are prepared by `bench.sh` and dispatched by this command
- Quality scores are aggregated into run summaries and fed to statistical regression detection
