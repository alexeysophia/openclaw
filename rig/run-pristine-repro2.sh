#!/bin/bash
# Pristine-main repro, phase 2: install+build solo, then the no-header spawn scenario.
set -u
RIG=/work/openclaw/rig
PRISTINE=/work/main-pristine
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

pkill node; sleep 2

cd "$PRISTINE" || { echo P2_CD_FAILED >> "$RIG/logs/status"; exit 1; }
corepack pnpm install --prefer-offline --reporter=append-only > "$RIG/logs/pristine-install.log" 2>&1 \
  && echo P2_INSTALL_OK >> "$RIG/logs/status" || { echo P2_INSTALL_FAILED >> "$RIG/logs/status"; exit 1; }
corepack pnpm build > "$RIG/logs/pristine-build.log" 2>&1 \
  && echo P2_BUILD_OK >> "$RIG/logs/status" || { echo P2_BUILD_FAILED >> "$RIG/logs/status"; exit 1; }

cd "$RIG"
nohup node mock-llm.cjs > logs/mock-llm.log 2>&1 &
sleep 2
curl -s -X POST http://127.0.0.1:8113/control/reset > /dev/null
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"CHILD_WORKER_MARKER_XK47","response":{"type":"text","text":"CHILD_FINAL_TEXT_P"}}' > /dev/null
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"[Internal task completion event]","response":{"type":"text","text":"ANNOUNCE_TEXT_PRISTINE"}}' > /dev/null
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"SPAWN-P","response":{"type":"tool","name":"sessions_spawn","arguments":{"agentId":"background-worker","task":"please do the background job and report the result"}}}' > /dev/null
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"SPAWN-P","response":{"type":"text","text":"PARENT_ACK_P"}}' > /dev/null

rm -rf "$RIG/state-c" /tmp/openclaw-state-locks-0 /tmp/openclaw
sed "s#RIG_DIR#$RIG#g" "$RIG/openclaw.tmpl.json" > "$RIG/openclaw.c.json"
cd "$PRISTINE"
OPENCLAW_STATE_DIR="$RIG/state-c" OPENCLAW_CONFIG_PATH="$RIG/openclaw.c.json" \
nohup node openclaw.mjs gateway --port 19301 > "$RIG/logs/gateway-pristine.log" 2>&1 &

UP=0
for i in $(seq 1 120); do
  curl -s -o /dev/null http://127.0.0.1:19301 && UP=1 && break
  sleep 2
done
[ "$UP" = 1 ] || { echo P2_GATEWAY_TIMEOUT >> "$RIG/logs/status"; exit 1; }
sleep 3

{
  echo "=== pristine main $(git -C "$PRISTINE" rev-parse --short HEAD): /v1/responses spawn, NO target headers ==="
  curl -s http://127.0.0.1:19301/v1/responses -X POST \
    -H "Authorization: Bearer rig-secret" -H "Content-Type: application/json" \
    -H "x-openclaw-session-key: agent:main:pristine-1" \
    -H "x-openclaw-message-channel: orchestrator" \
    -d '{"model":"openclaw/main","input":"SPAWN-P please run the background job","stream":false}' | head -c 400
  echo
} > "$RIG/logs/pristine-repro.log"
sleep 90
{
  echo "=== gateway stdout: announce lines ==="
  grep -aE "announce" "$RIG/logs/gateway-pristine.log" | head -6
  echo "=== file log: announce failures ==="
  grep -ahoE "Subagent completion direct announce failed[^\"]*" /tmp/openclaw/openclaw-*.log 2>/dev/null | head -4
  echo "=== mock rule consumption ==="
  curl -s http://127.0.0.1:8113/control/log
} >> "$RIG/logs/pristine-repro.log"
echo P2_REPRO_DONE >> "$RIG/logs/status"
