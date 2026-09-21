"use server";

import { createClient as createServiceClient } from "@supabase/supabase-js";
import { buildAdminClientReport, type AdminReportMachine } from "@/lib/admin-report";
import {
  buildIncidentContent,
  emailPalette,
  escapeHtml,
  renderManagedHynEmail,
} from "@/lib/cloud-email";
import { sendManagedEmail } from "@/lib/delivery-send";
import { concernsFor, toFleetServers } from "@/lib/fleet-monitor";
import { createClient } from "@/lib/supabase/server";
import { SUPABASE_URL } from "@/lib/supabase/config";
import { NODE_COLUMNS, type AlertEvent, type Metric, type Node, type Speedtest } from "@/lib/types";

export type MaintainerSendResult = { ok: true; message: string } | { ok: false; error: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Authorisation is re-checked in the database, not here: hyn_can_view_fleet() is
// the same predicate the RLS policies use, so a maintainer who has been demoted
// between page load and button press is refused by the row policies too. This
// call only turns that into a readable message instead of an empty result set.
async function fleetViewer() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) throw new Error("You must sign in again.");
  const { data: allowed, error } = await supabase.rpc("hyn_can_view_fleet");
  if (error || allowed !== true) {
    throw new Error("An active Maintainer, Admin or Super admin account is required.");
  }
  if (!auth.user.email) throw new Error("This account has no email address to send to.");
  return { supabase, user: auth.user, recipient: auth.user.email };
}

