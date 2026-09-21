import { buildSystemSummaryContent, emailPalette, escapeHtml } from "./cloud-email.ts";
import type { Metric, Speedtest } from "./types.ts";

export type AdminReportMachine = {
  id: string;
  name: string;
  hostname: string | null;
  os: string | null;
  agentVersion: string | null;
  lastHeartbeatAt: string | null;
  lastSeenAt: string | null;
  alerts: Array<{ severity: string; message: string }>;
  metric: Pick<
    Metric,
    | "cpu_pct"
    | "cpu_temp_c"
    | "cpu_model"
    | "cpu_cores"
    | "mem_pct"
    | "mem_total"
    | "mem_used"
    | "disk_pct"
    | "net_iface"
    | "net_rx_bps"
    | "net_tx_bps"
    | "net_link_mbps"
    | "sensors"
    | "payload"
  > | null;
  speedtest: Pick<Speedtest, "down_bps" | "up_bps" | "latency_ms"> | null;
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? { ...(value as Record<string, unknown>) }
    : {};
}

function value(value: number | null | undefined, suffix = "") {
  return value === null || value === undefined || !Number.isFinite(Number(value))
    ? "Unavailable"
    : `${Number(value).toFixed(1)}${suffix}`;
}

function row(label: string, content: string) {
  return `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-bottom:1px solid ${emailPalette.border}"><tr><td style="padding:10px 0;font:13px -apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.muted}">${escapeHtml(label)}</td><td align="right" style="padding:10px 0;font:600 13px -apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.heading}">${escapeHtml(content)}</td></tr></table>`;
}

function completePayload(machine: AdminReportMachine): Record<string, unknown> | null {
  const metric = machine.metric;
  if (!metric) return null;
  const payload = record(metric.payload);
  payload.cpu = {
    ...record(payload.cpu),
    model: metric.cpu_model,
    cores: metric.cpu_cores,
    pct: metric.cpu_pct,
    temp_c: metric.cpu_temp_c,
  };
  payload.memory = {
    ...record(payload.memory),
    total: metric.mem_total,
    used: metric.mem_used,
    pct: metric.mem_pct,
  };
  payload.network = {
    ...record(payload.network),
    iface: metric.net_iface,
    rx_bps: metric.net_rx_bps,
    tx_bps: metric.net_tx_bps,
    link_mbps: metric.net_link_mbps,
  };
  payload.speedtest = {
    ...record(payload.speedtest),
    down_bps: machine.speedtest?.down_bps ?? null,
    up_bps: machine.speedtest?.up_bps ?? null,
    latency_us: machine.speedtest?.latency_ms === null || machine.speedtest?.latency_ms === undefined
      ? null
      : Number(machine.speedtest.latency_ms) * 1_000,
  };
  payload.sensors = metric.sensors ?? record(payload.sensors);
  return payload;
}

export function buildAdminClientReport(args: {
  clientLabel: string;
  generatedAt: string;
  machines: AdminReportMachine[];
}) {
  const subject = `Current HYN fleet report · ${args.clientLabel}`;
  const heading = `<section><h2 style="margin:0 0 8px;color:${emailPalette.heading}">Current fleet status</h2><p style="margin:0 0 20px;color:${emailPalette.muted}">${args.machines.length} active machine${args.machines.length === 1 ? "" : "s"} · generated ${escapeHtml(args.generatedAt)}</p></section>`;
  if (args.machines.length === 0) {
    return {
      subject,
      preview: "No active HYN machines were available for this report.",
      content: `${heading}<p style="color:${emailPalette.muted}">No active linked machines were available when this report was generated.</p>`,
    };
  }

  const machines = args.machines.map((machine) => {
    const alerts = machine.alerts.length === 0
      ? `<p style="margin:12px 0;color:${emailPalette.info}">No open alerts.</p>`
      : `<ul style="margin:12px 0;padding-left:20px;color:#ff8b8b">${machine.alerts.map((alert) => `<li><strong>${escapeHtml(alert.severity.toUpperCase())}</strong> · ${escapeHtml(alert.message)}</li>`).join("")}</ul>`;
    return `<section style="margin-top:28px;border-top:1px solid ${emailPalette.border};padding-top:22px"><h2 style="margin:0 0 12px;color:${emailPalette.heading}">${escapeHtml(machine.name)}</h2>${row("Heartbeat", machine.lastHeartbeatAt ?? "Unavailable")}${row("Telemetry", machine.lastSeenAt ?? "Unavailable")}${row("Open alerts", String(machine.alerts.length))}${row("Disk usage", value(machine.metric?.disk_pct, "%"))}${alerts}${buildSystemSummaryContent({
      nodeName: machine.name,
      os: machine.os,
      agentVersion: machine.agentVersion,
      lastSeenAt: machine.lastSeenAt,
      payload: completePayload(machine),
    })}</section>`;
  }).join("");

  return {
    subject,
    preview: `${args.machines.length} active HYN machines with current health, network, speed, and hardware details.`,
    content: heading + machines,
  };
}
