import { handleAgentRpc, pruneTelemetry } from "./agent.ts";
import { ensureProfile } from "./access.ts";
import { bearer, json, jsonMessage, readJsonObject, RpcError } from "./http.ts";
import { verifySupabaseJwt } from "./jwt.ts";
import { handlePortalRpc } from "./portal.ts";
import type { Session } from "./types.ts";

const AGENT_RPCS = new Set([
  "hyn_device_start",
  "hyn_device_poll",
  "hyn_ingest",
  "hyn_fetch_config",
  "hyn_heartbeat",
  "hyn_record_bandwidth",
  "hyn_local_heartbeat",
  "hyn_fetch_local_config",
  "hyn_transient_snapshot",
  "hyn_report_notification",
  "hyn_claim_node_command",
  "hyn_report_node_command",
  "hyn_queue_web_notification",
]);

const AGENT_MAX = 1_048_576;
const PORTAL_MAX = 262_144;

function pepper(env: Env): string {
  return env.PAIRING_PEPPER || env.SUPABASE_JWT_SECRET || "";
}

function jwksUrl(env: Env): string | undefined {
  const base = (env.SUPABASE_URL ?? "").replace(/\/$/, "");
  return base ? `${base}/auth/v1/.well-known/jwks.json` : undefined;
}

async function sessionFromRequest(request: Request, env: Env): Promise<Session> {
  const token = bearer(request);
  if (!token) throw new RpcError("not authenticated", 401);
  if (env.DATA_SERVICE_KEY && token === env.DATA_SERVICE_KEY) {
    return {
      userId: "service",
      email: null,
      service: true,
      profile: {
        id: "service",
        email: null,
        full_name: null,
        role: "super_admin",
        status: "active",
        suspended_reason: null,
        created_at: new Date(0).toISOString(),
        updated_at: new Date(0).toISOString(),
      },
    };
  }
  const user = await verifySupabaseJwt(token, {
    secret: env.SUPABASE_JWT_SECRET || undefined,
    issuer: env.SUPABASE_JWT_ISS || undefined,
    jwksUrl: jwksUrl(env),
  });
  const profile = await ensureProfile(env.DB, user.id, user.email, env.BOOTSTRAP_EMAIL || null);
  return { userId: user.id, email: user.email, profile, service: false };
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/api/agent/v1/health")) {
        return json({ service: "hyn-agent-v1", store: "d1" });
      }
      if (request.method === "POST" && url.pathname.startsWith("/api/agent/v1/")) {
        const action = url.pathname.slice("/api/agent/v1/".length);
        if (!AGENT_RPCS.has(action)) return jsonMessage("unknown agent action", 404);
        const body = await readJsonObject(request, AGENT_MAX);
        const result = await handleAgentRpc(env.DB, action, body, pepper(env));
        return json(result);
      }
      if (request.method === "POST" && url.pathname.startsWith("/rpc/")) {
        const name = url.pathname.slice("/rpc/".length);
        const session = await sessionFromRequest(request, env);
        const body = await readJsonObject(request, PORTAL_MAX);
        if (AGENT_RPCS.has(name) && session.service) {
          return json(await handleAgentRpc(env.DB, name, body, pepper(env)));
        }
        return json(await handlePortalRpc(env.DB, session, name, body, pepper(env)));
      }
      return jsonMessage("not found", 404);
    } catch (error) {
      if (error instanceof RpcError) return jsonMessage(error.message, error.status);
      console.error(JSON.stringify({ err: error instanceof Error ? error.message : "error" }));
      return jsonMessage("internal error", 500);
    }
  },
  async scheduled(_event, env, ctx): Promise<void> {
    ctx.waitUntil(pruneTelemetry(env.DB, 5000).then((deleted) => {
      console.log(JSON.stringify({ cron: "telemetry-prune", deleted }));
    }));
  },
} satisfies ExportedHandler<Env>;
