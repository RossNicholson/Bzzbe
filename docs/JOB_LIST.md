# Bzzbe Detailed Job List (Phase 1 Execution)

This job list turns the Phase 1 backlog into assignable work items with sequencing, dependencies, and exit criteria.

## Planning assumptions

- Team: 2-4 engineers (macOS app, platform/runtime, QA/support).
- Delivery target: internal alpha first, then external beta.
- Priority scale:
  - **P0**: required for alpha
  - **P1**: important for alpha quality
  - **P2**: can slip if needed

---

## Current progress

- [x] JOB-001 — Initialize Xcode workspace and modules (completed in repository scaffold).
- [x] JOB-002 — Build app shell + primary navigation (SwiftUI shell + placeholders complete).
- [x] JOB-003 — Apple Silicon eligibility gate (launch-time gate + unsupported screen complete).
- [x] JOB-004 — Hardware capability profiler (live profile values + settings debug display complete).
- [x] JOB-005 — Define inference abstraction (request/event protocol + cancellable mock streaming + tests complete).
- [x] JOB-006 — Implement streaming chat UI (composer, streaming token render, stop/retry controls complete against mock client).
- [x] JOB-007 — Add first-run installer UX (intro/recommendation/progress/failure+retry flow wired as default first-launch path).
- [x] JOB-008 — Download manager with resume (resumable partial-file downloader + progress events + cancellation/resume tests integrated with installer UI).
- [x] JOB-009 — Checksum and artifact verification (SHA-256 verifier integrated in installer completion path with failing mismatch tests).
- [x] JOB-011 — Conversation storage schema + repository (SQLite-backed conversation/message CRUD with tests; chat persistence restored on launch).

---

## Job board

### JOB-001 — Initialize Xcode workspace and modules

- **Priority**: P0
- **Owner**: App engineer
- **Estimate**: 1-2 days
- **Dependencies**: none
- **Description**:
  - Create `BzzbeApp` target and Swift package modules:
    - `CoreHardware`
    - `CoreInference`
    - `CoreStorage`
    - `CoreInstaller` (stub)
    - `CoreAgents` (stub)
- **Definition of done**:
  - Project builds cleanly in Debug.
  - Modules are imported by app target.
  - CI build script runs successfully.

### JOB-002 — Build app shell + primary navigation

- **Priority**: P0
- **Owner**: App engineer
- **Estimate**: 1-2 days
- **Dependencies**: JOB-001
- **Description**:
  - Add sidebar routes for Chat, Tasks, Models, Settings.
  - Implement base `AppState` container.
- **Definition of done**:
  - Navigation is functional via mouse + keyboard.
  - Placeholder views render without crashes.

### JOB-003 — Apple Silicon eligibility gate

- **Priority**: P0
- **Owner**: Platform engineer
- **Estimate**: 0.5-1 day
- **Dependencies**: JOB-001
- **Description**:
  - Detect unsupported Intel devices and show blocked screen.
- **Definition of done**:
  - ARM64 machines proceed normally.
  - Intel path shows friendly guidance and exits safely.

### JOB-004 — Hardware capability profiler

- **Priority**: P0
- **Owner**: Platform engineer
- **Estimate**: 1-2 days
- **Dependencies**: JOB-003
- **Description**:
  - Collect total memory, free disk, and core counts.
  - Emit normalized `CapabilityProfile` to app state.
- **Definition of done**:
  - Profile appears in Settings debug view.
  - Unit tests cover normalization and edge cases.

### JOB-005 — Define inference abstraction

- **Priority**: P0
- **Owner**: Runtime engineer
- **Estimate**: 1 day
- **Dependencies**: JOB-001
- **Description**:
  - Introduce protocol for loading model, streaming tokens, and cancellation.
- **Definition of done**:
  - Chat UI compiles against protocol only.
  - Mock implementation available for local UI development.

### JOB-006 — Implement streaming chat UI

- **Priority**: P0
- **Owner**: App engineer
- **Estimate**: 2-3 days
- **Dependencies**: JOB-002, JOB-005
- **Description**:
  - Build composer, send/stop controls, token stream rendering, and retry UX.
- **Definition of done**:
  - Prompt -> streaming response -> stop path works.
  - Error states provide actionable next steps.

### JOB-007 — Add first-run installer UX

- **Priority**: P0
- **Owner**: App engineer
- **Estimate**: 2 days
- **Dependencies**: JOB-002, JOB-004
- **Description**:
  - Build onboarding screens showing recommended model tier and install progress.
