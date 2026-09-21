import { createClient } from "@supabase/supabase-js";
import { buildDailyDigestContent, emailPalette, escapeHtml, renderManagedHynEmail } from "./cloud-email.ts";
import { deliveryControlsEnabled, sendManagedEmail } from "./delivery-send.ts";

type DigestNode = {
  id: string; name: string; hostname: string | null; status: string; telemetry_mode: string;
  last_heartbeat_at: string | null; sample_count: number;
  cpu_average: number | null; cpu_peak: number | null; memory_average: number | null;
  temperature_peak: number | null; download_average: number | null; upload_average: number | null;
  latency_average: number | null; uptime: number | null;
};
export function renderUserDigest(name: string, date: string, nodes: DigestNode[]) {
  return `<p style="color:${emailPalette.muted}">Daily health summary for ${escapeHtml(name)} on ${escapeHtml(date)}. ${nodes.length} permitted server${nodes.length === 1 ? "" : "s"}.</p>`
    + nodes.map(node => `<section style="margin:24px 0;border-top:1px solid ${emailPalette.border};padding-top:16px"><p style="color:${emailPalette.muted}">${escapeHtml(node.hostname ?? node.name)} / ${escapeHtml(node.status)}${node.telemetry_mode === "local" ? " / Local-only telemetry: cloud history is unavailable" : ""}</p>`
      + buildDailyDigestContent({ nodeName: node.name, sampleCount: Number(node.sample_count),
        cpuAverage: node.cpu_average, cpuPeak: node.cpu_peak, memoryAverage: node.memory_average,
        temperaturePeak: node.temperature_peak, downloadAverageBps: node.download_average,
        uploadAverageBps: node.upload_average, latencyAverageMs: node.latency_average, uptimeSeconds: node.uptime,
      }) + "</section>").join("");
}

export async function dispatchUserDigests(triggerNode?: string) {
  const result = { sent: 0, failed: 0, skipped: 0, checked: 0 };
  if (!deliveryControlsEnabled() || (process.env.HYN_DATA_API_URL ?? "").replace(/\/$/, "")) return result;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Managed delivery controls are not configured");
  const database = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: targets, error } = await database.rpc("hyn_due_user_digests", { p_trigger_node: triggerNode ?? null });
  if (error) throw error;
  const { data: template } = await database.from("notification_templates").select("html_template").eq("template_key", "report").maybeSingle();
  for (const target of (targets ?? []) as { owner: string; local_date: string }[]) {
    result.checked++;
    const { data, error: contentError } = await database.rpc("hyn_user_digest_content", { p_owner: target.owner });
    if (contentError) { result.failed++; continue; }
    const digest = data as { name: string; recipient: string | null; nodes: DigestNode[] } | null;
    if (!digest?.recipient || !digest.nodes.length) { result.skipped++; continue; }
    const subject = `Daily HYN health / ${digest.name} / ${target.local_date}`;
    const delivery = await sendManagedEmail({
      apiKey: process.env.RESEND_API_KEY ?? "", from: process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>",
      to: digest.recipient, subject, idempotencyKey: `user-digest:${target.owner}:${target.local_date}`,
      delivery: { kind: "daily", ownerId: target.owner, nodeIds: digest.nodes.map(node => node.id) },
      html: renderManagedHynEmail({ template: template?.html_template, preview: "One daily summary of your permitted servers.",
        values: { subject, hostname: `${digest.nodes.length} permitted servers`, severity: "info", version: "fleet",
          content: renderUserDigest(digest.name, target.local_date, digest.nodes) } }),
    });
    if (delivery.ok) result.sent++;
    else if (delivery.deferred) result.skipped++;
    else result.failed++;
  }
  return result;
}
