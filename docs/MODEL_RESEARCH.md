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
- `https://ollama.com/library/qwen3`
- `https://ollama.com/library/gemma3`
- `https://ollama.com/library/gpt-oss`
- `https://ollama.com/library/mistral-small3.1`
- `https://ollama.com/library/phi4-mini`
- `https://ollama.com/library/qwen2.5`

## Candidate model families

### 1) Qwen 3 (0.6B to 235B)

- Strengths: strongest current open-family quality/size ladder for local chat + coding.
- Observed Ollama package sizes (selected): ~2.6GB (4B), ~5.2GB (8B), ~9.3GB (14B).
- Best use in Bzzbe: primary model family across all default RAM tiers.

### 2) Phi-4 Mini (3.8B)

- Strengths: compact, recent, and practical for 8GB Macs.
- Observed Ollama package size: ~2.5GB.
- Best use in Bzzbe: small-tier fallback when Qwen 3 tags are unavailable.

### 3) Gemma 3 (multimodal family)

- Strengths: multimodal-capable family with strong quality/size tradeoff and broad adoption.
- Observed Ollama package sizes (selected): ~815MB, ~3.3GB, ~8.1GB, ~17GB.
- Best use in Bzzbe: high-quality fallback tier for 24GB+ Macs.

### 4) GPT-OSS (20B/120B)

- Strengths: current open-weight flagship family.
- Observed Ollama package sizes: ~13GB (20B), ~65GB (120B).
- Best use in Bzzbe: optional "power user" pack for 32GB+ Macs after v1 defaults are stable.

### 5) Mistral Small 3.1 (24B)

- Strengths: high-quality compact frontier model with strong multilingual/coding behavior.
- Observed Ollama package size: ~15GB.
- Best use in Bzzbe: optional 32GB+ text+vision pack.

### 6) Qwen 2.5 (legacy fallback family)

- Strengths: stable, widely deployed fallback for existing local setups.
- Observed Ollama package sizes (selected): ~4.7GB (7B), ~9.0GB (14B).
- Best use in Bzzbe: balanced-tier fallback to reduce upgrade risk.

## Hardware-tier recommendation (v1)

Current v1 installer mapping adopted in code:

- **Small tier (8-15GB RAM)**:
  - Primary: `qwen3:4b` (~2.6GB)
  - Fallback: `phi4-mini:3.8b-instruct-q4_K_M` (~2.5GB)
- **Balanced tier (16-23GB RAM)**:
  - Primary: `qwen3:8b` (~5.2GB)
  - Fallback: `qwen2.5:7b-instruct-q4_K_M` (~4.7GB)
- **High quality tier (24GB+ RAM)**:
  - Primary: `qwen3:14b` (~9.3GB)
  - Fallback: `gemma3:12b-it-q4_K_M` (~8.1GB)

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