function service() {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  const resendKey = process.env.RESEND_API_KEY ?? "";
  const from = process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>";
  if (!SUPABASE_URL || !serviceKey || !resendKey) {
    throw new Error("Managed email delivery is not configured on the portal.");
  }
  return {
    resendKey,
    from,
    db: createServiceClient(SUPABASE_URL, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  };
}

// One node, read through the maintainer's own session so RLS decides what they
// may see. Everything after this point is composition, not authorisation.
async function readNode(nodeId: string) {
  const { supabase, recipient } = await fleetViewer();
  const { data: nodeRow, error } = await supabase
    .from("nodes").select(NODE_COLUMNS).eq("id", nodeId).maybeSingle();
  if (error) throw error;
  if (!nodeRow) throw new Error("That server is not visible to this account.");
  const node = nodeRow as Node;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [metricRes, speedRes, alertRes] = await Promise.all([
    supabase.from("metrics").select("*").eq("node_id", nodeId)
      .order("ts", { ascending: false }).limit(1),
    supabase.from("speedtests").select("*").eq("node_id", nodeId)
      .order("ts", { ascending: false }).limit(1),
    supabase.from("alert_events").select("*").eq("node_id", nodeId)
      .gte("ts", since).order("ts", { ascending: false }).limit(50),
  ]);
  const failure = metricRes.error ?? speedRes.error ?? alertRes.error;
  if (failure) throw failure;
  return {
    node, recipient,
    metric: ((metricRes.data ?? [])[0] ?? null) as Metric | null,
    speedtest: ((speedRes.data ?? [])[0] ?? null) as Speedtest | null,
    alerts: (alertRes.data ?? []) as AlertEvent[],
  };
}

async function deliver(args: {
  kind: "admin_report" | "other";
  nodeId: string; owner: string; recipient: string;
  subject: string; preview: string; content: string;
  severity: "info" | "warn" | "crit";
  templateKey: "report" | "alert";
  hostname: string; version: string;
}): Promise<MaintainerSendResult> {
  const { resendKey, from, db } = service();
  const { data: template } = await db.from("notification_templates")
    .select("html_template").eq("template_key", args.templateKey).maybeSingle();
  const html = renderManagedHynEmail({
    template: template?.html_template ?? "{{content}}",
    values: {
      subject: args.subject, hostname: args.hostname,
      version: args.version, severity: args.severity, content: args.content,
    },
    preview: args.preview,
  });
  const delivery = await sendManagedEmail({
    // manual: true is the whole point -- every non-auth email is off by default
    // (lib/email-automation.ts) and this is a person pressing a button.
    delivery: { kind: args.kind, ownerId: args.owner, nodeId: args.nodeId, manual: true },
    apiKey: resendKey, from, to: args.recipient,
    subject: args.subject, html,
    idempotencyKey: `maintainer:${args.kind}:${args.nodeId}:${Date.now()}`,
  });
  await db.from("notification_log").insert({
    node_id: args.nodeId, owner: args.owner, kind: "resend-cloud", target: args.recipient,
    severity: args.severity, subject: args.subject,
    status: delivery.ok ? "sent" : "failed",
    error: delivery.ok ? null : delivery.error,
    category: args.templateKey === "alert" ? "alert" : "report",
  });
  if (!delivery.ok) return { ok: false, error: delivery.error };
  return { ok: true, message: `Sent to ${args.recipient}.` };
}

export async function sendMaintainerNodeReport(nodeId: string): Promise<MaintainerSendResult> {
  if (!UUID.test(nodeId)) return { ok: false, error: "A valid server is required." };
  try {
    const { node, metric, speedtest, alerts, recipient } = await readNode(nodeId);
    const machine: AdminReportMachine = {
      id: node.id, name: node.name, hostname: node.hostname, os: node.os,
      agentVersion: node.agent_version, lastHeartbeatAt: node.last_heartbeat_at,
      lastSeenAt: node.last_seen_at,
      alerts: alerts.filter((alert) => !alert.resolved).map(({ severity, message }) => ({ severity, message })),
      metric, speedtest,
    };
    const report = buildAdminClientReport({
      clientLabel: node.name,
      generatedAt: new Date().toISOString(),
      machines: [machine],
    });
    return await deliver({
      kind: "admin_report", nodeId: node.id, owner: node.owner, recipient,
      subject: `HYN report · ${node.name}`,
      preview: report.preview, content: report.content,
      severity: "info", templateKey: "report",
      hostname: node.hostname ?? node.name, version: node.agent_version ?? "unknown",
    });
  } catch (reason) {
    return { ok: false, error: reason instanceof Error ? reason.message : "The report could not be sent." };
  }
}

export async function sendMaintainerNodeNotification(nodeId: string): Promise<MaintainerSendResult> {
  if (!UUID.test(nodeId)) return { ok: false, error: "A valid server is required." };
  try {
    const { node, metric, speedtest, alerts, recipient } = await readNode(nodeId);
    const [server] = toFleetServers({
      nodes: [node], metrics: metric ? [metric] : [], speedtests: speedtest ? [speedtest] : [], alerts,
    });
    const concerns = concernsFor(server);
    const open = alerts.filter((alert) => !alert.resolved);
    const severity: "info" | "warn" | "crit" = concerns.some((c) => c.severity === "crit")
      ? "crit" : concerns.length ? "warn" : "info";
    // State the current condition plainly. When nothing is wrong, say that rather
    // than padding the message -- a notification that always looks urgent trains
    // the reader to ignore the ones that are.
    const status = concerns.length
      ? `<p style="margin:0 0 16px;color:${emailPalette.text}">Current condition: ${concerns
          .map((concern) => `<strong style="color:${concern.severity === "crit" ? emailPalette.critical : emailPalette.warn}">${escapeHtml(concern.label)}</strong>`)
          .join(" · ")}</p>`
      : `<p style="margin:0 0 16px;color:${emailPalette.text}">No open alerts and no threshold exceeded at the time this was sent.</p>`;
    const reading = metric
      ? `<p style="margin:0;color:${emailPalette.muted}">cpu ${metric.cpu_pct ?? "—"}% · memory ${metric.mem_pct ?? "—"}% · disk ${metric.disk_pct ?? "—"}% · ${metric.cpu_temp_c ?? "—"}°C · reading taken ${escapeHtml(metric.ts)}</p>`
      : `<p style="margin:0;color:${emailPalette.muted}">No cloud reading has arrived for this server yet.</p>`;
    const content = `<section><h2 style="margin:0 0 8px;color:${emailPalette.heading}">${escapeHtml(node.name)} · ${escapeHtml(server.freshness.label)}</h2>`
      + `<p style="margin:0 0 16px;color:${emailPalette.muted}">${escapeHtml(node.hostname ?? "unknown host")} · sent manually by a maintainer</p>`
      + status + reading
      + (open.length ? buildIncidentContent(open.map(({ severity: s, message, resolved, ts }) => ({ severity: s, message, resolved, ts }))) : "")
      + `</section>`;
    return await deliver({
      kind: "other", nodeId: node.id, owner: node.owner, recipient,
      subject: `[HYN ${severity.toUpperCase()}] ${node.name} · ${server.freshness.label}`,
      preview: concerns.length ? concerns.map((c) => c.label).join(", ") : "No open alerts.",
      content, severity, templateKey: "alert",
      hostname: node.hostname ?? node.name, version: node.agent_version ?? "unknown",
    });
  } catch (reason) {
    return { ok: false, error: reason instanceof Error ? reason.message : "The notification could not be sent." };
  }
}
