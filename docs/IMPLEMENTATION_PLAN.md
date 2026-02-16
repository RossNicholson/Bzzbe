# Bzzbe Implementation Plan

## Phase 0 — Product definition (1-2 weeks)

- Define v1 scope and non-goals.
- Finalize compatible open-source models and license checks.
- Decide primary runtime approach (embedded vs helper process).
- Validate App Store review constraints with a minimal prototype.

Deliverables:
- Product requirements doc.
- App architecture decision record.
- Compliance checklist.

## Phase 1 — Local chat MVP (2-4 weeks)

- Build SwiftUI shell with chat screen and settings.
- Integrate local inference backend with token streaming.
- Support one default model profile and basic conversation persistence.

Deliverables:
- Internal alpha for local chat.
- Baseline performance metrics on M1/M2/M3 devices.

## Phase 2 — Smart installer (2-3 weeks)

- Implement hardware profiler and recommendation engine.
- Build robust download/install pipeline with resume + checksum validation.
- Add model manager UI (install/update/remove).

Deliverables:
- One-click setup flow.
- Stable installer behavior under network interruption.

## Phase 3 — Agent task framework (3-5 weeks)

- Introduce task templates with structured plans.
- Add limited tool interfaces (file organizer, summarizer, code helper).
- Add run history and execution audit log.

Deliverables:
- First set of user-facing agent tasks.
- Consent UI and policy controls for tool usage.

## Phase 4 — Polish, QA, and App Store submission (2-4 weeks)

- Improve onboarding, error states, and recovery flows.
- Performance tuning and memory stability pass.
- Complete signing, notarization, and App Store metadata.

Deliverables:
- Release candidate.
- App Store submission package.

## Suggested workstream ownership

- **Core app/UI**: SwiftUI + UX
- **Inference/runtime**: model serving + performance
- **Installer/platform**: packaging + updates + validation
- **Security/compliance**: sandbox, permissions, App Store policy

## Initial engineering checklist

1. Create Xcode project with modular package layout.
2. Add hardware profile service abstraction + unit tests.
3. Add backend adapter protocol for inference runtime.
4. Implement chat state store and local DB.
5. Build installer pipeline with resumable downloads.
6. Add telemetry toggle (off by default).
7. Add CI for lint + tests + basic static checks.
