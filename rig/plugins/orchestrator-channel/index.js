// orchestrator-channel — the persond delivery channel for OpenClaw.
//
// Outbound-only: every send the OpenClaw runtime performs on this channel
// (the built-in `message` tool is the one producer in this deployment)
// becomes an HTTP POST to the persond orchestrator's assistant API, which
// resolves the caller by X-Container-Id and forwards to the caller's own
// user's Telegram chat — the same endpoints, auth and per-user isolation the
// retired reminders__send_message / reminders__send_photo MCP tools used:
//
//   text  → POST /internal/send        {text}
//   media → POST /internal/media/send  {path, caption}   (path = the object's
//           storage key in the assistant's own media library, passed through
//           verbatim — this channel never reads media bytes itself)
//
// Inbound never flows through this channel: the orchestrator drives every
// turn via /v1/responses and merely stamps the run's channel context with the
// x-openclaw-message-channel header. One container serves exactly one user,
// so every target string resolves to that user (normalizeTarget below) — the
// orchestrator ignores the target and addresses the caller's own chat.
//
// Credentials come from the gateway process's own environment (the host-agent
// injects ORCHESTRATOR_INTERNAL_URL / ORCHESTRATOR_ASSISTANT_TOKEN into the
// container; unlike MCP stdio children, an in-process plugin sees the full
// gateway env — no /proc-environ bridging or config-file fallback needed
// here). The container id is self-detected from the hostname, exactly
// like mcpserver/identity.go. All three are re-read on every send and
// missing values fail the send with a clear error — an unprovisioned host
// still boots and chats; only channel delivery degrades, mirroring
// mcpserver's errNotConfigured convention.
import { hostname } from "node:os";
import { defineChannelPluginEntry } from "openclaw/plugin-sdk/channel-core";

const CHANNEL_ID = "orchestrator";

// Same well-formedness rule the orchestrator's assistantapi enforces on the
// X-Container-Id header: 12-64 lowercase hex characters.
const CONTAINER_ID_RE = /^[0-9a-f]{12,64}$/;

function resolveOrchestratorEnv() {
  const base = process.env.ORCHESTRATOR_INTERNAL_URL;
  const token = process.env.ORCHESTRATOR_ASSISTANT_TOKEN;
  let containerId = process.env.ORCHESTRATOR_CONTAINER_ID || "";
  if (!containerId) {
    const host = hostname().toLowerCase();
    if (CONTAINER_ID_RE.test(host)) containerId = host;
  }
  return { base, token, containerId };
}

async function postOrchestrator(path, body) {
  const { base, token, containerId } = resolveOrchestratorEnv();
  if (!base || !token || !containerId) {
    throw new Error(
      "orchestrator channel is not configured on this host (ORCHESTRATOR_INTERNAL_URL / ORCHESTRATOR_ASSISTANT_TOKEN / container id unavailable)",
    );
  }
  const res = await fetch(base.replace(/\/+$/, "") + path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      "X-Container-Id": containerId,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok && res.status !== 204) {
    const detail = await res.text().catch(() => "");
    throw new Error(`orchestrator ${path}: HTTP ${res.status}${detail ? ` — ${detail}` : ""}`);
  }
}

const plugin = {
  id: CHANNEL_ID,
  meta: {
    id: CHANNEL_ID,
    label: "Orchestrator",
    selectionLabel: "Orchestrator (persond)",
    docsPath: "/",
    blurb:
      "Delivers assistant messages to the persond orchestrator, which forwards them to the user's own Telegram chat.",
    showInSetup: false,
  },
  capabilities: { chatTypes: ["direct"], media: true },
  config: {
    listAccountIds: () => ["default"],
    resolveAccount: (cfg, accountId) => ({
      accountId: accountId ?? "default",
      config: cfg.channels?.[CHANNEL_ID] ?? {},
    }),
    isEnabled: () => true,
    isConfigured: () => true,
  },
  messaging: {
    normalizeTarget: () => "user",
    targetResolver: {
      looksLikeId: () => true,
      hint: "user",
      resolveTarget: async () => ({ to: "user", kind: "user", source: "normalized" }),
    },
  },
  outbound: {
    sendText: async (ctx) => {
      await postOrchestrator("/internal/send", { text: ctx.text });
      return { channel: CHANNEL_ID, messageId: `orch-${Date.now()}` };
    },
    sendMedia: async (ctx) => {
      await postOrchestrator("/internal/media/send", {
        path: ctx.mediaUrl,
        caption: ctx.text || "",
      });
      return { channel: CHANNEL_ID, messageId: `orch-${Date.now()}` };
    },
  },
};

export default defineChannelPluginEntry({
  // The ENTRY id must match the openclaw.plugin.json manifest id (the gateway
  // refuses a mismatched export with "plugin id mismatch"); the CHANNEL keeps
  // its own id from plugin.id above.
  id: "orchestrator-channel",
  name: "Orchestrator",
  description: "persond orchestrator delivery channel (outbound-only)",
  plugin,
});
