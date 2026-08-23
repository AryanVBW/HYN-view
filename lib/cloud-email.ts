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
  const inventory = summary.payload
    ? `<pre style="white-space:pre-wrap;word-break:break-word;background:#f8fafc;border:1px solid #e2e8f0;padding:14px">${escapeHtml(JSON.stringify(summary.payload, null, 2))}</pre>`
    : `<p style="color:#64748b">No detailed inventory was reported by this server.</p>`;
  return `<section style="font-family:Arial,sans-serif;color:#0f172a"><h1 style="margin:0 0 16px">System information · ${escapeHtml(summary.nodeName)}</h1>${metric("Operating system", summary.os ?? "Unavailable")}${metric("HYN agent", summary.agentVersion ?? "Unavailable")}${metric("Last check-in", summary.lastSeenAt ?? "Never")}${inventory}</section>`;
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
