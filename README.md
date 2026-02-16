# Bzzbe

Bzzbe is an open-source macOS app (Apple Silicon only) that installs and runs local AI models with a polished GUI and agent-like workflows. The goal is to provide a free, privacy-first alternative to paid online assistants by auto-configuring an on-device stack based on each Mac's hardware profile.

## Product goals

- **Apple Silicon focused**: support M-series Macs only for predictable performance and simpler distribution.
- **Automatic setup**: one-click provisioning of model runtime, model weights, and helper tools.
- **Hardware-aware model selection**: choose an appropriate default model/quantization based on RAM, CPU/GPU cores, and available disk.
- **Agent workflows**: offer reusable, multi-step tasks for coding, writing, research, and local automation.
- **Open source foundation**: open source models + open source runtime + transparent packaging.
- **Mac App Store distribution**: downloadable for free with in-app onboarding and local-first defaults.

## Proposed stack (v1)

- **UI**: SwiftUI + AppKit interop where required.
- **Inference runtime**: `llama.cpp`-based runtime via local service process.
- **Model sources**: open models with permissive licenses (e.g., Qwen, Llama variants where license permits).
- **Persistence**: SQLite + structured files in app support folder.
- **Task engine**: tool-calling style orchestration for “agent” task templates.

## Core user flow

1. Install from Mac App Store.
2. On first launch, app verifies Apple Silicon and checks available resources.
3. App recommends a model profile (Small/Balanced/High Quality).
4. User clicks **Install**.
5. Runtime + model package download and setup runs automatically.
6. User lands in chat + task catalog and can run agent workflows.

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
- 🔜 Next: JOB-011 conversation storage schema + repository.

## Early roadmap summary

- Build a functional local chat MVP first.
- Add robust installer + hardware detection.
- Add agent task catalog and safe local tool execution.
- Harden sandboxing/signing/notarization for App Store compliance.

## Notes on App Store strategy

Because this app provisions AI assets and executes local tools, compliance should be validated early against latest App Store Review Guidelines. Keep first release narrow in scope with clear user consent for any local automation permissions.
