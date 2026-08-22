// Scriptable mock OpenAI Responses SSE provider for the delivery-target rig.
// POST /control/push {match, response} — FIFO-among-matches substring rules.
//   response: {type:"text", text} | {type:"tool", name, arguments:{...}}
// POST /control/reset, GET /control/log
// POST */responses — matches body against rules, consumes first hit, replies SSE.
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const PORT = Number(process.env.MOCK_LLM_PORT || 8113);
const CAP_DIR = path.join(__dirname, "captured");
fs.mkdirSync(CAP_DIR, { recursive: true });

let rules = [];
let reqN = 0;
const log = [];

function sseEvent(res, obj) {
  res.write(`event: ${obj.type}\n`);
  res.write(`data: ${JSON.stringify(obj)}\n\n`);
}

function readBody(req, cb) {
  let chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => cb(Buffer.concat(chunks).toString("utf-8")));
}

const server = http.createServer((req, res) => {
  if (req.url.startsWith("/control/push") && req.method === "POST") {
    return readBody(req, (b) => {
      rules.push(JSON.parse(b));
      res.writeHead(200).end(JSON.stringify({ ok: true, rules: rules.length }));
    });
  }
  if (req.url.startsWith("/control/reset") && req.method === "POST") {
    rules = [];
    return res.writeHead(200).end('{"ok":true}');
  }
  if (req.url.startsWith("/control/log")) {
    return res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(log, null, 1));
  }
  if (req.method === "POST" && req.url.includes("/responses")) {
    return readBody(req, (b) => {
      reqN += 1;
      const n = reqN;
      fs.writeFileSync(path.join(CAP_DIR, `req-${String(n).padStart(4, "0")}.json`), JSON.stringify({ url: req.url, headers: req.headers, body: JSON.parse(b) }, null, 1));
      const idx = rules.findIndex((r) => b.includes(r.match));
      const rule = idx >= 0 ? rules.splice(idx, 1)[0] : { match: null, response: { type: "text", text: "NO_RULE_MATCHED" } };
      log.push({ n, matched: rule.match, kind: rule.response.type });
      console.log(`[mock-llm] REQ${n} matched=${JSON.stringify(rule.match)} kind=${rule.response.type}`);

      const respId = `resp_mock_${n}`;
      let item;
      if (rule.response.type === "tool") {
        item = {
          id: `fc_${n}`,
          call_id: `call_${n}`,
          type: "function_call",
          name: rule.response.name,
          arguments: JSON.stringify(rule.response.arguments),
          status: "completed",
        };
      } else {
        item = {
          id: `msg_${n}`,
          type: "message",
          role: "assistant",
          status: "completed",
          content: [{ type: "output_text", text: rule.response.text, annotations: [] }],
        };
      }
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store" });
      sseEvent(res, { type: "response.created", sequence_number: 1, response: { id: respId, status: "in_progress", output: [] } });
      sseEvent(res, { type: "response.output_item.done", sequence_number: 2, output_index: 0, item });
      sseEvent(res, {
        type: "response.completed",
        sequence_number: 3,
        response: {
          id: respId,
          status: "completed",
          output: [item],
          usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
        },
      });
      res.end();
    });
  }
  res.writeHead(404).end("not found");
});

server.listen(PORT, "127.0.0.1", () => console.log(`[mock-llm] listening on 127.0.0.1:${PORT}`));
