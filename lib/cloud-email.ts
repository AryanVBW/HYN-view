export type TemplateValues = {
  subject: string;
  hostname: string;
  severity: string;
  version: string;
  content: string;
};

export function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function applyEmailTemplate(template: string, values: TemplateValues): string {
  const wrapper = template.includes("{{content}}") ? template : "{{content}}";
  return wrapper
    .replaceAll("{{hostname}}", escapeHtml(values.hostname))
    .replaceAll("{{version}}", escapeHtml(values.version))
    .replaceAll("{{severity}}", escapeHtml(values.severity))
    .replaceAll("{{subject}}", escapeHtml(values.subject))
    .replaceAll("{{content}}", values.content);
}

export function localDateAndTime(now: Date, timezone: string) {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(now);
    const get = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)?.value ?? "";
    return {
      date: `${get("year")}-${get("month")}-${get("day")}`,
      time: `${get("hour")}:${get("minute")}`,
    };
  } catch {
    return null;
  }
}

export function scheduleIsDue(
  now: Date,
  timezone: string,
  scheduledAt: string,
  lastSentLocalDate: string | null
): boolean {
  const local = localDateAndTime(now, timezone);
  if (!local || !/^([01]\d|2[0-3]):[0-5]\d$/.test(scheduledAt)) return false;
  return local.date !== lastSentLocalDate && local.time >= scheduledAt;
}

function metric(label: string, value: string) {
  return `<div style="display:flex;justify-content:space-between;gap:20px;border-bottom:1px solid #e2e8f0;padding:10px 0"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`;
}

function number(value: number | null, suffix = "", digits = 1) {
  return value === null || !Number.isFinite(value)
    ? "Unavailable"
    : `${value.toFixed(digits)}${suffix}`;
}

