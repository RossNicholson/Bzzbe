# Alpha Performance Report 01

_Generated: 2026-02-16_

## Scope

- Target metrics: first-token latency, tokens/sec, peak memory.
- Target environments: two Apple Silicon tiers.
- Harness: `swift run BzzbePerfHarness` (added in JOB-016) via `scripts/run-alpha-perf.sh`.
- Memory sampling mode: harness RSS + runtime-process RSS (`--runtime-process`, default `ollama`).

## Environment + Commands

- Workspace machine label: `Ross’s Mac mini`
- Model target: `qwen2.5:7b-instruct-q4_K_M`
- Prompt: `Explain what Bzzbe does in two short sentences.`

Commands used on 2026-02-16:

```bash
which ollama
BZZBE_PERF_CLIENT=mock BZZBE_PERF_RUNS=3 ./scripts/run-alpha-perf.sh
BZZBE_PERF_CLIENT=runtime BZZBE_PERF_RUNS=1 ./scripts/run-alpha-perf.sh
```

Raw output artifacts:

- `docs/reports/raw/alpha-perf-20260216-210821.json` (initial baseline)
- `docs/reports/raw/alpha-perf-20260216-211543.json` (latest baseline with host/runtime RSS fields)

## Results

| Run Set | Backend | First-Token Latency (avg ms) | Throughput (avg tokens/sec) | Peak Combined RSS (MB) | Peak Runtime RSS (MB) | Status |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Local harness validation (3 runs) | mock | 0.09 | 34.80 | 8.23 | 0.00 | Complete |
| Runtime connectivity check (1 run) | runtime (`http://127.0.0.1:11434`) | N/A | N/A | N/A | N/A | Failed: `Local runtime unavailable: Could not connect to the server.` |

## Defect Triage

| Severity | Defect | Impact | Owner | Status |
| --- | --- | --- | --- | --- |
| P1 | Runtime binary/service unavailable on benchmark host (`ollama` not found; `127.0.0.1:11434` unreachable) | Blocks real alpha performance capture. | Runtime | Open |
| P1 | Second Apple Silicon tier data missing | Alpha report requirement (two tiers) not yet met. | QA/Platform | Open |
| P2 | Runtime RSS remains `0 MB` in available samples | Harness now tracks runtime-process RSS, but no runtime process was active during capture. | QA | Open |

## Summary

- JOB-016 harness and reporting pipeline is now present in-repo and runnable.
- Real runtime metrics remain blocked by local runtime availability and missing second-tier execution.
- Next report update should include successful runtime captures on two Apple Silicon tiers and close the two P1 defects above.
