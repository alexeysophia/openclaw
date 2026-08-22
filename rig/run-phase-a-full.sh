#!/bin/bash
# Full phase A run: fresh services + fresh gateway (final config, no mid-run edits) + driver.
set -u
RIG=/work/openclaw/rig
cd "$RIG"
mkdir -p logs captured workspace-main worker-workspace
echo 'CHILD_WORKER_MARKER_XK47: this file identifies the background-worker child prompt.' > worker-workspace/AGENTS.md
mkdir -p plugins/orchestrator-channel/node_modules
ln -sfn /work/openclaw plugins/orchestrator-channel/node_modules/openclaw

nohup node mock-llm.cjs > logs/mock-llm.log 2>&1 &
nohup node fake-orchestrator.cjs > logs/fake-orch.log 2>&1 &
sleep 2

sed "s#RIG_DIR#$RIG#g" openclaw.tmpl.json > openclaw.a.json
rm -rf state-a
cd /work/openclaw
OPENCLAW_STATE_DIR="$RIG/state-a" OPENCLAW_CONFIG_PATH="$RIG/openclaw.a.json" \
ORCHESTRATOR_INTERNAL_URL=http://127.0.0.1:8114 \
ORCHESTRATOR_ASSISTANT_TOKEN=test-assistant-token \
ORCHESTRATOR_CONTAINER_ID=abcdef012345 \
nohup node openclaw.mjs gateway --port 19301 > "$RIG/logs/gateway-a.log" 2>&1 &

UP=0
for i in $(seq 1 90); do
  if curl -s -o /dev/null http://127.0.0.1:19301; then UP=1; break; fi
  sleep 2
done
if [ "$UP" != 1 ]; then echo GATEWAY_A_TIMEOUT >> logs/status; exit 1; fi
echo GATEWAY_A_UP >> "$RIG/logs/status"
sleep 5

bash "$RIG/drive-phase-a.sh" > "$RIG/logs/phase-a.log" 2>&1
echo PHASE_A4_DONE >> "$RIG/logs/status"
