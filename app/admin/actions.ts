"use server";

import { createClient as createServiceClient } from "@supabase/supabase-js";
import { revalidatePath } from "next/cache";
import { start } from "workflow/api";
import { buildAdminClientReport, type AdminReportMachine } from "@/lib/admin-report";
import { renderManagedHynEmail, sendResendEmail } from "@/lib/cloud-email";
import { normalizeNodeCommand } from "@/lib/node-command";
import { createClient } from "@/lib/supabase/server";
import { SUPABASE_URL } from "@/lib/supabase/config";
import { monitorNodeUpdate } from "@/workflows/node-update";

export type SaveTemplateResult = { ok: true } | { ok: false; error: string };
export type AdminActionResult = { ok: true; message: string } | { ok: false; error: string };
export type BulkUpdateResult = {
  ok: boolean;
  queued: string[];
  skipped: string[];
  failed: Array<{ nodeId: string; error: string }>;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function errorMessage(reason: unknown) {
  return reason instanceof Error ? reason.message : "The operation failed.";
}

async function authenticatedAdmin() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) throw new Error("You must sign in again.");
  const { data: admin, error } = await supabase.rpc("hyn_is_super_admin");
  if (error || admin !== true) throw new Error("An active administrator account is required.");
  return { supabase, user: auth.user };
}

