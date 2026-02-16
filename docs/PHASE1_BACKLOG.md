# Phase 1 Build Backlog (Execution-Ready)

This backlog translates the current strategy docs into implementation-ready work for a local chat MVP.

## Sprint goal

Deliver an internal alpha that can:
1. run on Apple Silicon Macs,
2. complete first-run local model setup,
3. provide streaming local chat,
4. persist conversation history.

## Epic A — App foundation

### A1. Create Xcode workspace and targets

**Description**
Set up the app target and initial module boundaries that align with the architecture.

**Tasks**
- Create `BzzbeApp` macOS target (SwiftUI lifecycle).
- Add Swift package modules:
  - `CoreHardware`
  - `CoreInference`
  - `CoreStorage`
  - `CoreInstaller` (stub)
  - `CoreAgents` (stub)
- Add a shared `DesignSystem` package for typography/colors/components.

**Acceptance criteria**
- App launches to a basic shell view.
- All modules compile and are imported into app target.
- CI build can compile app + packages without tests.

### A2. App shell and navigation

**Description**
Create the initial user shell used by all future features.

**Tasks**
- Implement side navigation:
  - Chat
  - Tasks (placeholder)
  - Models (placeholder)
  - Settings
- Add global app state container (`AppStore`/`Observable` model).

**Acceptance criteria**
- Navigation works with keyboard + mouse.
- Placeholders are clearly marked as “Coming in next phase”.

## Epic B — Hardware profiling and gating

### B1. Apple Silicon eligibility check

**Description**
Prevent unsupported Intel Macs from proceeding.

**Tasks**
- Detect architecture at launch.
- If not ARM64, show unsupported message and block installer/chat.

**Acceptance criteria**
- ARM64 devices proceed.
- Intel devices receive a clear non-crashing blocked state.

### B2. Capability profile service

**Description**
Collect local hardware signals used for model recommendation.

**Tasks**
- Gather:
  - total unified memory (GB)
  - available disk (GB)
  - CPU core counts
- Emit `CapabilityProfile` model.

**Acceptance criteria**
- Profile object is available in app state and settings debug section.
- Unit tests cover profile parsing and value normalization.

## Epic C — Local inference MVP

### C1. Inference adapter protocol

**Description**
Create a swappable interface to support runtime changes without UI rewrites.

**Tasks**
- Define `InferenceClient` protocol with:
  - `loadModel(...)`
  - `streamCompletion(...)`
  - `cancel(...)`
- Add first implementation targeting local runtime process.

**Acceptance criteria**
- Chat UI depends only on protocol, not concrete runtime.
- Streaming callback includes token chunks and completion events.

### C2. Chat feature (streaming)

**Description**
Implement the first working chat loop.

**Tasks**
- Prompt input composer with send/stop controls.
- Stream model output token-by-token.
- Add retry on transient inference start failure.

**Acceptance criteria**
- User can send prompt and receive streaming response.
- User can cancel generation safely.
- Errors surface readable messages and recovery actions.

## Epic D — Model install flow (minimum viable)

### D1. First-run installer UI

**Description**
Guide user through a one-click setup flow.

**Tasks**
- Intro screen describing local model setup.
- “Recommended profile” card based on hardware tier.
- Install progress view with status and percent.

**Acceptance criteria**
- User can complete setup from fresh install without Terminal.
- Failure states include retry and diagnostics copy button.

### D2. Artifact download and verification

**Description**
Safely fetch runtime/model files.

**Tasks**
- Download with resumable transfer support.
- Validate checksums after download.
- Persist installed model metadata.

**Acceptance criteria**
- Interrupted download can resume.
- Corrupt artifact is rejected with clear error.

## Epic E — Local data persistence

### E1. Conversation storage

**Description**
Save and restore local conversations.

**Tasks**
- Define conversation/message schema.
- Persist messages in SQLite.
- Add conversation list and delete action.

**Acceptance criteria**
- Conversations persist across app restarts.
- Deleting a conversation removes it from UI and storage.

## Epic F — QA, instrumentation, and release prep

### F1. Internal alpha test pass

**Description**
Run focused validation on representative hardware tiers.

**Tasks**
- Validate on at least:
  - base memory Apple Silicon machine
  - mid/high memory Apple Silicon machine
- Record:
  - first token latency
  - tokens/sec
  - peak memory

**Acceptance criteria**
- Performance report captured in `/docs/reports/alpha-01.md`.
- Top 10 defects triaged with severity.

### F2. Privacy and consent baseline

**Description**
Establish default-safe behavior for first release.

**Tasks**
- Telemetry default set to off.
- Explicit disclosure that inference is local by default.
- Add a simple action log for installer and model operations.

**Acceptance criteria**
- Fresh install shows privacy defaults clearly.
- Settings includes data controls and log export.

---

## Suggested ticket order (first 15)

1. A1 Xcode workspace + modules
2. A2 App shell navigation
3. B1 Apple Silicon gate
4. B2 Capability profile service
5. C1 Inference protocol + mock client
6. C2 Chat UI with streaming mock
7. D1 First-run installer screens
8. D2 Download manager skeleton
9. D2 Checksum verifier
10. E1 SQLite schema + repository layer
11. E1 Conversation list UI
12. C2 Runtime integration (real client)
13. D2 Resume download behavior
14. F2 Privacy defaults/settings
15. F1 Alpha report template + performance harness

## Definition of done for Phase 1

- Internal alpha can be installed and used on Apple Silicon without Terminal.
- Local chat works with streaming and cancel.
- Conversations persist locally.
- Basic installer can fetch + verify one recommended model profile.
- Known risks and App Store blockers documented with mitigation owners.
