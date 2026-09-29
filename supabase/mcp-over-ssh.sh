#!/usr/bin/env bash
# Supabase MCP for the self-hosted database on server02, as a local stdio MCP
# server for Kiro or any other MCP client.
#
# Studio's MCP endpoint has no authentication, so the API gateway denies /mcp
# and /api/mcp and it must never be reachable through data.hyn-view.in. (The
# Supabase guide's IP allow-list does not help here: the gateway sees every
# request, including Cloudflare's, as coming from 172.18.0.1.) This script
# reaches it over SSH instead: key login to server02 (host "hyn" goes through
# the Cloudflare tunnel, ssh.hyn-view.in), into the LXD container and the
# Studio container. There the bridge below posts each JSON-RPC line to Studio
# on loopback and writes the reply back. Nothing is opened on the server.
#
# Kiro (.kiro/settings/mcp.json):
#   "supabase": { "command": "/bin/bash", "args": ["<repo>/supabase/mcp-over-ssh.sh"] }
#
#   HYN_MCP_HOST   ssh host alias (default hyn; hyn-lan on the local network)
#   HYN_MCP_QUERY  Studio MCP options (default read_only=true: SQL runs read-only;
#                  read_only=false allows writes)
set -euo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" # cloudflared, for the ssh ProxyCommand
host=${HYN_MCP_HOST:-hyn}
query=${HYN_MCP_QUERY-read_only=true}
allowed='^[A-Za-z0-9_=,&%.-]*$'
[[ $query =~ $allowed ]] || { echo "mcp-over-ssh: HYN_MCP_QUERY has unsupported characters" >&2; exit 64; }

IFS= read -r -d '' bridge <<'JS' || true
// Runs inside the supabase-studio container: one MCP JSON-RPC message per line
// on stdin, forwarded to Studio's MCP endpoint on loopback, replies written to
// stdout one per line. A request that fails is answered with a JSON-RPC error
// for its id, so the client never waits for a reply that cannot come.
const http = require("node:http");
const url = "http://127.0.0.1:3000/api/mcp" + (process.argv[2] || "");
let version = null;
let session = null;
let pending = "";
const send = (message) => process.stdout.write(JSON.stringify(message) + "\n");
const fail = (id, message) => {
  if (id !== undefined) send({ jsonrpc: "2.0", id, error: { code: -32603, message } });
};
const sse = (body) => body.split(/\r?\n\r?\n/)
  .map((block) => block.split(/\r?\n/).filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).replace(/^ /, "")).join("\n"))
  .filter(Boolean);

// A new loopback connection per request: reusing a kept-alive socket raced
// Studio closing it after an error reply ("fetch failed" on the next call).
function post(body, headers) {
  return new Promise((resolve, reject) => {
    const request = http.request(url, {
      method: "POST", agent: false, timeout: 110000,
      headers: { ...headers, "content-length": Buffer.byteLength(body) },
    }, (response) => {
      let data = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { data += chunk; });
      response.on("end", () => resolve({ status: response.statusCode, headers: response.headers, body: data }));
      response.on("error", reject);
    });
    request.on("timeout", () => request.destroy(new Error("no reply within 110 s")));
    request.on("error", reject);
    request.end(body);
  });
}

async function forward(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  }
  const request = message && typeof message === "object" && !Array.isArray(message) && "method" in message;
  const id = request ? message.id : undefined;
  const headers = { "content-type": "application/json", accept: "application/json, text/event-stream" };
  if (version) headers["mcp-protocol-version"] = version;
  if (session) headers["mcp-session-id"] = session;
  try {
    const response = await post(line, headers);
    session = response.headers["mcp-session-id"] || session;
    const body = response.body;
    if (response.status < 200 || response.status > 299) {
      return fail(id, `Supabase MCP answered HTTP ${response.status}: ${body.slice(0, 500)}`);
    }
    const replies = String(response.headers["content-type"] || "").includes("text/event-stream")
      ? sse(body) : body.trim() ? [body] : [];
    for (const text of replies) {
      const reply = JSON.parse(text);
      if (request && message.method === "initialize" && reply.result && reply.result.protocolVersion) {
        version = reply.result.protocolVersion;
      }
      send(reply);
    }
  } catch (error) {
    fail(id, `Supabase MCP bridge: ${error.message}`);
  }
}

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  pending += chunk;
  for (let at = pending.indexOf("\n"); at >= 0; at = pending.indexOf("\n")) {
    const line = pending.slice(0, at).trim();
    pending = pending.slice(at + 1);
    if (line) forward(line);
  }
});
process.stdin.on("end", () => {
  if (pending.trim()) forward(pending.trim());
});
JS

encoded=$(printf '%s' "$bridge" | base64 | tr -d '\n')
exec ssh -o BatchMode=yes -o ConnectTimeout=20 -T "$host" \
  "lxc exec supabase --mode=non-interactive -- docker exec -i supabase-studio node -e 'eval(Buffer.from(process.argv[1],\"base64\").toString())' $encoded '?$query'"
