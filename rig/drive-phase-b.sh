#!/bin/bash
# Phase B: auth mode "none" (private ingress, identity-bearing via x-openclaw-scopes) —
# owner-gate proof: write-only scope + target header => 403; admin scope => 200.
set -u
GW="http://127.0.0.1:19302"
MOCK="http://127.0.0.1:8113"

push() { curl -s -X POST "$MOCK/control/push" -d "$1" > /dev/null; }
mock_count() { curl -s "$MOCK/control/log" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"; }

echo "=== B1: /v1/responses, target header + scopes=operator.write => expect 403, no dispatch ==="
M0=$(mock_count)
curl -s -w "\nHTTP %{http_code}\n" "$GW/v1/responses" -X POST -H "Content-Type: application/json" \
  -H "x-openclaw-scopes: operator.write" \
  -H "x-openclaw-session-key: rig-b1-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -H "x-openclaw-message-to: user" \
  -d '{"model":"openclaw","input":"plain question","stream":false}'
echo "provider requests before=$M0 after=$(mock_count)"

echo "=== B2: /v1/chat/completions, target header + scopes=operator.write => expect 403 ==="
M0=$(mock_count)
curl -s -w "\nHTTP %{http_code}\n" "$GW/v1/chat/completions" -X POST -H "Content-Type: application/json" \
  -H "x-openclaw-scopes: operator.write" \
  -H "x-openclaw-session-key: rig-b2-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -H "x-openclaw-message-to: user" \
  -d '{"model":"openclaw","messages":[{"role":"user","content":"plain question"}],"stream":false}'
echo "provider requests before=$M0 after=$(mock_count)"

echo "=== B3: /v1/responses, target header + scopes=operator.admin, operator.write => expect 200 ==="
push '{"match":"ADMIN-OK","response":{"type":"text","text":"ADMIN_SCOPE_ACCEPTED_REPLY"}}'
curl -s -w "\nHTTP %{http_code}\n" "$GW/v1/responses" -X POST -H "Content-Type: application/json" \
  -H "x-openclaw-scopes: operator.admin, operator.write" \
  -H "x-openclaw-session-key: rig-b3-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -H "x-openclaw-message-to: user" \
  -d '{"model":"openclaw","input":"ADMIN-OK plain question","stream":false}' | head -c 500

echo "=== B4: /v1/responses, NO target header + scopes=operator.write => expect 200 (unchanged for non-owners not using the header) ==="
push '{"match":"WRITE-OK","response":{"type":"text","text":"WRITE_SCOPE_NO_HEADER_REPLY"}}'
curl -s -w "\nHTTP %{http_code}\n" "$GW/v1/responses" -X POST -H "Content-Type: application/json" \
  -H "x-openclaw-scopes: operator.write" \
  -H "x-openclaw-session-key: rig-b4-session" \
  -H "x-openclaw-message-channel: orchestrator" \
  -d '{"model":"openclaw","input":"WRITE-OK plain question","stream":false}' | head -c 500
echo
