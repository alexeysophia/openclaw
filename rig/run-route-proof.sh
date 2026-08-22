#!/bin/bash
# Minimal session-route binding proof: fresh gateway A, one turn with the header,
# one turn without (separate session), then dump the state DB while the gateway lives.
set -u
RIG=/work/openclaw/rig
cd "$RIG"

PIDS=$(pgrep -a node | awk '/openclaw\.mjs gateway/ {print $1}')
[ -n "$PIDS" ] && kill $PIDS
sleep 3
rm -rf /tmp/openclaw-state-locks-0 state-a
rm -f logs/gateway-a.log

curl -s -o /dev/null http://127.0.0.1:8113/control/log || (nohup node mock-llm.cjs > logs/mock-llm.log 2>&1 &)
sleep 1
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"ROUTE-PROOF-1","response":{"type":"text","text":"ROUTE_PROOF_REPLY_1"}}'
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"ROUTE-PROOF-2","response":{"type":"text","text":"ROUTE_PROOF_REPLY_2"}}'

sed "s#RIG_DIR#$RIG#g" openclaw.tmpl.json > openclaw.a.json
cd /work/openclaw
OPENCLAW_STATE_DIR="$RIG/state-a" OPENCLAW_CONFIG_PATH="$RIG/openclaw.a.json" \
ORCHESTRATOR_INTERNAL_URL=http://127.0.0.1:8114 \
ORCHESTRATOR_ASSISTANT_TOKEN=test-assistant-token \
ORCHESTRATOR_CONTAINER_ID=abcdef012345 \
nohup node openclaw.mjs gateway --port 19301 > "$RIG/logs/gateway-a.log" 2>&1 &

for i in $(seq 1 90); do
  curl -s -o /dev/null http://127.0.0.1:19301 && break
  sleep 2
done
sleep 3

echo "=== turn WITH x-openclaw-message-to (session agent:main:rig-route-1) ==="
curl -s http://127.0.0.1:19301/v1/responses -X POST \
  -H "Authorization: Bearer rig-secret" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: agent:main:rig-route-1" \
  -H "x-openclaw-message-channel: orchestrator" \
  -H "x-openclaw-message-to: user" \
  -d '{"model":"openclaw/main","input":"ROUTE-PROOF-1 hello","stream":false}' | head -c 300
echo
echo "=== turn WITHOUT the header (session agent:main:rig-route-2) ==="
curl -s http://127.0.0.1:19301/v1/responses -X POST \
  -H "Authorization: Bearer rig-secret" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: agent:main:rig-route-2" \
  -H "x-openclaw-message-channel: orchestrator" \
  -d '{"model":"openclaw/main","input":"ROUTE-PROOF-2 hello","stream":false}' | head -c 300
echo
sleep 3
echo "=== state DB dump (live) ==="
node "$RIG/dump-session2.cjs" "$RIG/state-a/state/openclaw.sqlite"
echo ROUTE_PROOF_DONE >> "$RIG/logs/status"