- **Definition of done**:
  - Fresh install can start setup from GUI only.
  - Failure and retry states are implemented.

### JOB-008 — Download manager with resume

- **Priority**: P0
- **Owner**: Platform engineer
- **Estimate**: 2-3 days
- **Dependencies**: JOB-007
- **Description**:
  - Download runtime/model artifacts with resumable transfers.
- **Definition of done**:
  - Interrupted downloads resume correctly.
  - Progress events update installer UI.

### JOB-009 — Checksum and artifact verification

- **Priority**: P0
- **Owner**: Platform engineer
- **Estimate**: 1 day
- **Dependencies**: JOB-008
- **Description**:
  - Validate hash for downloaded artifacts before activation.
- **Definition of done**:
  - Invalid artifacts are rejected.
  - Clear user-facing error message is shown.

### JOB-010 — Persist installed model metadata

- **Priority**: P1
- **Owner**: Platform engineer
- **Estimate**: 1 day
- **Dependencies**: JOB-009
- **Description**:
  - Record installed model ID, tier, path, version, and checksum.
- **Definition of done**:
  - App restarts preserve installed state correctly.

### JOB-011 — Conversation storage schema + repository

- **Priority**: P0
- **Owner**: Data/app engineer
- **Estimate**: 2 days
- **Dependencies**: JOB-001
- **Description**:
  - Add SQLite schema and repository methods for conversations/messages.
- **Definition of done**:
  - Create/read/update/delete conversation flows are tested.

### JOB-012 — Conversation list and history UX

- **Priority**: P1
- **Owner**: App engineer
- **Estimate**: 1-2 days
- **Dependencies**: JOB-006, JOB-011
- **Description**:
  - Add sidebar/history panel for past conversations and delete action.
- **Definition of done**:
  - Conversations restore correctly after relaunch.
  - Delete action removes DB records and UI entries.

### JOB-013 — Runtime integration (real local backend)

- **Priority**: P0
- **Owner**: Runtime engineer
- **Estimate**: 2-4 days
- **Dependencies**: JOB-005, JOB-008, JOB-009
- **Description**:
  - Replace mock client with local runtime process integration.
- **Definition of done**:
  - End-to-end prompt execution works with installed model.
  - Cancel path safely terminates active generation.

### JOB-014 — Privacy defaults and consent messaging

- **Priority**: P1
- **Owner**: App engineer
- **Estimate**: 1 day
- **Dependencies**: JOB-002
- **Description**:
  - Add local-first disclosure and telemetry-off-by-default controls.
- **Definition of done**:
  - Settings expose privacy controls.
  - Default install does not enable telemetry automatically.

### JOB-015 — Installer/model action log

- **Priority**: P1
- **Owner**: Platform engineer
- **Estimate**: 1 day
- **Dependencies**: JOB-008
- **Description**:
  - Log install/update/verify events for debugging and transparency.
- **Definition of done**:
  - Log is viewable in Settings and exportable as text.

### JOB-016 — Alpha performance harness + report

- **Priority**: P1
- **Owner**: QA engineer
- **Estimate**: 1-2 days
- **Dependencies**: JOB-013
- **Description**:
  - Measure first-token latency, tokens/sec, and peak memory on two Apple Silicon tiers.
- **Definition of done**:
  - Report committed under `docs/reports/alpha-01.md`.
  - Top defects triaged by severity.

### JOB-017 — Failure-recovery hardening

- **Priority**: P2
- **Owner**: Cross-functional
- **Estimate**: 1-2 days
- **Dependencies**: JOB-006, JOB-008, JOB-013
- **Description**:
  - Improve recoverability for offline launch, missing model, and failed runtime boots.
- **Definition of done**:
  - No critical crash paths in common failure scenarios.
  - Recovery hints shown with one-click retry where possible.

---

## Suggested execution waves

### Wave 1 (alpha skeleton)
- JOB-001, JOB-002, JOB-003, JOB-005, JOB-006, JOB-011

### Wave 2 (installer + runtime)
- JOB-004, JOB-007, JOB-008, JOB-009, JOB-013

### Wave 3 (quality + readiness)
- JOB-010, JOB-012, JOB-014, JOB-015, JOB-016, JOB-017

---

## Alpha exit checklist

- [ ] Apple Silicon gating is reliable.
- [ ] Local chat streams and can be canceled.
- [ ] First-run installer completes without Terminal usage.
- [ ] Artifact verification is enforced.
- [ ] Conversations persist between launches.
- [ ] Privacy defaults are user-friendly and explicit.
- [ ] Performance report and defect triage are complete.
