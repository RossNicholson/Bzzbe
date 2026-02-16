# Bzzbe Local Model Research (Apple Silicon Focus)

_Last updated: 2026-02-16_

This document captures practical model options for Bzzbe's first installer experience on Apple Silicon Macs.

## Research method

We prioritized models that:

1. are available in mainstream local runtimes (`llama.cpp` / Ollama),
2. have downloadable quantized variants that fit unified-memory Macs,
3. have clear licensing notes suitable for open-source distribution,
4. provide strong instruction-following quality for assistant/agent workflows.

Primary source pages reviewed:

- `https://ollama.com/library`
- `https://ollama.com/library/llama3.2`
- `https://ollama.com/library/qwen2.5`
- `https://ollama.com/library/gemma3`
- `https://ollama.com/library/mistral`
- `https://ollama.com/library/phi4`
- `https://ollama.com/library/deepseek-r1`

## Candidate model families

### 1) Llama 3.2 (1B/3B)

- Strengths: small footprint, good baseline chat quality, practical for 8GB Macs.
- Observed Ollama package sizes: ~1.3GB to ~2.0GB for common tags.
- Best use in Bzzbe: default "small" tier and safe first-run install.

### 2) Qwen 2.5 (0.5B to 72B variants)

- Strengths: broad size ladder, generally strong instruction + coding behavior.
- Observed Ollama package sizes (selected): ~398MB, ~986MB, ~1.9GB, ~4.7GB, ~9.0GB, ~20GB, ~47GB.
- License note on model page: most variants Apache 2.0; exceptions called out for some sizes.
- Best use in Bzzbe: default "balanced" tier around 7B.

### 3) Gemma 3 (multimodal family)

- Strengths: multimodal-capable family with strong quality/size tradeoff.
- Observed Ollama package sizes (selected): ~815MB, ~3.3GB, ~8.1GB, ~17GB.
- Best use in Bzzbe: "high quality" tier for 24GB+ Macs.

### 4) Mistral 7B

- Strengths: mature open model, compact, reliable baseline.
- Observed Ollama package size: ~4.4GB.
- Best use in Bzzbe: backup balanced-tier option if other models are unavailable.

### 5) Phi-4 (14B)

- Strengths: high quality general assistant model for local use.
- Observed Ollama package size: ~9.1GB.
- Best use in Bzzbe: optional high-quality text-only alternative.

### 6) DeepSeek-R1 distilled family

- Strengths: reasoning-heavy options; many sizes available.
- Observed Ollama package sizes range from ~1.1GB to very large variants (40GB+).
- Best use in Bzzbe: optional advanced "reasoning" add-on after v1 stability.

## Hardware-tier recommendation (v1)

Current v1 installer mapping adopted in code:

- **Small tier (8-15GB RAM)**: `llama3.2:3b-instruct-q4_K_M` (~2.0GB)
- **Balanced tier (16-23GB RAM)**: `qwen2.5:7b-instruct-q4_K_M` (~4.7GB)
- **High quality tier (24GB+ RAM)**: `gemma3:12b-it-q4_K_M` (~8.1GB)

Safety rule used for first-pass install eligibility: require approximately `2x` model download size in free disk before installation.

## Notes for App Store + OSS readiness

Before shipping a default catalog in production:

1. Re-verify each model's license terms at release cut time.
2. Pin exact model tags/checksums for reproducible installs.
3. Maintain a fallback mirror strategy and artifact verification chain.
4. Keep model downloads user-initiated with explicit consent in onboarding UX.

## Follow-up actions

- Add versioned model manifest file (JSON) with checksums and mirrors.
- Add benchmark harness results per Mac tier (M1 8GB, M2/M3 16GB, M3/M4 24GB+).
- Add opt-in "reasoning pack" with larger models for power users.
