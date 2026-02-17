# Bzzbe

Bzzbe is an open-source macOS app (Apple Silicon only) that installs and runs local AI models with a GUI and task workflows. The goal is a privacy-first local assistant that auto-configures an on-device stack based on each Mac's hardware profile.

## Product goals

- **Apple Silicon focused**: support M-series Macs only for predictable performance and simpler distribution.
- **Automatic setup**: one-click provisioning of model runtime, model weights, and helper tools.
- **Hardware-aware model selection**: choose an appropriate default model/quantization based on RAM, CPU/GPU cores, and available disk.
- **Agent workflows**: offer reusable, multi-step tasks for coding, writing, research, and local automation.
- **Open source foundation**: open source models + open source runtime + transparent packaging.
- **Mac App Store distribution**: downloadable for free with in-app onboarding and local-first defaults.

## Current stack

- **UI**: SwiftUI + AppKit interop where required.
- **Inference runtime**: local Ollama-compatible service process.
- **Model sources**: runtime registry pulls and direct provider artifacts (currently Hugging Face entries in catalog).
- **Persistence**: SQLite for chat history + structured JSON files in Application Support.
- **Task engine**: reusable local task templates (`CoreAgents`).

## Core user flow

1. User launches app on Apple Silicon Mac.
2. App profiles hardware and recommends a model profile (Small/Balanced/High Quality).
3. User can accept recommendation or override model choice.
4. On install, app ensures runtime is available, downloads model artifact, verifies checksum when configured, and imports into runtime.
5. On completion, user lands in Chat, Tasks, Models, and Settings routes.

## Local development

- Build:
  - `swift build`
- Test:
  - `swift test`
- Open in Xcode:
  - `open Package.swift`
  - Run the `BzzbeApp` scheme.

## Repo contents

- `docs/ARCHITECTURE.md`: system design and module boundaries.
- `docs/IMPLEMENTATION_PLAN.md`: build phases and milestones.
- `docs/AGENT_TASKS.md`: starter list of built-in agent workflows.
- `docs/PHASE1_BACKLOG.md`: execution-ready backlog with acceptance criteria.
- `docs/JOB_LIST.md`: detailed assignable jobs with dependencies and DoD.
- `docs/MODEL_RESEARCH.md`: Apple Silicon model-family research and v1 tier recommendations.
- `docs/TASK_STATUS_REVIEW.md`: checkpoint review of completed vs remaining jobs and next execution order.

## Current implementation status

- ✅ JOB-001 complete: Swift package scaffold with `BzzbeApp`, core modules, tests, and CI workflow.
- ✅ JOB-002 complete: SwiftUI app shell with Chat/Tasks/Models/Settings navigation placeholders.
- ✅ JOB-003 complete: launch-time Apple Silicon gate with unsupported-Mac screen.
- ✅ JOB-004 complete: hardware capability profiler with settings debug surface.
- ✅ JOB-005 complete: hardened inference abstraction with cancellable streaming request model.
- ✅ JOB-006 complete: chat route now supports prompt send, streaming response rendering, stop, and retry controls.
- ✅ JOB-011 complete: SQLite conversation storage with CRUD operations, test coverage, and chat persistence/restore wiring.
- ✅ JOB-007 complete: first-run onboarding flow with hardware-aware recommendation, install progress, and failure/retry states.
- ✅ JOB-008 complete: resumable artifact download manager with progress stream and installer integration.
- ✅ JOB-009 complete: SHA-256 artifact verification enforced before install completion with mismatch handling and tests.
- ✅ JOB-013 complete: local runtime streaming client integrated via `InferenceClient` with protocol-level tests and chat wired to real backend.
- ✅ JOB-010 complete: installed model metadata now persists locally after verified setup.
- ✅ JOB-012 complete: chat now includes conversation history sidebar with restore/select/delete flows plus view model tests.
- ✅ JOB-014 complete: settings now expose local-first consent messaging with telemetry/diagnostics opt-in controls defaulting to off.
- ✅ JOB-015 complete: installer/model action events are now recorded, visible in Settings, and exportable as text.
- 🟡 JOB-016 in progress: benchmark harness now emits host metadata + runtime-process RSS with alpha-01 baseline report; real runtime/two-tier capture remains open in defect triage.
- ✅ JOB-017 complete: chat recovery now surfaces actionable offline/missing-model guidance with one-click retry or setup rerun.
- ✅ Runtime bootstrap hardening: app now starts runtime headlessly from bundled CLI path before fallback app launch.
- ✅ Provider import hardening: provider artifacts are uploaded as runtime blobs and then imported via `/api/create` `files` mapping.
- ✅ Retry UX hardening: setup retries now reuse previously downloaded provider artifact files when present.
- ✅ Personal memory context: optional local `MEMORY.md` can now be edited in Settings and injected into chat as system context.
- ✅ Chat slash commands: local quick controls for presets/tuning, new conversation, and context compaction (`/help` for command list).
- ✅ Chat model failover: runtime/model failures can now trigger automatic fallback to an alternate local model with cooldown-based retry behavior.
- ✅ Tool permission profiles: `Read-only`/`Local files`/`Advanced` profiles with layered policy evaluation and task-level enforcement.
- ✅ Risky-action approvals: task runs requiring risky access now require explicit `Allow Once`, `Always Allow`, or `Deny`, with local persistence for always-allow decisions.
- ✅ Sandbox hardening: risky task runs now pass local sandbox guardrails for path/network/escalation/mount checks, with diagnostics shown when policy config is unsafe.
- ✅ Skills system: Bzzbe now discovers skills from workspace/user/bundled directories with precedence rules, metadata gating checks, and settings-level enable/disable controls.
- ✅ Scheduled jobs: one-shot and recurring task jobs now persist locally with run logs, retry behavior, and task-workspace controls to run due jobs.
- ✅ Sub-agent orchestration: background child task runs now have lifecycle tracking, cancel controls, and safe output handoff back into the main task input.

## Troubleshooting

- `Could not connect to the server` (`127.0.0.1:11434`):
  - Runtime is not reachable. In onboarding, use **Fix Setup Automatically** (now forces runtime restart) or **Retry** after runtime is started.
- `The network connection was lost` during setup validation:
  - Setup now retries transient runtime startup drops automatically before surfacing a failure.
- `The network connection was lost` during model import/upload (`/api/blobs/...`):
  - Setup now retries runtime import automatically and attempts to restart the local runtime before failing.
  - If provider import remains unstable, setup now falls back to runtime registry pull for the same model ID.
- `Setup failed: Local runtime returned status 400 while importing model.`:
  - Pull latest `main` and retry. Recent fixes switched provider imports to the Ollama-compatible blob + `files` flow.
- Long re-download after failed import:
  - Latest setup flow reuses an already-downloaded provider artifact on retry.
- `Cannot index window tabs due to missing main bundle identifier` (Xcode console):
  - Common warning when running as an SPM executable context; not the primary runtime failure signal.

## Early roadmap summary

- Build a functional local chat MVP first.
- Add robust installer + hardware detection.
- Add agent task catalog and safe local tool execution.
- Harden sandboxing/signing/notarization for App Store compliance.

## Notes on App Store strategy

Because this app provisions AI assets and executes local tools, compliance should be validated early against latest App Store Review Guidelines. Keep first release narrow in scope with clear user consent for any local automation permissions.
