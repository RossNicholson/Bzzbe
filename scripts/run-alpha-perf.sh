#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/docs/reports/raw"
mkdir -p "${REPORT_DIR}"

LABEL="${BZZBE_PERF_LABEL:-$(scutil --get ComputerName 2>/dev/null || hostname)}"
CLIENT="${BZZBE_PERF_CLIENT:-runtime}"
RUNS="${BZZBE_PERF_RUNS:-3}"
MODEL="${BZZBE_PERF_MODEL:-qwen2.5:7b-instruct-q4_K_M}"
BASE_URL="${BZZBE_PERF_BASE_URL:-http://127.0.0.1:11434}"
PROMPT="${BZZBE_PERF_PROMPT:-Explain what Bzzbe does in two short sentences.}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="${REPORT_DIR}/alpha-perf-${STAMP}.json"

cd "${ROOT_DIR}"

swift run BzzbePerfHarness \
  --client "${CLIENT}" \
  --base-url "${BASE_URL}" \
  --model "${MODEL}" \
  --prompt "${PROMPT}" \
  --runs "${RUNS}" \
  --label "${LABEL}" \
  --json-out "${OUT_FILE}"

echo "saved raw report: ${OUT_FILE}"
