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
- `docs/IMPLEMENTATION_PLAN.md`: active roadmap (open work only).
- `docs/AGENT_TASKS.md`: starter list of built-in agent workflows.
- `docs/MODEL_RESEARCH.md`: Apple Silicon model-family research and v1 tier recommendations.
- `docs/reports/ALPHA_PERF_RUNBOOK.md`: perf run checklist for alpha measurements.
- `docs/reports/alpha-01.md`: current benchmark report snapshot.

## Current capabilities

- First-run onboarding with hardware-aware model recommendation and manual model override.
- Local runtime bootstrap/recovery flow with provider import plus runtime-registry fallback.
- Streaming chat with stop/retry controls and persisted conversation history.
- Chat slash commands for presets, tuning controls, and context compaction.
- Automatic model failover ladder for retryable runtime/model failures.
- Task workspace with layered permission policy evaluation and clear block reasons.
- Explicit risky-action approval flow (`Allow Once`, `Always Allow`, `Deny`).
- Sandbox guardrails for risky task input (path/network/escalation/mount checks).
- Local skills discovery with precedence (workspace > user > bundled) and gating checks.
- Persisted one-shot/recurring scheduled jobs with run logs and retry behavior.
- Sub-agent background runs with lifecycle tracking, cancellation, and output handoff.
- Layered local memory (`MEMORY.md` + dated notes) with scoped note search.
- Local-first privacy defaults and installer/model action logging in Settings.

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

## Roadmap

- Active roadmap items are tracked in `docs/IMPLEMENTATION_PLAN.md`.

## Notes on App Store strategy

Because this app provisions AI assets and executes local tools, compliance should be validated early against latest App Store Review Guidelines. Keep first release narrow in scope with clear user consent for any local automation permissions.
