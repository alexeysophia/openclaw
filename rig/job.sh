#!/bin/bash
# Phase 1: install deps, build, run gateway unit tests + typecheck. Logs to rig/logs/.
set -uo pipefail
cd /work/openclaw
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
mkdir -p rig/logs
echo "JOB_START $(date -u +%H:%M:%S)" >> rig/logs/status
corepack pnpm install --reporter=append-only > rig/logs/install.log 2>&1 \
  && echo "INSTALL_OK $(date -u +%H:%M:%S)" >> rig/logs/status \
  || { echo "INSTALL_FAILED $(date -u +%H:%M:%S)" >> rig/logs/status; exit 1; }
corepack pnpm build > rig/logs/build.log 2>&1 \
  && echo "BUILD_OK $(date -u +%H:%M:%S)" >> rig/logs/status \
  || echo "BUILD_FAILED $(date -u +%H:%M:%S)" >> rig/logs/status
node scripts/run-vitest.mjs src/gateway/openresponses-http.test.ts src/gateway/openai-http.test.ts > rig/logs/vitest.log 2>&1 \
  && echo "VITEST_OK $(date -u +%H:%M:%S)" >> rig/logs/status \
  || echo "VITEST_FAILED $(date -u +%H:%M:%S)" >> rig/logs/status
corepack pnpm exec tsc -p tsconfig.core.json --noEmit > rig/logs/tsc.log 2>&1 \
  && echo "TSC_OK $(date -u +%H:%M:%S)" >> rig/logs/status \
  || echo "TSC_FAILED $(date -u +%H:%M:%S)" >> rig/logs/status
echo "PHASE1_DONE $(date -u +%H:%M:%S)" >> rig/logs/status
