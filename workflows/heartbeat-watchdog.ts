import { createClient } from "@supabase/supabase-js";
import { FatalError, sleep } from "workflow";
import {
  escapeHtml,
  renderManagedHynEmail,
} from "@/lib/cloud-email";
import { sendManagedEmail as sendResendEmail } from "@/lib/delivery-send";

type HeartbeatCheck = {
  stop: boolean;
  state?: "online" | "offline";
  notify?: boolean;
  nodeId?: string;
  nodeName?: string;
  hostname?: string | null;
  owner?: string;
  heartbeatAt?: string | null;
  ageSeconds?: number | null;
  recipient?: string | null;
  incident_enabled?: boolean;
  template?: string | null;
};

function d1Url() {
  return (process.env.HYN_DATA_API_URL ?? "").replace(/\/$/, "");
}

async function d1Rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const base = d1Url();
  const key = process.env.HYN_DATA_SERVICE_KEY ?? "";
  if (!base || !key) throw new FatalError("D1 service credentials are not configured");
  const res = await fetch(`${base}/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`data request failed: ${name}`);
  return await res.json() as T;
}

function serviceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new FatalError("Supabase service credentials are not configured");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function checkHeartbeat(nodeId: string): Promise<HeartbeatCheck> {
  "use step";
  if (d1Url()) {
    return d1Rpc<HeartbeatCheck>("hyn_heartbeat_watchdog_tick", { p_node: nodeId });
  }
  const supabase = serviceClient();
  const { data: node, error: nodeError } = await supabase
    .from("nodes")
    .select("id,owner,name,hostname,last_heartbeat_at,status,revoked,is_demo")
    .eq("id", nodeId)
    .maybeSingle();
  if (nodeError) throw nodeError;
  if (!node || node.revoked || node.is_demo || node.status !== "active") {
    await supabase.from("node_watchdogs").update({ state: "stopped", updated_at: new Date().toISOString() }).eq("node_id", nodeId);
    return { stop: true };
  }

  const heartbeatMs = node.last_heartbeat_at ? Date.parse(node.last_heartbeat_at) : Number.NaN;
  const ageSeconds = Number.isFinite(heartbeatMs)
    ? Math.max(0, Math.floor((Date.now() - heartbeatMs) / 1_000))
    : null;
  const state = ageSeconds !== null && ageSeconds < 180 ? "online" : "offline";
  const { data: watchdog, error: watchdogError } = await supabase
    .from("node_watchdogs")
    .select("last_alert_state")
    .eq("node_id", nodeId)
    .maybeSingle();
  if (watchdogError) throw watchdogError;
  const prior = watchdog?.last_alert_state ?? "unknown";
  const notify = state !== prior && (state === "offline" || prior === "offline");
  const { error: updateError } = await supabase.from("node_watchdogs").upsert({
    node_id: nodeId,
    state: "running",
    last_alert_state: state,
    updated_at: new Date().toISOString(),
  });
  if (updateError) throw updateError;
  return {
    stop: false,
    state,
    notify,
    nodeId: node.id,
    nodeName: node.name,
    hostname: node.hostname,
    owner: node.owner,
    heartbeatAt: node.last_heartbeat_at,
    ageSeconds,
  };
}

async function sendHeartbeatTransition(check: HeartbeatCheck) {
  "use step";
  if (!check.nodeId || !check.owner || !check.state) return { status: "invalid" };
  let recipient = check.recipient ?? null;
  let templateHtml = check.template ?? null;
  if (!d1Url()) {
    const supabase = serviceClient();
    const { data: preference, error: preferenceError } = await supabase
      .from("email_preferences")
      .select("recipient,incident_enabled")
      .eq("node_id", check.nodeId)
      .maybeSingle();
    if (preferenceError) throw preferenceError;
    if (!preference?.recipient || !preference.incident_enabled) return { status: "disabled" };
    recipient = preference.recipient;
    const { data: template } = await supabase
      .from("notification_templates")
      .select("html_template")
      .eq("template_key", "alert")
      .maybeSingle();
    templateHtml = template?.html_template ?? null;
  } else if (!recipient || check.incident_enabled === false) {
    return { status: "disabled" };
  }

  const offline = check.state === "offline";
  const subject = offline
    ? `[HYN CRIT] ${check.nodeName ?? "Machine"} missed three heartbeats`
    : `[HYN RECOVERED] ${check.nodeName ?? "Machine"} is reporting again`;
  const detail = offline
    ? `No heartbeat has reached the portal for ${check.ageSeconds === null ? "an unknown interval" : `${check.ageSeconds} seconds`}. Charts still show the last received values.`
    : `The machine resumed its one-minute heartbeat at ${check.heartbeatAt ?? "the current check"}.`;
  const content = `<p style="margin:0 0 16px;color:#dcecf2">${escapeHtml(detail)}</p><pre style="white-space:pre-wrap;border:1px solid #17333d;background:#05090c;padding:14px;color:#dcecf2">sudo hyn doctor --fix</pre>`;
  const html = renderManagedHynEmail({
    template: templateHtml ?? "{{content}}",
    values: {
      subject,
      hostname: check.hostname ?? check.nodeName ?? "linked machine",
      version: "",
      severity: offline ? "crit" : "info",
      content,
    },
    preview: detail,
  });
  const delivery = await sendResendEmail({
    delivery: { kind: "incident", ownerId: check.owner, nodeId: check.nodeId },
    apiKey: process.env.RESEND_API_KEY ?? "",
    from: process.env.EMAIL_FROM ?? "HYN-view <reports@hyn-view.info>",
    to: recipient!,
    subject,
    html,
    idempotencyKey: `heartbeat:${check.nodeId}:${check.state}:${check.heartbeatAt ?? "missing"}`,
  });
  if (!delivery.ok && delivery.deferred) return { status: "deferred", reason: delivery.error };
  if (d1Url()) {
    await d1Rpc("hyn_log_notification", {
      p_node_id: check.nodeId,
      p_owner: check.owner,
      p_kind: "resend-cloud",
      p_target: recipient,
      p_severity: offline ? "crit" : "info",
      p_subject: subject,
      p_status: delivery.ok ? "sent" : "failed",
      p_error: delivery.ok ? null : delivery.error,
      p_category: "alert",
    });
  } else {
    const supabase = serviceClient();
    const { error: logError } = await supabase.from("notification_log").insert({
      node_id: check.nodeId,
      owner: check.owner,
      kind: "resend-cloud",
      target: recipient,
      severity: offline ? "crit" : "info",
      subject,
      status: delivery.ok ? "sent" : "failed",
      error: delivery.ok ? null : delivery.error,
      category: "alert",
    });
    if (logError) throw logError;
  }
  if (!delivery.ok) throw new Error(delivery.error);
  return { status: "sent", providerId: delivery.providerId };
}

export async function monitorNodeHeartbeat(nodeId: string) {
  "use workflow";
  while (true) {
    await sleep("1m");
    const check = await checkHeartbeat(nodeId);
    if (check.stop) return { status: "stopped", nodeId };
    if (check.notify) await sendHeartbeatTransition(check);
  }
}
