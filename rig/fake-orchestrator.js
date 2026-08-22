// Logging fake receiver for the orchestrator-channel plugin.
// Captures every /internal/* call; GET /control/log dumps them.
const http = require("node:http");

const PORT = Number(process.env.FAKE_ORCH_PORT || 8114);
let calls = [];

const server = http.createServer((req, res) => {
  if (req.url.startsWith("/control/log")) {
    return res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(calls, null, 1));
  }
  if (req.url.startsWith("/control/reset") && req.method === "POST") {
    calls = [];
    return res.writeHead(200).end('{"ok":true}');
  }
  let chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks).toString("utf-8");
    const n = calls.length + 1;
    calls.push({ n, method: req.method, url: req.url, auth: req.headers.authorization, containerId: req.headers["x-container-id"], body });
    console.log(`receiver: CALL #${String(n).padStart(4, "0")} ${req.method} ${req.url} body=${body}`);
    res.writeHead(200, { "content-type": "application/json" }).end('{"ok":true}');
  });
});

server.listen(PORT, "127.0.0.1", () => console.log(`[fake-orchestrator] listening on 127.0.0.1:${PORT}`));
