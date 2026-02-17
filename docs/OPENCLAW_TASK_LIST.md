# OpenClaw Feature Adoption Task List

Last updated: 2026-02-17

This tracks the OpenClaw-inspired features Bzzbe should add, in implementation order.

## Status legend

- `[ ]` not started
- `[-]` in progress
- `[x]` complete

## Wave 1 (core chat reliability + control)

1. `[x]` Session context compaction (`/compact` + auto-compaction guard)
   - Add manual slash command: `/compact [optional focus]`.
   - Add automatic compaction when chat context approaches model window.
   - Preserve recent turns and replace older turns with a compact summary block.
   - Add tests for slash behavior and context reduction.

2. `[x]` Model failover and retry ladder
   - Add fallback model chain when runtime/model errors are retryable.
   - Add cooldown tracking for recently failed models.
   - Add per-conversation current model state and fallback events in logs.
   - Add tests for failover order and cooldown handling.

3. `[x]` Layered tool policy pipeline
   - Move from single profile gate to layered policy evaluation.
   - Support global + per-task + per-session policy merge.
   - Add explain/debug output for “why action was blocked”.
   - Add policy pipeline unit tests.

## Wave 2 (safe capability expansion)

4. `[x]` Risky-action approval workflow
   - Add explicit approval prompts for high-risk actions.
   - Add “allow once / always allow / deny” outcomes.
   - Persist per-user allowlist rules locally.
   - Add tests for approval and timeout behavior.

5. `[x]` Sandbox hardening for local tool execution
   - Add strict path/network guardrails before tool execution.
   - Block unsafe mounts, host networking, and disallowed escalation.
   - Add diagnostics for sandbox configuration issues.
   - Add hardening tests.

6. `[ ]` Skills system
   - Add skill directories with precedence: workspace > user > bundled.
   - Add metadata-based gating (required binaries/env/config).
   - Add settings UI for enabling/disabling installed skills.
   - Add tests for precedence and gating.

## Wave 3 (automation + advanced orchestration)

7. `[ ]` Scheduled jobs (cron-style)
   - Add persisted scheduler jobs for local tasks.
   - Support one-shot and recurring schedules.
   - Add basic run logs and retry behavior.
   - Add tests for scheduling and persistence.

8. `[ ]` Sub-agent orchestration
   - Add background child runs with isolated context.
   - Add run registry, status, and cancel controls.
   - Return child outputs back into parent conversation safely.
   - Add tests for lifecycle and cancellation.

9. `[ ]` Memory upgrade beyond `MEMORY.md`
   - Add layered memory (`MEMORY.md` + dated notes).
   - Add local search over memory snippets.
   - Add memory scoping controls (private vs shared contexts).
   - Add tests for memory indexing/search behavior.
