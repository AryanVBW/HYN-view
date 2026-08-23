import { createClient } from "@supabase/supabase-js";
import { after, NextResponse } from "next/server";
import {
  agentRpcForAction,
  enrichIngestWithPublicIp,
  MAX_AGENT_BODY_BYTES,
  observedPublicIp,
} from "@/lib/agent-api";
import { buildSystemSummaryContent, sendResendEmail } from "@/lib/cloud-email";
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

  if (rpc === "hyn_ingest") {
    body = enrichIngestWithPublicIp(
      body,
      request.headers.get("x-forwarded-for") ?? request.headers.get("x-real-ip"),
    );
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

  if (rpc === "hyn_ingest") {
    const nodeToken = typeof body.p_node_token === "string" ? body.p_node_token : "";
    if (nodeToken) {
      const publicIp = observedPublicIp(
        request.headers.get("x-forwarded-for") ?? request.headers.get("x-real-ip"),
      );
      after(async () => {
        const { data: claim } = await supabase.rpc("hyn_claim_first_telemetry_email", {
          p_node_token: nodeToken,
          p_public_ip: publicIp,
        });
        const email = claim as null | {
          status?: string;
          node_name?: string;
          hostname?: string | null;
          os?: string | null;
          agent_version?: string | null;
          last_seen_at?: string | null;
          recipient?: string;
          payload?: Record<string, unknown>;
        };
        if (email?.status === "send" && email.recipient) {
          const subject = `Your first HYN system report · ${email.node_name ?? "linked machine"}`;
          const delivery = await sendResendEmail({
            apiKey: process.env.RESEND_API_KEY ?? "",
            from: process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.in>",
            to: email.recipient,
            subject,
            html: buildSystemSummaryContent({
              nodeName: email.node_name ?? email.hostname ?? "linked machine",
              os: email.os ?? null,
              agentVersion: email.agent_version ?? null,
              lastSeenAt: email.last_seen_at ?? null,
              payload: email.payload ?? null,
            }),
          });
          await supabase.rpc("hyn_report_notification", {
            p_node_token: nodeToken,
            p_events: [{
              kind: "resend-cloud",
              target: email.recipient,
              severity: "info",
              subject,
              status: delivery.ok ? "sent" : "failed",
              error: delivery.ok ? null : delivery.error,
              category: "report",
            }],
          });
          if (delivery.ok) {
            await supabase.rpc("hyn_complete_first_telemetry_email", {
              p_node_token: nodeToken,
              p_provider_id: delivery.providerId,
            });
          } else {
            await supabase.rpc("hyn_release_first_telemetry_email", { p_node_token: nodeToken });
          }
        }
      });
    }
  }
  return NextResponse.json(data, {
    headers: { "Cache-Control": "no-store" },
  });
}
