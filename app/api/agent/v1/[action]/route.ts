import { createClient } from "@supabase/supabase-js";
import { after, NextResponse } from "next/server";
import { start } from "workflow/api";
import {
  agentRpcForAction,
  enrichIngestWithPublicIp,
  MAX_AGENT_BODY_BYTES,
  observedPublicIp,
} from "@/lib/agent-api";
import { buildSystemSummaryContent, renderHynEmailShell, sendResendEmail } from "@/lib/cloud-email";
import { dispatchScheduledEmails } from "@/lib/scheduled-email";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/supabase/config";
import {
  dispatchCommandNotification,
  dispatchQueuedWebNotification,
  retryNodeCommandNotification,
} from "@/lib/web-notification";
import { monitorNodeHeartbeat } from "@/workflows/heartbeat-watchdog";

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

  const response = data as Record<string, unknown> | null;
  if (rpc === "hyn_queue_web_notification") {
    const jobId = typeof response?.id === "string" ? response.id : null;
    if (jobId) {
      after(async () => {
        try {
          await dispatchQueuedWebNotification(jobId);
        } catch (dispatchError) {
          console.error("[web-notification] dispatch failed; the next heartbeat will retry it", dispatchError);
        }
      });
    }
  }

  if (rpc === "hyn_report_node_command") {
    const commandId = typeof body.p_command_id === "string" ? body.p_command_id : null;
    const terminal = body.p_status === "succeeded" || body.p_status === "failed";
    if (commandId && terminal) {
      after(async () => {
        try {
          await dispatchCommandNotification(commandId);
        } catch (notificationError) {
          console.error("[node-command] completion email failed; next heartbeat will retry it", notificationError);
        }
      });
    }
  }

  if (rpc === "hyn_fetch_config") {
    const nodeId = typeof response?.node_id === "string" ? response.node_id : null;
    const watchdog = response?.watchdog && !Array.isArray(response.watchdog)
      && typeof response.watchdog === "object"
      ? response.watchdog as Record<string, unknown>
      : null;
    after(async () => {
      try {
        await dispatchQueuedWebNotification();
      } catch (dispatchError) {
        console.error("[web-notification] retry failed", dispatchError);
      }
      if (nodeId) {
        try {
          await retryNodeCommandNotification(nodeId);
        } catch (notificationError) {
          console.error("[node-command] completion email retry failed", notificationError);
        }
      }
      if (nodeId && watchdog?.created === true) {
        try {
          const run = await start(monitorNodeHeartbeat, [nodeId]);
          const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
          if (serviceKey) {
            const service = createClient(SUPABASE_URL, serviceKey, {
              auth: { persistSession: false, autoRefreshToken: false },
            });
            await service.from("node_watchdogs").update({
              state: "running",
              run_id: run.runId,
              updated_at: new Date().toISOString(),
            }).eq("node_id", nodeId);
          }
        } catch (watchdogError) {
          console.error("[heartbeat-watchdog] could not start", watchdogError);
        }
      }
    });
  }

  if (rpc === "hyn_ingest") {
    const nodeToken = typeof body.p_node_token === "string" ? body.p_node_token : "";
    const nodeId = typeof response?.node_id === "string" ? response.node_id : null;
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
          node_id?: string;
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
            from: process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>",
            to: email.recipient,
            subject,
            html: renderHynEmailShell({
              subject,
              preview: "Your first complete HYN-view system report is ready.",
              hostname: email.hostname ?? email.node_name ?? "linked machine",
              severity: "info",
              content: buildSystemSummaryContent({
                nodeName: email.node_name ?? email.hostname ?? "linked machine",
                os: email.os ?? null,
                agentVersion: email.agent_version ?? null,
                lastSeenAt: email.last_seen_at ?? null,
                payload: email.payload ?? null,
              }),
            }),
            idempotencyKey: `first-system:${email.node_id ?? nodeToken.slice(0, 12)}`,
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
        if (nodeId) {
          try {
            await dispatchScheduledEmails(nodeId);
          } catch (scheduledError) {
            console.error("[scheduled-email] telemetry-triggered dispatch failed", scheduledError);
          }
        }
      });
    }
  }
  return NextResponse.json(data, {
    headers: { "Cache-Control": "no-store" },
  });
}
