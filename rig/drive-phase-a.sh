#!/bin/bash
# Phase A: token-auth gateway — owner (shared-secret) delivery proof, both endpoints.
set -u
GW="http://127.0.0.1:19301"
MOCK="http://127.0.0.1:8113"
RECV="http://127.0.0.1:8114"
AUTH="Authorization: Bearer rig-secret"

push() { curl -s -X POST "$MOCK/control/push" -d "$1" > /dev/null; }
recv_count() { curl -s "$RECV/control/log" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"; }
wait_send() { # $1 = expected substring, $2 = timeout seconds
  local t=0
  while [ $t -lt "$2" ]; do
    if curl -s "$RECV/control/log" | grep -q "$1"; then echo "SEND_OBSERVED"; return 0; fi
    sleep 3; t=$((t+3))
  done
  echo "SEND_TIMEOUT"; return 1
}

echo "=== A1: /v1/responses, WITH x-openclaw-message-to (owner via token auth) ==="
push '{"match":"CHILD_WORKER_MARKER_XK47","response":{"type":"text","text":"CHILD_FINAL_TEXT_A"}}'
push '{"match":"[Internal task completion event]","response":{"type":"text","text":"ANNOUNCE_AUTODELIVER_TEXT: background task finished, here is the result for the user."}}'
push '{"match":"SPAWN-A","response":{"type":"tool","name":"sessions_spawn","arguments":{"agentId":"background-worker","task":"please do the background job and report the result"}}}'
push '{"match":"SPAWN-A","response":{"type":"text","text":"PARENT_ACK_A_AFTER_SPAWN_RESULT"}}'
C0=$(recv_count)
curl -s "$GW/v1/responses" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: rig-a1-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -H "x-openclaw-message-to: user" \
  -d '{"model":"openclaw","input":"SPAWN-A please run the background job","stream":false}' | head -c 400
echo
wait_send "ANNOUNCE_AUTODELIVER_TEXT" 120
echo "receiver calls before=$C0 after=$(recv_count)"

echo "=== A2: /v1/responses, WITHOUT the header — must NOT deliver ==="
push '{"match":"CHILD_WORKER_MARKER_XK47","response":{"type":"text","text":"CHILD_FINAL_TEXT_B"}}'
push '{"match":"[Internal task completion event]","response":{"type":"text","text":"ANNOUNCE_NOT_FOR_DELIVERY_B"}}'
push '{"match":"SPAWN-B","response":{"type":"tool","name":"sessions_spawn","arguments":{"agentId":"background-worker","task":"please do the background job and report the result"}}}'
push '{"match":"SPAWN-B","response":{"type":"text","text":"PARENT_ACK_B_AFTER_SPAWN_RESULT"}}'
C0=$(recv_count)
curl -s "$GW/v1/responses" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: rig-a2-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -d '{"model":"openclaw","input":"SPAWN-B please run the background job","stream":false}' | head -c 400
echo
wait_send "ANNOUNCE_NOT_FOR_DELIVERY_B" 45 || true
echo "receiver calls before=$C0 after=$(recv_count)"

echo "=== A3: /v1/chat/completions, WITH the header ==="
push '{"match":"CHILD_WORKER_MARKER_XK47","response":{"type":"text","text":"CHILD_FINAL_TEXT_C"}}'
push '{"match":"[Internal task completion event]","response":{"type":"text","text":"ANNOUNCE_AUTODELIVER_TEXT_CC: chat-completions parity delivery."}}'
push '{"match":"SPAWN-C","response":{"type":"tool","name":"sessions_spawn","arguments":{"agentId":"background-worker","task":"please do the background job and report the result"}}}'
push '{"match":"SPAWN-C","response":{"type":"text","text":"PARENT_ACK_C_AFTER_SPAWN_RESULT"}}'
C0=$(recv_count)
curl -s "$GW/v1/chat/completions" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: rig-a3-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -H "x-openclaw-message-to: user" \
  -d '{"model":"openclaw","messages":[{"role":"user","content":"SPAWN-C please run the background job"}],"stream":false}' | head -c 400
echo
wait_send "ANNOUNCE_AUTODELIVER_TEXT_CC" 120
echo "receiver calls before=$C0 after=$(recv_count)"

echo "=== A4: /v1/chat/completions, WITHOUT the header — must NOT deliver ==="
push '{"match":"CHILD_WORKER_MARKER_XK47","response":{"type":"text","text":"CHILD_FINAL_TEXT_D"}}'
push '{"match":"[Internal task completion event]","response":{"type":"text","text":"ANNOUNCE_NOT_FOR_DELIVERY_D"}}'
push '{"match":"SPAWN-D","response":{"type":"tool","name":"sessions_spawn","arguments":{"agentId":"background-worker","task":"please do the background job and report the result"}}}'
push '{"match":"SPAWN-D","response":{"type":"text","text":"PARENT_ACK_D_AFTER_SPAWN_RESULT"}}'
C0=$(recv_count)
curl -s "$GW/v1/chat/completions" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: rig-a4-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -d '{"model":"openclaw","messages":[{"role":"user","content":"SPAWN-D please run the background job"}],"stream":false}' | head -c 400
echo
wait_send "ANNOUNCE_NOT_FOR_DELIVERY_D" 45 || true
echo "receiver calls before=$C0 after=$(recv_count)"

echo "=== receiver full log ==="
curl -s "$RECV/control/log"
