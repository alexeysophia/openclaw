#!/bin/bash
# Reproduce the announce-dispatch failure on PRISTINE upstream main (no PR diff):
# worktree at the same base commit, own build, one no-header spawn scenario.
set -u
RIG=/work/openclaw/rig
BASE=39cff928
PRISTINE=/work/main-pristine
cd /work/openclaw

git remote add up https://github.com/openclaw/openclaw.git 2>/dev/null
git fetch --depth 1 up main 2>&1 | tail -1
git worktree add "$PRISTINE" "$BASE" 2>&1 | tail -1 || git worktree add "$PRISTINE" up/main 2>&1 | tail -1
cd "$PRISTINE"
git log --oneline -1
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
corepack pnpm install --prefer-offline --reporter=append-only > "$RIG/logs/pristine-install.log" 2>&1 \
  && echo PRISTINE_INSTALL_OK >> "$RIG/logs/status" || { echo PRISTINE_INSTALL_FAILED >> "$RIG/logs/status"; exit 1; }
corepack pnpm build > "$RIG/logs/pristine-build.log" 2>&1 \
  && echo PRISTINE_BUILD_OK >> "$RIG/logs/status" || { echo PRISTINE_BUILD_FAILED >> "$RIG/logs/status"; exit 1; }

PIDS=$(pgrep -a node | awk '/openclaw\.mjs gateway/ {print $1}')
[ -n "$PIDS" ] && kill $PIDS
sleep 3
rm -rf "$RIG/state-c" /tmp/openclaw-state-locks-0

curl -s -o /dev/null http://127.0.0.1:8113/control/log || (cd "$RIG" && nohup node mock-llm.cjs > logs/mock-llm.log 2>&1 &)
sleep 1
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"CHILD_WORKER_MARKER_XK47","response":{"type":"text","text":"CHILD_FINAL_TEXT_P"}}'
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"[Internal task completion event]","response":{"type":"text","text":"ANNOUNCE_TEXT_PRISTINE"}}'
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"SPAWN-P","response":{"type":"tool","name":"sessions_spawn","arguments":{"agentId":"background-worker","task":"please do the background job and report the result"}}}'
curl -s -X POST http://127.0.0.1:8113/control/push -d '{"match":"SPAWN-P","response":{"type":"text","text":"PARENT_ACK_P"}}'

sed "s#RIG_DIR#$RIG#g" "$RIG/openclaw.tmpl.json" > "$RIG/openclaw.c.json"
cd "$PRISTINE"
OPENCLAW_STATE_DIR="$RIG/state-c" OPENCLAW_CONFIG_PATH="$RIG/openclaw.c.json" \
nohup node openclaw.mjs gateway --port 19301 > "$RIG/logs/gateway-pristine.log" 2>&1 &

for i in $(seq 1 90); do
  curl -s -o /dev/null http://127.0.0.1:19301 && break
  sleep 2
done
sleep 3

echo "=== pristine main $(git -C "$PRISTINE" rev-parse --short HEAD): /v1/responses spawn, NO target headers ===" > "$RIG/logs/pristine-repro.log"
curl -s http://127.0.0.1:19301/v1/responses -X POST \
  -H "Authorization: Bearer rig-secret" -H "Content-Type: application/json" \
  -H "x-openclaw-session-key: agent:main:pristine-1" \
  -H "x-openclaw-message-channel: orchestrator" \
  -d '{"model":"openclaw/main","input":"SPAWN-P please run the background job","stream":false}' | head -c 400 >> "$RIG/logs/pristine-repro.log"
echo >> "$RIG/logs/pristine-repro.log"
sleep 90
echo "=== gateway log: announce lines ===" >> "$RIG/logs/pristine-repro.log"
grep -aE "announce|In-process gateway dispatch" "$RIG/logs/gateway-pristine.log" | head -8 >> "$RIG/logs/pristine-repro.log"
grep -aE "In-process gateway dispatch" /tmp/openclaw/openclaw-*.log 2>/dev/null | grep -o "Subagent completion direct announce failed[^\"]*" | head -4 >> "$RIG/logs/pristine-repro.log"
echo PRISTINE_REPRO_DONE >> "$RIG/logs/status"
