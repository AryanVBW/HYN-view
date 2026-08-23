import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import {
  buildDailyDigestContent,
  buildIncidentContent,
  buildSystemSummaryContent,
  localDateAndTime,
  novelIncidentEvents,
  scheduleIsDue,
  renderManagedHynEmail,
  sendResendEmail,
} from "@/lib/cloud-email";
import { SUPABASE_URL } from "@/lib/supabase/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

type PreferenceRow = {
  node_id: string; recipient: string; timezone: string;
  incident_enabled: boolean; daily_enabled: boolean; daily_at: string;
  system_enabled: boolean; system_at: string;
  last_daily_local_date: string | null; last_system_local_date: string | null;
  last_alert_id: number;
  nodes: { id: string; owner: string; name: string; hostname: string | null; os: string | null; agent_version: string | null; last_seen_at: string | null; status: string; revoked: boolean; is_demo: boolean };
};
type MetricRow = { cpu_pct: number | null; cpu_temp_c: number | null; mem_pct: number | null; net_rx_bps: number | null; net_tx_bps: number | null; latency_ms: number | null; uptime_s: number | null; payload: Record<string, unknown> | null; ts: string };

const average = (values: Array<number | null>) => {
  const present = values.map(Number).filter(Number.isFinite);
  return present.length ? present.reduce((sum, value) => sum + value, 0) / present.length : null;
};
const peak = (values: Array<number | null>) => {
  const present = values.map(Number).filter(Number.isFinite);
  return present.length ? Math.max(...present) : null;
};

