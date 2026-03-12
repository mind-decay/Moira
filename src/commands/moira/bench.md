---
name: moira:bench
description: Run Moira behavioral tests
argument-hint: "[tier1|tier2|tier3|report|compare]"
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

## Budget Guards

- Tier 2: max 5 tests, warn at 4
- Tier 3: max 30 tests, warn at 20
- Token-based guards deferred to Phase 7

## Phase 6 Limitations

- No LLM-judge scores (quality_scores: null)
- Automated checks only (compile, lint, test pass/fail)
- Statistical analysis deferred to Phase 10+