export async function saveNotificationTemplate(
  templateKey: string,
  htmlTemplate: string
): Promise<SaveTemplateResult> {
  if (!['alert', 'report', 'system'].includes(templateKey)) {
    return { ok: false, error: "Unknown notification template." };
  }
  if (!htmlTemplate.includes("{{content}}")) {
    return { ok: false, error: "The template must include {{content}}." };
  }
  if (new TextEncoder().encode(htmlTemplate).length > 100_000) {
    return { ok: false, error: "The template must be smaller than 100 KB." };
  }
  if (/<\s*(script|iframe|object|embed|form)\b/i.test(htmlTemplate)) {
    return { ok: false, error: "Scripts, frames, objects, embeds, and forms are not allowed in email templates." };
  }
  if (/\son[a-z]+\s*=/i.test(htmlTemplate)) {
    return { ok: false, error: "Inline event handlers are not allowed in email templates." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("hyn_admin_save_template", {
    p_template_key: templateKey,
    p_html_template: htmlTemplate,
  });
  if (error) return { ok: false, error: error.message };

  revalidatePath("/admin");
  return { ok: true };
}

export async function sendAdminClientReport(clientId: string): Promise<AdminActionResult> {
  if (!UUID.test(clientId)) return { ok: false, error: "A valid client is required." };

  let reportId: string | null = null;
  try {
    const { supabase } = await authenticatedAdmin();
    const { data: claim, error: claimError } = await supabase.rpc("hyn_claim_admin_report", {
      p_target_user: clientId,
    });
    if (claimError) throw claimError;
    const claimed = claim as Record<string, unknown> | null;
    reportId = typeof claimed?.id === "string" ? claimed.id : null;
    if (!reportId) throw new Error("The report queue returned an invalid response.");

    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
    const resendKey = process.env.RESEND_API_KEY ?? "";
    const from = process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>";
    if (!SUPABASE_URL || !serviceKey || !resendKey) {
      throw new Error("Managed email delivery is not configured on the portal.");
    }
    const service = createServiceClient(SUPABASE_URL, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await supabase.rpc("hyn_complete_admin_report", {
      p_report_id: reportId,
      p_status: "sending",
      p_provider_id: null,
      p_error: null,
    });

    const [{ data: profile, error: profileError }, { data: nodeRows, error: nodesError }] = await Promise.all([
      service.from("profiles").select("id,email,full_name,status").eq("id", clientId).single(),
      service.from("nodes")
        .select("id,owner,name,hostname,os,agent_version,last_seen_at,last_heartbeat_at")
        .eq("owner", clientId)
        .eq("revoked", false)
        .eq("is_demo", false)
        .eq("status", "active")
        .order("name"),
    ]);
    if (profileError || nodesError) throw profileError ?? nodesError;
    if (!profile || profile.status !== "active" || !profile.email) {
      throw new Error("The selected active client does not have an email address.");
    }
    if (!nodeRows?.length) throw new Error("The selected client has no active linked machines.");

    const machines: AdminReportMachine[] = await Promise.all(nodeRows.map(async (node) => {
      const [metricResult, speedResult, alertResult] = await Promise.all([
        service.from("metrics")
          .select("cpu_pct,cpu_temp_c,cpu_model,cpu_cores,mem_pct,mem_total,mem_used,disk_pct,net_iface,net_rx_bps,net_tx_bps,net_link_mbps,sensors,payload")
          .eq("node_id", node.id).order("ts", { ascending: false }).limit(1).maybeSingle(),
        service.from("speedtests")
          .select("down_bps,up_bps,latency_ms")
          .eq("node_id", node.id).order("ts", { ascending: false }).limit(1).maybeSingle(),
        service.from("alert_events")
          .select("severity,message")
          .eq("node_id", node.id).eq("resolved", false).order("ts", { ascending: false }).limit(50),
      ]);
      const queryError = metricResult.error ?? speedResult.error ?? alertResult.error;
      if (queryError) throw queryError;
      return {
        id: node.id,
        name: node.name,
        hostname: node.hostname,
        os: node.os,
        agentVersion: node.agent_version,
        lastHeartbeatAt: node.last_heartbeat_at,
        lastSeenAt: node.last_seen_at,
        alerts: alertResult.data ?? [],
        metric: metricResult.data,
        speedtest: speedResult.data,
      } as AdminReportMachine;
    }));

    const clientLabel = profile.full_name || profile.email;
    const report = buildAdminClientReport({
      clientLabel,
      generatedAt: new Date().toISOString(),
      machines,
    });
    const { data: template } = await service.from("notification_templates")
      .select("html_template").eq("template_key", "report").maybeSingle();
    const html = renderManagedHynEmail({
      template: template?.html_template ?? "{{content}}",
      values: {
        subject: report.subject,
        hostname: `${machines.length} active HYN machine${machines.length === 1 ? "" : "s"}`,
        version: "fleet",
        severity: "info",
        content: report.content,
      },
      preview: report.preview,
    });
    const delivery = await sendResendEmail({
      apiKey: resendKey,
      from,
      to: profile.email,
      subject: report.subject,
      html,
      idempotencyKey: `admin-report:${reportId}`,
    });
    await service.from("notification_log").insert({
      node_id: machines[0].id,
      owner: clientId,
      kind: "resend-cloud",
      target: profile.email,
      severity: "info",
      subject: report.subject,
      status: delivery.ok ? "sent" : "failed",
      error: delivery.ok ? null : delivery.error,
      category: "report",
    });
    if (!delivery.ok) throw new Error(delivery.error);
    const { error: completeError } = await supabase.rpc("hyn_complete_admin_report", {
      p_report_id: reportId,
      p_status: "sent",
      p_provider_id: delivery.providerId,
      p_error: null,
    });
    if (completeError) throw completeError;
    revalidatePath("/admin");
    return { ok: true, message: `Current report sent to ${profile.email}.` };
  } catch (reason) {
    const message = errorMessage(reason);
    if (reportId) {
      try {
        const { supabase } = await authenticatedAdmin();
        await supabase.rpc("hyn_complete_admin_report", {
          p_report_id: reportId,
          p_status: "failed",
          p_provider_id: null,
          p_error: message,
        });
      } catch {
        // Preserve the original report failure for the administrator.
      }
    }
    return { ok: false, error: message };
  }
}

export async function requestAdminNodeUpdates(nodeIds: string[]): Promise<BulkUpdateResult> {
  const unique = [...new Set(nodeIds)].filter((id) => UUID.test(id)).slice(0, 200);
  const result: BulkUpdateResult = { ok: true, queued: [], skipped: [], failed: [] };
  if (unique.length === 0) return { ...result, ok: false, failed: [{ nodeId: "", error: "No valid machines were selected." }] };
  try {
    const { supabase } = await authenticatedAdmin();
    for (const nodeId of unique) {
      const { data, error } = await supabase.rpc("hyn_admin_request_node_command", {
        p_node_id: nodeId,
        p_command: "update",
      });
      if (error) {
        result.failed.push({ nodeId, error: error.message });
        continue;
      }
      const raw = data as Record<string, unknown> | null;
      const command = normalizeNodeCommand(raw);
      if (!command) {
        result.failed.push({ nodeId, error: "Invalid command response." });
        continue;
      }
      if (raw?.created === true) {
        result.queued.push(nodeId);
        try {
          await start(monitorNodeUpdate, [command.id]);
        } catch (reason) {
          console.error("[admin-update] timeout monitor did not start", nodeId, reason);
        }
      } else {
        result.skipped.push(nodeId);
      }
    }
  } catch (reason) {
    result.ok = false;
    result.failed.push({ nodeId: "", error: errorMessage(reason) });
  }
  result.ok = result.failed.length === 0;
  revalidatePath("/admin");
  return result;
}
