#!/bin/bash
# Start mock provider + fake receiver + gateway. Usage: start-stack.sh a|b
# a = token auth (port 19301), b = auth none (port 19302).
set -euo pipefail
PHASE="$1"
RIG=/work/openclaw/rig
cd "$RIG"
mkdir -p logs state-a state-b workspace-main worker-workspace captured
echo 'CHILD_WORKER_MARKER_XK47: this file identifies the background-worker child prompt.' > worker-workspace/AGENTS.md
mkdir -p plugins/orchestrator-channel/node_modules
ln -sfn /work/openclaw plugins/orchestrator-channel/node_modules/openclaw

if ! curl -s -o /dev/null http://127.0.0.1:8113/control/log; then
  nohup node mock-llm.js > logs/mock-llm.log 2>&1 &
fi
if ! curl -s -o /dev/null http://127.0.0.1:8114/control/log; then
  nohup node fake-orchestrator.js > logs/fake-orch.log 2>&1 &
fi
sleep 1

if [ "$PHASE" = "a" ]; then
  sed "s#RIG_DIR#$RIG#g" openclaw.tmpl.json > openclaw.a.json
  CFG="$RIG/openclaw.a.json"; STATE="$RIG/state-a"; PORT=19301
else
  sed -e "s#RIG_DIR#$RIG#g" -e 's#"mode": "token", "token": "rig-secret"#"mode": "none"#' openclaw.tmpl.json > openclaw.b.json
  CFG="$RIG/openclaw.b.json"; STATE="$RIG/state-b"; PORT=19302
fi

cd /work/openclaw
OPENCLAW_STATE_DIR="$STATE" OPENCLAW_CONFIG_PATH="$CFG" \
ORCHESTRATOR_INTERNAL_URL=http://127.0.0.1:8114 \
ORCHESTRATOR_ASSISTANT_TOKEN=test-assistant-token \
ORCHESTRATOR_CONTAINER_ID=abcdef012345 \
nohup node openclaw.mjs gateway --port "$PORT" > "$RIG/logs/gateway-$PHASE.log" 2>&1 &

for i in $(seq 1 90); do
  if curl -s -o /dev/null "http://127.0.0.1:$PORT"; then echo "GATEWAY_${PHASE}_UP"; exit 0; fi
  sleep 2
done
echo "GATEWAY_${PHASE}_TIMEOUT"
tail -30 "$RIG/logs/gateway-$PHASE.log"
exit 1
