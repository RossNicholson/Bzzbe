# OpenClaw-Inspired Feature Adoption (2026-02-17)

This note tracks which OpenClaw-style product features we can adopt in Bzzbe and whether source reuse is license-safe.

## Source and licensing check

- OpenClaw official repo: https://github.com/openclaw/openclaw
- OpenClaw license: MIT (`LICENSE` in repo root)
- Official docs index: https://docs.openclaw.ai/

MIT licensing permits code reuse with attribution and license preservation in copied files.

## OpenClaw features relevant to Bzzbe

1. Personal memory/context files.
2. Tool + plugin ecosystem (MCP-style integrations).
3. Safety controls for what the assistant can do.
4. Slash-command style productivity shortcuts.

## Bzzbe adoption status

### Implemented in this change

- Personal memory notebook (`MEMORY.md`) in local app data.
- Settings UI to enable/disable memory context and edit/save/reload it.
- Chat injection of memory as a bounded system-context block when enabled.
- Slash commands in chat for fast local control:
  - `/help`, `/new`
  - `/preset <accurate|balanced|creative>`
  - `/temperature`, `/top-p`, `/top-k`, `/max-tokens`

### Good next candidates

1. Tool permission profiles (`Read-only`, `Local files`, `Advanced`) with explicit consent prompts.
2. Plugin/MCP connector surface in Settings.
3. Slash commands in chat/task input (`/summarize`, `/test`, `/rewrite`).

## Guardrails for borrowed code

- Only copy from permissive licensed repositories (MIT/Apache-2.0/BSD).
- Preserve original license headers for copied files.
- Record source repo + commit hash in PR notes or inline comments.
- Prefer borrowing small utilities/patterns rather than entire subsystems.
