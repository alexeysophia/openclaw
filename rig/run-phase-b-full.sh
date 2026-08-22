#!/bin/bash
# Phase B: stop gateway A, start auth-none gateway on 19302, run the gate proofs.
set -u
RIG=/work/openclaw/rig
cd "$RIG"

PIDS=$(pgrep -a node | awk '/openclaw\.mjs gateway/ {print $1}')
[ -n "$PIDS" ] && kill $PIDS
sleep 3

rm -rf state-b
cd /work/openclaw
OPENCLAW_STATE_DIR="$RIG/state-b" OPENCLAW_CONFIG_PATH="$RIG/openclaw.b.json" \
ORCHESTRATOR_INTERNAL_URL=http://127.0.0.1:8114 \
ORCHESTRATOR_ASSISTANT_TOKEN=test-assistant-token \
ORCHESTRATOR_CONTAINER_ID=abcdef012345 \
nohup node openclaw.mjs gateway --port 19302 > "$RIG/logs/gateway-b.log" 2>&1 &

UP=0
for i in $(seq 1 90); do
  if curl -s -o /dev/null http://127.0.0.1:19302; then UP=1; break; fi
  sleep 2
done
if [ "$UP" != 1 ]; then echo GATEWAY_B_TIMEOUT >> "$RIG/logs/status"; exit 1; fi
echo GATEWAY_B_UP >> "$RIG/logs/status"
sleep 3

bash "$RIG/drive-phase-b.sh" > "$RIG/logs/phase-b.log" 2>&1
echo PHASE_B_DONE >> "$RIG/logs/status"
