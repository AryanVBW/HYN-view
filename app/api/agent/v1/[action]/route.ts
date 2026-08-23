import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { agentRpcForAction, MAX_AGENT_BODY_BYTES } from "@/lib/agent-api";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/supabase/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function jsonError(status: number, message: string) {
  return NextResponse.json({ message }, { status });
}

export async function POST(
  request: Request,
  context: { params: Promise<{ action: string }> }
) {
  const { action } = await context.params;
  const rpc = agentRpcForAction(action);
  if (!rpc) return jsonError(404, "unknown agent action");
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return jsonError(503, "agent API is not configured");
  }

  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_AGENT_BODY_BYTES) {
    return jsonError(413, "agent request exceeds 1 MB");
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_AGENT_BODY_BYTES) {
    return jsonError(413, "agent request exceeds 1 MB");
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw || "{}") as Record<string, unknown>;
  } catch {
    return jsonError(400, "request body must be valid JSON");
  }
  if (!body || Array.isArray(body) || typeof body !== "object") {
    return jsonError(400, "request body must be a JSON object");
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.rpc(rpc, body);
  if (error) {
    const message = error.message || "agent request failed";
    const status = /invalid node token|revoked/i.test(message) ? 401 : 400;
    return jsonError(status, message);
  }
  return NextResponse.json(data, {
    headers: { "Cache-Control": "no-store" },
  });
}
