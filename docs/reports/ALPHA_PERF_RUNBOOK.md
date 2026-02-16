# Alpha Perf Runbook

_Last updated: 2026-02-16_

This runbook defines the exact steps to close `JOB-016` by capturing real runtime performance on two Apple Silicon tiers.

## Required environments

- Tier A: Apple Silicon machine with **16GB RAM class** (or nearest lower tier available).
- Tier B: Apple Silicon machine with **24GB+ RAM class**.
- Runtime installed and serving locally (default target: `http://127.0.0.1:11434`).

## Pre-flight checks (run on each machine)

```bash
which ollama
curl -sS http://127.0.0.1:11434/api/tags | head
```

If either fails, runtime is not ready and captures are invalid for `JOB-016`.

## Benchmark capture command

Run from repository root on each machine:

```bash
BZZBE_PERF_CLIENT=runtime \
BZZBE_PERF_RUNS=3 \
BZZBE_PERF_LABEL="<machine-label>" \
BZZBE_PERF_MODEL="qwen3:8b" \
./scripts/run-alpha-perf.sh
```

This writes raw output to:

- `docs/reports/raw/alpha-perf-<timestamp>.json`

## Data required in final alpha report

For each tier, include:

- Average first-token latency (ms)
- Average tokens/sec
- Peak combined RSS (MB)
- Peak runtime RSS (MB)
- Machine metadata from `hostProfile` (`architecture`, `physicalMemoryGB`, `logicalCPUCount`, `macOSVersion`)

## Completion criteria for JOB-016

- Two runtime captures exist from distinct Apple Silicon memory tiers.
- `docs/reports/alpha-01.md` includes both runtime rows and no open P1 blockers.
- Any remaining issues are triaged with owner + status.
