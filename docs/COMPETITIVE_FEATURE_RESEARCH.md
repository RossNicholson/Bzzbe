# Competitive Feature Research (2026-02-17)

This review compares Bzzbe to widely used local-first AI desktop/web apps and extracts practical features we can add next.

## Apps reviewed

- LM Studio
- Jan
- AnythingLLM
- GPT4All
- Open WebUI
- Ollama (runtime + import baseline)

## Feature matrix (high-level)

Legend: `Y` = clearly supported in product docs, `P` = partial/indirect support, `N` = not currently in Bzzbe.

| Capability | Bzzbe | LM Studio | Jan | AnythingLLM | GPT4All | Open WebUI |
| --- | --- | --- | --- | --- | --- | --- |
| Hardware-aware model recommendation | Y | P | P | P | P | P |
| In-app model download/management | Y | Y | Y | Y | Y | Y |
| Provider artifact import (GGUF/etc.) | Y | Y | Y | Y | Y | Y |
| Conversation history | Y | Y | Y | Y | Y | Y |
| Conversation folders/tags/archive UX | N | Y | P | Y | P | Y |
| Model parameter controls (temp/top-p/top-k/context) | P | Y | Y | Y | P | Y |
| Prompt/tool presets per model | N | Y | Y | Y | P | Y |
| Document chat / RAG with citations | N | Y | P | Y | Y | Y |
| Local OpenAI-compatible API server | N | Y | Y | Y | Y | Y |
| Tool calling / MCP integrations | N | Y | Y | Y | P | Y |
| Multi-user / roles / admin policies | N | N | N | Y | N | Y |

## What similar apps provide that users notice most

1. Document chat with source attribution.
2. Better chat lifecycle controls (folders, tags, export/import, archive).
3. Model tuning controls and easy presets.
4. Local API compatibility for external tools.
5. Tooling integrations (MCP/tool calling, workflows/agents).

## Bzzbe current strengths

- Smooth onboarding for Apple Silicon users.
- Hardware-aware recommendation and guided runtime setup.
- Local-first chat, tasks, and installer diagnostics.
- Runtime bootstrap and provider import hardening already in place.

## Bzzbe highest-value gaps

1. No document-grounded chat path yet.
2. No user-facing local API mode.
3. Limited chat/project organization features.
4. Limited model tuning and preset UX.
5. No tool/MCP integration surface.

## Proposed next feature sequence

### Now (next 2-4 jobs)

1. **Model controls and presets**
   - Presets: Accurate / Balanced / Creative.
   - Expose temperature, top-p, top-k, max output.
   - Save model defaults locally.

2. **Chat export + import**
   - Export active conversation to Markdown/JSON.
   - Import JSON conversation backup.

3. **Document chat v1**
   - Attach files, chunk locally, retrieve relevant passages.
   - Show cited snippets/filenames under each answer.

### Next (integration + productivity)

4. **Local OpenAI-compatible API mode**
   - Optional localhost endpoint for developer tooling.
   - Port + API key controls in Settings.

5. **Tool execution baseline**
   - Safe built-in tools first (calculator, file read in scoped directories, optional web fetch).
   - Explicit allow/deny prompts.

6. **Compare mode**
   - Run one prompt against two selected models and diff outputs.

### Later (platform expansion)

7. **Voice IO** (dictation + read-aloud).
8. **Workspace/project organization** (folders/tags/shared prompt kits).
9. **Optional multi-user profile** for self-hosted teams.

## Immediate implementation choice

Start with **Model controls and presets** because it is low-risk, improves day-to-day quality quickly, and is a prerequisite for fair model comparisons.

## Sources

- LM Studio docs: [https://lmstudio.ai/docs](https://lmstudio.ai/docs)
- LM Studio model discovery/download: [https://lmstudio.ai/docs/app/basics/download-model](https://lmstudio.ai/docs/app/basics/download-model)
- LM Studio API server: [https://lmstudio.ai/docs/app/api/endpoints/openai](https://lmstudio.ai/docs/app/api/endpoints/openai)
- LM Studio MCP docs: [https://lmstudio.ai/docs/app/plugins/mcp](https://lmstudio.ai/docs/app/plugins/mcp)
- Jan docs home: [https://jan.ai/docs](https://jan.ai/docs)
- Jan model parameters: [https://jan.ai/docs/desktop/model-parameters](https://jan.ai/docs/desktop/model-parameters)
- Jan API server: [https://jan.ai/docs/desktop/api-server](https://jan.ai/docs/desktop/api-server)
- AnythingLLM docs: [https://docs.anythingllm.com](https://docs.anythingllm.com)
- AnythingLLM all features: [https://docs.anythingllm.com/features/all-features](https://docs.anythingllm.com/features/all-features)
- AnythingLLM API: [https://docs.anythingllm.com/features/api](https://docs.anythingllm.com/features/api)
- AnythingLLM MCP: [https://docs.anythingllm.com/mcp-compatibility/overview](https://docs.anythingllm.com/mcp-compatibility/overview)
- GPT4All docs: [https://docs.gpt4all.io](https://docs.gpt4all.io)
- GPT4All LocalDocs: [https://docs.gpt4all.io/gpt4all_desktop/localdocs.html](https://docs.gpt4all.io/gpt4all_desktop/localdocs.html)
- GPT4All API server: [https://docs.gpt4all.io/gpt4all_api_server/home.html](https://docs.gpt4all.io/gpt4all_api_server/home.html)
- Open WebUI features: [https://docs.openwebui.com/features/](https://docs.openwebui.com/features/)
- Ollama docs: [https://docs.ollama.com](https://docs.ollama.com)
- Ollama model import: [https://docs.ollama.com/import](https://docs.ollama.com/import)
