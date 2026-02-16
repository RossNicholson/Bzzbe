# Bzzbe Architecture (Draft)

## 1) Platform constraints

- Target: macOS 14+ on **Apple Silicon only**.
- Distribution: Mac App Store (free app).
- Primary principle: local-first inference and storage.

## 2) High-level components

### A. App Shell (SwiftUI)

Responsibilities:
- Onboarding, installation progress, chat UI, task catalog, settings.
- Hardware and storage status display.
- Permission prompts and trust/consent controls.

### B. Hardware Profiler

Responsibilities:
- Detect SoC tier (M1/M2/M3 family and variants where possible).
- Determine total memory, free disk, thermal/power mode hints.
- Produce a normalized capability profile for model recommendation.

Example capability profile:

```json
{
  "chip": "M2",
  "memoryGB": 16,
  "freeDiskGB": 85,
  "recommendedTier": "balanced",
  "maxContext": 8192
}
```

### C. Installer + Package Manager

Responsibilities:
- Download and verify runtime binaries/model artifacts.
- Resume interrupted downloads.
- Verify checksums/signatures for all artifacts.
- Install/update/remove model packages.

Suggested package metadata fields:
- model id
- parameter size
- quantization
- min memory requirement
- disk footprint
- license URL
- checksum

### D. Local Inference Service

Responsibilities:
- Run model inference through local backend (e.g., llama.cpp wrapper).
- Expose a local IPC interface to app shell.
- Stream tokens to UI.
- Load/unload models on demand.

### E. Agent Orchestrator

Responsibilities:
- Execute structured multi-step task templates.
- Manage tool execution policy.
- Track task state, intermediate outputs, and retries.

### F. Tool Sandbox Layer

Responsibilities:
- Gate all local tool actions behind explicit user consent.
- Restrict file access to approved directories.
- Log tool calls for transparency.

### G. Storage Layer

Responsibilities:
- Conversation history.
- Installed models index.
- Task templates and run history.
- Telemetry toggles (default privacy-first/off unless required).

## 3) Suggested module boundaries

- `BzzbeApp` (SwiftUI app target)
- `CoreHardware`
- `CoreInstaller`
- `CoreInference`
- `CoreAgents`
- `CoreStorage`
- `CoreSecurity`

Using Swift packages for shared logic helps testability and future CLI/service reuse.

## 4) Model recommendation logic (v1 heuristic)

Inputs:
- total RAM
- free disk
- performance core count
- target use case (chat only vs advanced agents)

Output:
- model family + quantization + default context window

Example policy:
- 8 GB RAM -> 3B–7B quantized profile
- 16 GB RAM -> 7B–14B quantized profile
- 24+ GB RAM -> higher quality profile with larger context

## 5) Security and privacy baseline

- No cloud dependency required for default behavior.
- All model inference on device.
- User-controlled data export/delete.
- Signed artifacts with checksum verification.
- Verbose action log for agent tool use.

## 6) App Store risk areas to manage early

- Downloading executable/runtime components post-install.
- Running local automation and shell-like tools.
- Handling user files outside app container.

Mitigations:
- Keep v1 capabilities explicit and constrained.
- Use user-selected folders (security-scoped bookmarks).
- Provide clear disclosures and user controls.
