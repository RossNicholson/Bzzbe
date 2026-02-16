# Alpha Performance Report 01

_Generated: 2026-02-16_

## Scope

- Target metrics: first-token latency, tokens/sec, peak memory.
- Target environments: two Apple Silicon tiers.
- Harness: `swift run BzzbePerfHarness` (added in JOB-016) via `scripts/run-alpha-perf.sh`.

## Environment + Commands

- Workspace machine label: `Ross’s Mac mini`
- Model target: `qwen2.5:7b-instruct-q4_K_M`
- Prompt: `Explain what Bzzbe does in two short sentences.`

Commands used on 2026-02-16:

```bash
BZZBE_PERF_CLIENT=mock BZZBE_PERF_RUNS=3 ./scripts/run-alpha-perf.sh
BZZBE_PERF_CLIENT=runtime BZZBE_PERF_RUNS=1 ./scripts/run-alpha-perf.sh
```

Raw output artifact:

- `docs/reports/raw/alpha-perf-20260216-210821.json`

## Results

| Run Set | Backend | First-Token Latency (avg ms) | Throughput (avg tokens/sec) | Peak Memory (MB) | Status |
| --- | --- | ---: | ---: | ---: | --- |
| Local harness validation (3 runs) | mock | 0.06 | 36.99 | 6.88 | Complete |
| Runtime connectivity check (1 run) | runtime (`http://127.0.0.1:11434`) | N/A | N/A | N/A | Failed: `Local runtime unavailable: Could not connect to the server.` |

## Defect Triage

| Severity | Defect | Impact | Owner | Status |
| --- | --- | --- | --- | --- |
| P1 | Local runtime not reachable on benchmark host (`127.0.0.1:11434`) | Blocks real alpha performance capture. | Runtime | Open |
| P1 | Second Apple Silicon tier data missing | Alpha report requirement (two tiers) not yet met. | QA/Platform | Open |
| P2 | Peak memory currently samples harness process RSS only | Under-reports full runtime+model memory footprint until external runtime process metrics are added. | QA | Open |

## Summary

- JOB-016 harness and reporting pipeline is now present in-repo and runnable.
- Real runtime metrics are blocked by local runtime availability and missing second-tier execution.
- Next report update should replace mock validation numbers with real runtime runs from two Apple Silicon tiers and close the two P1 defects above.
