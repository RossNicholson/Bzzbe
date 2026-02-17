# Bzzbe Roadmap (Open Work)

Last updated: 2026-02-17

This document tracks forward-looking work only.

## Near-term priorities

1. Performance validation
   - Capture real runtime metrics on at least two Apple Silicon tiers.
   - Update `docs/reports/alpha-01.md` with reproducible results.
   - Keep `docs/reports/ALPHA_PERF_RUNBOOK.md` aligned with actual benchmark procedure.

2. Installer and runtime resilience polish
   - Reduce setup failure paths that still require manual user retry.
   - Improve UX messaging for runtime startup/restart edge cases.
   - Add additional diagnostics where runtime connectivity is unstable.

3. Task and automation UX hardening
   - Improve scheduler/sub-agent clarity in the Tasks view.
   - Refine risk-approval and sandbox messaging for non-technical users.
   - Add end-to-end QA scenarios for task execution lifecycle flows.

4. Distribution readiness
   - Continue sandbox/signing/notarization hardening for macOS distribution.
   - Keep privacy defaults and permission prompts aligned with release policy.
   - Prepare release checklist for public beta packaging.

## Quality gates

- `swift test` must pass on every release candidate.
- Setup flow should complete from a clean install without terminal steps.
- Chat and task flows must be functional without data loss across relaunch.
- Public docs should avoid internal/completed task tracking and competitor planning notes.