export async function GET(request: Request) {
  const cronSecret = process.env.CRON_SECRET ?? "";
  if (!cronSecret || request.headers.get("authorization") !== `Bearer ${cronSecret}`) return NextResponse.json({ message: "unauthorized" }, { status: 401 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  const resendKey = process.env.RESEND_API_KEY ?? "";
  const from = process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.in>";
  if (!SUPABASE_URL || !serviceKey || !resendKey) return NextResponse.json({ message: "email automation is not configured" }, { status: 503 });

  const supabase = createClient(SUPABASE_URL, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const [preferencesResult, templatesResult] = await Promise.all([
    supabase.from("email_preferences").select("*,nodes!inner(id,owner,name,hostname,os,agent_version,last_seen_at,status,revoked,is_demo)").eq("nodes.revoked", false).eq("nodes.is_demo", false).limit(500),
    supabase.from("notification_templates").select("template_key,html_template"),
  ]);
  if (preferencesResult.error || templatesResult.error) return NextResponse.json({ message: preferencesResult.error?.message ?? templatesResult.error?.message }, { status: 500 });

  const templates = new Map((templatesResult.data ?? []).map((row) => [row.template_key, row.html_template]));
  const now = new Date();
  const since = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
  let sent = 0, failed = 0, skipped = 0;

  async function deliver(args: { preference: PreferenceRow; kind: "alert" | "report" | "system"; idempotencyKey: string; subject: string; severity: "info" | "warn" | "crit"; content: string }) {
    const claim = await supabase.from("cloud_email_dispatches").insert({ idempotency_key: args.idempotencyKey, node_id: args.preference.node_id, kind: args.kind });
    if (claim.error) { if (claim.error.code === "23505") skipped += 1; else failed += 1; return false; }
    const node = args.preference.nodes;
    const html = renderManagedHynEmail({
      template: templates.get(args.kind) ?? "{{content}}",
      values: { subject: args.subject, hostname: node.hostname ?? node.name, version: node.agent_version ?? "unknown", severity: args.severity, content: args.content },
      preview: args.subject,
    });
    const delivery = await sendResendEmail({ apiKey: resendKey, from, to: args.preference.recipient, subject: args.subject, html, idempotencyKey: args.idempotencyKey });
    const ok = delivery.ok;
    await supabase.from("notification_log").insert({ node_id: node.id, owner: node.owner, kind: "resend-cloud", target: args.preference.recipient, severity: args.severity, subject: args.subject, status: ok ? "sent" : "failed", error: ok ? null : delivery.error, category: args.kind === "alert" ? "alert" : "report" });
    if (!ok) { await supabase.from("cloud_email_dispatches").delete().eq("idempotency_key", args.idempotencyKey); failed += 1; return false; }
    await supabase.from("cloud_email_dispatches").update({ provider_id: delivery.providerId }).eq("idempotency_key", args.idempotencyKey);
    sent += 1; return true;
  }

  for (const rawPreference of preferencesResult.data ?? []) {
    const preference = rawPreference as unknown as PreferenceRow;
    const node = preference.nodes;
    const local = localDateAndTime(now, preference.timezone);
    if (!local || node.status !== "active") { skipped += 1; continue; }

    if (preference.incident_enabled) {
      const alertResult = await supabase.from("alert_events").select("id,rule,ts,severity,message,resolved").eq("node_id", node.id).gt("id", preference.last_alert_id).order("id", { ascending: true }).limit(50);
      const incoming = alertResult.data ?? [];
      if (incoming.length) {
        const lastId = Number(incoming.at(-1)?.id ?? preference.last_alert_id);
        const previousResult = preference.last_alert_id > 0
          ? await supabase.from("alert_events").select("id,rule,ts,severity,message,resolved").eq("node_id", node.id).lte("id", preference.last_alert_id).order("id", { ascending: false }).limit(200)
          : { data: [] };
        const events = novelIncidentEvents(incoming, previousResult.data ?? []);
        if (events.length === 0) {
          await supabase.from("email_preferences").update({ last_alert_id: lastId }).eq("node_id", node.id);
        } else {
          const severity = events.some((event) => event.severity === "crit") ? "crit" : "warn";
          const ok = await deliver({ preference, kind: "alert", idempotencyKey: `alert:${node.id}:${lastId}`, subject: `[HYN ${severity.toUpperCase()}] ${node.name}: ${events.length} incident update${events.length === 1 ? "" : "s"}`, severity, content: buildIncidentContent(events) });
          if (ok) await supabase.from("email_preferences").update({ last_alert_id: lastId }).eq("node_id", node.id);
        }
      }
    }

    const dailyDue = preference.daily_enabled && scheduleIsDue(now, preference.timezone, preference.daily_at.slice(0, 5), preference.last_daily_local_date);
    const systemDue = preference.system_enabled && scheduleIsDue(now, preference.timezone, preference.system_at.slice(0, 5), preference.last_system_local_date);
    if (!dailyDue && !systemDue) continue;
    const metricResult = await supabase.from("metrics").select("cpu_pct,cpu_temp_c,mem_pct,net_rx_bps,net_tx_bps,latency_ms,uptime_s,payload,ts").eq("node_id", node.id).gte("ts", since).order("ts", { ascending: false }).limit(500);
    const metrics = (metricResult.data ?? []) as MetricRow[];
    const latest = metrics[0] ?? null;

    if (dailyDue) {
      const ok = await deliver({ preference, kind: "report", idempotencyKey: `report:${node.id}:${local.date}`, subject: `Daily HYN health · ${node.name} · ${local.date}`, severity: "info", content: buildDailyDigestContent({ nodeName: node.name, sampleCount: metrics.length, cpuAverage: average(metrics.map((row) => row.cpu_pct)), cpuPeak: peak(metrics.map((row) => row.cpu_pct)), memoryAverage: average(metrics.map((row) => row.mem_pct)), temperaturePeak: peak(metrics.map((row) => row.cpu_temp_c)), downloadAverageBps: average(metrics.map((row) => row.net_rx_bps)), uploadAverageBps: average(metrics.map((row) => row.net_tx_bps)), latencyAverageMs: average(metrics.map((row) => row.latency_ms)), uptimeSeconds: latest?.uptime_s ?? null }) });
      if (ok) await supabase.from("email_preferences").update({ last_daily_local_date: local.date }).eq("node_id", node.id);
    }
    if (systemDue) {
      const ok = await deliver({ preference, kind: "system", idempotencyKey: `system:${node.id}:${local.date}`, subject: `System information · ${node.name} · ${local.date}`, severity: "info", content: buildSystemSummaryContent({ nodeName: node.name, os: node.os, agentVersion: node.agent_version, lastSeenAt: node.last_seen_at, payload: latest?.payload ?? null }) });
      if (ok) await supabase.from("email_preferences").update({ last_system_local_date: local.date }).eq("node_id", node.id);
    }
  }

  return NextResponse.json({ status: "ok", sent, failed, skipped, checked: preferencesResult.data?.length ?? 0 });
}
