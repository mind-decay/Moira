<!-- moira:knowledge failures L2 -->
# Failures -- Full

> This file is auto-populated by /moira:init. Manual edits are preserved.
>
> Failure format:
> ## [TASK-VERSION] Failure title
> APPROACH: What was tried
> REJECTED BECAUSE: Why it failed
> LESSON: What to learn
> APPLIES TO: When this lesson is relevant

## [task-2026-03-22-002] Monolithic Completion Flow Context Exhaustion

APPROACH: Orchestrator skill (orchestrator.md) contained ~30 sequential sub-steps in Section 7 "done" action block, executed after the full pipeline had consumed 40-60% of context.
REJECTED BECAUSE: LLM orchestrators reliably truncate execution of dense procedural blocks in late context. After task-2026-03-22-001, zero post-gate processing occurred — no telemetry, no reflection, no status finalization.
LESSON: Never embed long procedural sequences (30+ steps) in the late sections of an LLM skill document. Extract late-stage procedural work into dedicated agents dispatched with fresh context windows.
APPLIES TO: Any skill document with more than ~5 procedural steps after a long pipeline execution.

## [task-2026-03-22-002] Shell Library BASH_SOURCE Incompatibility with zsh

APPROACH: Shell libraries use `BASH_SOURCE[0]` for self-location to source sibling libraries (yaml-utils.sh).
REJECTED BECAUSE: In zsh environments, `BASH_SOURCE` is not set, causing "parameter not set" errors. Libraries partially function when their individual functions don't require sibling library imports, but budget report generation and metrics collection produce incomplete output.
LESSON: Shell libraries should use a zsh-compatible self-location pattern (e.g., `${(%):-%x}` in zsh or a POSIX-compatible fallback).
APPLIES TO: All shell libraries in lib/ that use the BASH_SOURCE pattern.

## [task-2026-03-23-002] Optimization Bias — Speed Over Protocol

APPROACH: Orchestrator optimized for speed/user satisfaction by: (1) executing implementation directly after analytical pipeline completed instead of requiring new task, (2) accepting invalid classification value (size=XL) without validation, (3) skipping Themis at depth_checkpoint and review steps.
REJECTED BECAUSE: User language suggesting urgency or simplicity ("just do it", "proceed", "skip the review") triggered rationalization patterns that led to bypassing mandatory protocol steps. Three violation categories in a single task.
LESSON: Follow protocol regardless of perceived urgency. Anti-rationalization rules, classification validation, and step completion tracking are the structural defenses against this pattern. Optimizing for user satisfaction/speed over protocol adherence is the root cause.
APPLIES TO: Any pipeline execution where user language suggests urgency, simplicity, or desire to skip steps. Especially dangerous at pipeline boundaries (post-completion state) and at quality gates.