function record(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

function finite(value: unknown): number | null {
  const parsed = Number(value);
  return value !== null && value !== "" && Number.isFinite(parsed) ? parsed : null;
}

function bitsPerSecond(value: unknown) {
  const parsed = finite(value);
  return parsed === null ? "Unavailable" : `${((parsed * 8) / 1_000_000).toFixed(1)} Mbps`;
}

function byteSize(value: unknown) {
  const parsed = finite(value);
  if (parsed === null) return "Unavailable";
  return `${(parsed / 1_000_000_000).toFixed(1)} GB`;
}

export function buildSignInContent(details: {
  email: string;
  signedInAt: string;
  ip: string | null;
  userAgent: string | null;
}) {
  return `<section style="font-family:Arial,sans-serif;color:#0f172a"><h1 style="margin:0 0 8px">Welcome, you signed in</h1><p style="color:#64748b;margin:0 0 20px">A successful sign-in to your HYN-view account was recorded.</p>${metric("Account", details.email)}${metric("Time", details.signedInAt)}${metric("IP address", details.ip ?? "Unavailable")}${metric("Browser / device", details.userAgent ?? "Unavailable")}<p style="margin-top:20px;color:#64748b">If this was not you, secure your account and contact support immediately.</p></section>`;
}

export function buildDeviceLinkedContent(details: {
  nodeName: string;
  hostname: string | null;
  os: string | null;
  agentVersion: string | null;
  linkedAt: string;
}) {
  return `<section style="font-family:Arial,sans-serif;color:#0f172a"><h1 style="margin:0 0 8px">${escapeHtml(details.nodeName)} is linked</h1><p style="color:#64748b;margin:0 0 20px">The first telemetry report is being collected now. You will receive a second email with network, speed, hardware, temperature, sensors, processes, and Highway details as soon as the machine checks in.</p>${metric("Node", details.nodeName)}${metric("Hostname", details.hostname ?? "Unavailable")}${metric("Operating system", details.os ?? "Unavailable")}${metric("HYN agent", details.agentVersion ?? "Unavailable")}${metric("Linked at", details.linkedAt)}</section>`;
}

export function buildDailyDigestContent(summary: {
  nodeName: string;
  sampleCount: number;
  cpuAverage: number | null;
  cpuPeak: number | null;
  memoryAverage: number | null;
  temperaturePeak: number | null;
  downloadAverageBps: number | null;
  uploadAverageBps: number | null;
  latencyAverageMs: number | null;
  uptimeSeconds: number | null;
}) {
  const mbps = (value: number | null) =>
    value === null
      ? "Unavailable"
      : `${new Intl.NumberFormat("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format((value * 8) / 1_000_000)} Mbps`;
  return `<section style="font-family:Arial,sans-serif;color:#0f172a"><h1 style="margin:0 0 6px">Daily health · ${escapeHtml(summary.nodeName)}</h1><p style="color:#64748b;margin:0 0 20px">${summary.sampleCount} readings from the last 24 hours</p>${metric("CPU average", number(summary.cpuAverage, "%"))}${metric("CPU peak", number(summary.cpuPeak, "%"))}${metric("Memory average", number(summary.memoryAverage, "%"))}${metric("Temperature", number(summary.temperaturePeak, "°C"))}${metric("Download average", mbps(summary.downloadAverageBps))}${metric("Upload average", mbps(summary.uploadAverageBps))}${metric("Latency average", number(summary.latencyAverageMs, " ms"))}${metric("Uptime", summary.uptimeSeconds === null ? "Unavailable" : `${Math.floor(summary.uptimeSeconds / 86400)}d ${Math.floor((summary.uptimeSeconds % 86400) / 3600)}h`)}</section>`;
}

export function buildSystemSummaryContent(summary: {
  nodeName: string;
  os: string | null;
  agentVersion: string | null;
  lastSeenAt: string | null;
  payload: Record<string, unknown> | null;
}) {
  const payload = record(summary.payload);
  const cpu = record(payload.cpu);
  const memory = record(payload.memory);
  const network = record(payload.network);
  const speedtest = record(payload.speedtest);
  const sensors = record(payload.sensors);
  const highway = record(payload.highway);
  const sensorRows = Object.entries(sensors)
    .map(([label, value]) => metric(`Sensor · ${label}`, number(finite(value), "°C")))
    .join("");
  const linkMbps = finite(network.link_mbps);
  const speedLatency = finite(speedtest.latency_us);
  const highwayPresent = finite(highway.present) === 1;
  const inventory = summary.payload
    ? `<pre style="white-space:pre-wrap;word-break:break-word;background:#f8fafc;border:1px solid #e2e8f0;padding:14px">${escapeHtml(JSON.stringify(summary.payload, null, 2))}</pre>`
    : `<p style="color:#64748b">No detailed inventory was reported by this server.</p>`;
  return `<section style="font-family:Arial,sans-serif;color:#0f172a"><h1 style="margin:0 0 16px">System information · ${escapeHtml(summary.nodeName)}</h1>${metric("Operating system", summary.os ?? String(payload.os ?? "Unavailable"))}${metric("Kernel", String(payload.kernel ?? "Unavailable"))}${metric("HYN agent", summary.agentVersion ?? "Unavailable")}${metric("Last check-in", summary.lastSeenAt ?? "Never")}${metric("CPU model", String(cpu.model ?? "Unavailable"))}${metric("CPU cores", finite(cpu.cores)?.toFixed(0) ?? "Unavailable")}${metric("CPU usage", number(finite(cpu.pct), "%"))}${metric("CPU temperature", number(finite(cpu.temp_c), "°C"))}${metric("Memory", `${byteSize(memory.total)} · ${number(finite(memory.pct), "%")}`)}${metric("Network interface", String(network.iface ?? "Unavailable"))}${metric("Public IP", String(network.public_ip ?? "Unavailable"))}${metric("Local IP", String(network.local_ip ?? "Unavailable"))}${metric("Wi-Fi name", String(network.ssid ?? "Unavailable"))}${metric("Connection", String(network.connection ?? "Unavailable"))}${metric("Link speed", linkMbps === null ? "Unavailable" : `${new Intl.NumberFormat("en-US").format(linkMbps)} Mbps`)}${metric("Current traffic", `${bitsPerSecond(network.rx_bps)} down · ${bitsPerSecond(network.tx_bps)} up`)}${metric("Speed test", `${bitsPerSecond(speedtest.down_bps)} down · ${bitsPerSecond(speedtest.up_bps)} up`)}${metric("Speed-test latency", speedLatency === null ? "Unavailable" : `${(speedLatency / 1000).toFixed(1)} ms`)}${sensorRows}${metric("Highway health", highwayPresent ? String(highway.health ?? "Unknown") : "Not detected")}${metric("Highway version", highwayPresent ? String(highway.version ?? "Unavailable") : "Unavailable")}${metric("Highway services", highwayPresent ? `${finite(highway.units_active)?.toFixed(0) ?? "0"} active · ${finite(highway.units_failed)?.toFixed(0) ?? "0"} failed` : "Unavailable")}<h2 style="margin:24px 0 8px;font-size:16px">Complete reported inventory</h2>${inventory}</section>`;
}

export async function sendResendEmail(args: {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  html: string;
  fetchImpl?: typeof fetch;
}): Promise<{ ok: true; providerId: string | null } | { ok: false; error: string }> {
  if (!args.apiKey || !args.from || !args.to) {
    return { ok: false, error: "email delivery is not configured" };
  }
  try {
    const response = await (args.fetchImpl ?? fetch)("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${args.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: args.from,
        to: [args.to],
        subject: args.subject,
        html: args.html,
      }),
    });
    const provider = await response.json().catch(() => ({})) as { id?: string; message?: string };
    if (!response.ok) {
      return { ok: false, error: provider.message ?? `Resend HTTP ${response.status}` };
    }
    return { ok: true, providerId: provider.id ?? null };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : "email request failed" };
  }
}

export function buildIncidentContent(events: Array<{
  severity: string;
  message: string;
  resolved: boolean;
  ts: string;
}>) {
  const rows = events
    .map(
      (event) =>
        `<li style="margin:0 0 12px"><strong>${escapeHtml(event.resolved ? "Resolved" : event.severity.toUpperCase())}</strong> · ${escapeHtml(event.message)}<br><span style="color:#64748b">${escapeHtml(event.ts)}</span></li>`
    )
    .join("");
  return `<section style="font-family:Arial,sans-serif;color:#0f172a"><h1>Incident update</h1><ul style="padding-left:20px">${rows}</ul></section>`;
}

export type IncidentEvent = {
  id: number;
  rule: string | null;
  severity: string;
  message: string;
  resolved: boolean;
  ts: string;
};

export function novelIncidentEvents(
  incoming: IncidentEvent[],
  previous: IncidentEvent[]
): IncidentEvent[] {
  const key = (event: IncidentEvent) => event.rule ?? event.message;
  const latestPrevious = new Map<string, IncidentEvent>();
  for (const event of [...previous].sort((a, b) => b.id - a.id)) {
    if (!latestPrevious.has(key(event))) latestPrevious.set(key(event), event);
  }
  const latestIncoming = new Map<string, IncidentEvent>();
  for (const event of incoming) latestIncoming.set(key(event), event);
  return [...latestIncoming.values()].filter((event) => {
    const prior = latestPrevious.get(key(event));
    return !prior || prior.resolved !== event.resolved || prior.severity !== event.severity || prior.message !== event.message;
  });
}
