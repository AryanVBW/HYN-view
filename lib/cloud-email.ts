export type TemplateValues = {
  subject: string;
  hostname: string;
  severity: string;
  version: string;
  content: string;
};

// One light, professional palette shared by every generated email (this file,
// admin-report.ts, user-digest.ts, web-notification.ts) so a redesign is one
// change, not four coordinated ones. White surface, dark readable text, the
// severity rail is the only saturated color -- the look every other HYN-view
// email inherits from renderHynEmailShell's <body> and metric()/row().
export const emailPalette = {
  bg: "#f4f6f8",
  surface: "#ffffff",
  border: "#e2e6ea",
  text: "#1a2027",
  muted: "#6b7684",
  heading: "#0f1420",
  brand: "#0f6dd6",
  critical: "#c22b2b",
  warn: "#a8660a",
  info: "#0f6dd6",
  codeBg: "#f7f8fa",
} as const;

export function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function applyEmailTemplate(template: string, values: TemplateValues): string {
  const safe = template
    .replace(/<(script|form|iframe|object|embed|link|meta)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, "")
    .replace(/<(script|form|iframe|object|embed|link|meta)\b[^>]*\/?>/gi, "")
    .replace(/\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*')/gi, "")
    .replace(/\s+(src|href)\s*=\s*("|')\s*(?:https?:|data:)[^"']*\2/gi, "")
    .replace(/url\s*\([^)]*\)/gi, "");
  const wrapper = safe.includes("{{content}}") ? safe : "{{content}}";
  return wrapper
    .replaceAll("{{hostname}}", escapeHtml(values.hostname))
    .replaceAll("{{version}}", escapeHtml(values.version))
    .replaceAll("{{severity}}", escapeHtml(values.severity))
    .replaceAll("{{subject}}", escapeHtml(values.subject))
    .replaceAll("{{content}}", values.content);
}

export function renderHynEmailShell(args: {
  subject: string;
  preview: string;
  hostname?: string | null;
  severity?: string;
  content: string;
}) {
  const severity = args.severity === "crit" ? "critical" : args.severity ?? "info";
  const rail = severity === "critical" ? emailPalette.critical : severity === "warn" ? emailPalette.warn : emailPalette.info;
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:${emailPalette.bg};color:${emailPalette.text}"><div style="display:none;max-height:0;overflow:hidden;opacity:0">${escapeHtml(args.preview)}</div><table data-hyn-email="light" role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;background:${emailPalette.bg}"><tr><td align="center" style="padding:28px 12px"><table role="presentation" width="640" cellspacing="0" cellpadding="0" style="width:100%;max-width:640px;background:${emailPalette.surface};border:1px solid ${emailPalette.border};border-radius:8px"><tr><td style="padding:24px 28px 18px;border-top:4px solid ${rail};border-radius:8px 8px 0 0"><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td style="font:700 12px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.08em;color:${emailPalette.brand}">HYN-VIEW</td><td align="right" style="font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.04em;color:${rail};text-transform:uppercase">${escapeHtml(severity)}</td></tr></table><h1 style="margin:18px 0 6px;font:600 26px Georgia,'Times New Roman',serif;line-height:1.3;color:${emailPalette.heading}">${escapeHtml(args.subject)}</h1><p style="margin:0;font:13px -apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.muted}">${escapeHtml(args.hostname ?? "HYN-view account")}</p></td></tr><tr><td style="padding:6px 28px 30px;font:14px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:${emailPalette.text}">${args.content}</td></tr><tr><td style="border-top:1px solid ${emailPalette.border};padding:16px 28px;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:${emailPalette.muted};border-radius:0 0 8px 8px">Sent by the HYN-view web portal. The CLI never stores your email address or provider credentials.</td></tr></table></td></tr></table></body></html>`;
}

export function renderManagedHynEmail(args: {
  template?: string | null;
  values: TemplateValues;
  preview: string;
}) {
  const content = applyEmailTemplate(args.template ?? "{{content}}", args.values);
  return renderHynEmailShell({
    subject: args.values.subject,
    preview: args.preview,
    hostname: args.values.hostname,
    severity: args.values.severity,
    content,
  });
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
  return `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-bottom:1px solid ${emailPalette.border}"><tr><td style="padding:10px 0;font:13px -apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.muted}">${escapeHtml(label)}</td><td align="right" style="padding:10px 0;font:600 13px -apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.heading}">${escapeHtml(value)}</td></tr></table>`;
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
  return `<section><h2 style="margin:0 0 8px;color:${emailPalette.heading}">Welcome, you signed in</h2><p style="color:${emailPalette.muted};margin:0 0 20px">A successful sign-in to your HYN-view account was recorded.</p>${metric("Account", details.email)}${metric("Time", details.signedInAt)}${metric("IP address", details.ip ?? "Unavailable")}${metric("Browser / device", details.userAgent ?? "Unavailable")}<p style="margin-top:20px;color:${emailPalette.muted}">If this was not you, secure your account and contact support immediately.</p></section>`;
}

export function buildDeviceLinkedContent(details: {
  nodeName: string;
  hostname: string | null;
  os: string | null;
  agentVersion: string | null;
  linkedAt: string;
}) {
  return `<section><h2 style="margin:0 0 8px;color:${emailPalette.heading}">${escapeHtml(details.nodeName)} is linked</h2><p style="color:${emailPalette.muted};margin:0 0 20px">The first telemetry report is being collected now. You will receive a second email with network, speed, hardware, temperature, sensors, processes, and Highway details as soon as the machine checks in.</p>${metric("Node", details.nodeName)}${metric("Hostname", details.hostname ?? "Unavailable")}${metric("Operating system", details.os ?? "Unavailable")}${metric("HYN agent", details.agentVersion ?? "Unavailable")}${metric("Linked at", details.linkedAt)}</section>`;
}

export function buildCommandResultContent(details: {
  command: "update" | "sync";
  status: "succeeded" | "failed" | "expired";
  message: string;
  targetVersion: string | null;
  resultVersion: string | null;
  updatedAt: string;
}) {
  const action = details.command === "update" ? "Update" : "Synchronization";
  const completed = details.status === "succeeded";
  const recovery = completed
    ? ""
    : `<p style="margin:20px 0 8px;color:${emailPalette.critical}">Run these checks on the server:</p><pre style="white-space:pre-wrap;border:1px solid #e6c4c4;background:#fdf4f4;padding:14px;color:${emailPalette.heading};border-radius:6px">sudo hyn doctor\nsystemctl status hyn-push.timer\nsudo systemctl restart hyn-push.timer</pre>`;
  return `<section><h2 style="margin:0 0 16px;color:${emailPalette.heading}">${action} ${completed ? "completed" : "failed"}</h2>${metric("Status", details.status)}${metric("Portal message", details.message)}${metric("Target version", details.targetVersion ?? "Unavailable")}${metric("Reported version", details.resultVersion ?? "Unavailable")}${metric("Last progress", details.updatedAt)}${recovery}</section>`;
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
  return `<section><h2 style="margin:0 0 6px;color:${emailPalette.heading}">Daily health · ${escapeHtml(summary.nodeName)}</h2><p style="color:${emailPalette.muted};margin:0 0 20px">${summary.sampleCount} readings from the last 24 hours</p>${metric("CPU average", number(summary.cpuAverage, "%"))}${metric("CPU peak", number(summary.cpuPeak, "%"))}${metric("Memory average", number(summary.memoryAverage, "%"))}${metric("Temperature", number(summary.temperaturePeak, "°C"))}${metric("Download average", mbps(summary.downloadAverageBps))}${metric("Upload average", mbps(summary.uploadAverageBps))}${metric("Latency average", number(summary.latencyAverageMs, " ms"))}${metric("Uptime", summary.uptimeSeconds === null ? "Unavailable" : `${Math.floor(summary.uptimeSeconds / 86400)}d ${Math.floor((summary.uptimeSeconds % 86400) / 3600)}h`)}</section>`;
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
    ? `<pre style="white-space:pre-wrap;word-break:break-word;background:${emailPalette.codeBg};color:${emailPalette.text};border:1px solid ${emailPalette.border};padding:14px;border-radius:6px">${escapeHtml(JSON.stringify(summary.payload, null, 2))}</pre>`
    : `<p style="color:${emailPalette.muted}">No detailed inventory was reported by this server.</p>`;
  return `<section><h2 style="margin:0 0 16px;color:${emailPalette.heading}">System information · ${escapeHtml(summary.nodeName)}</h2>${metric("Operating system", summary.os ?? String(payload.os ?? "Unavailable"))}${metric("Kernel", String(payload.kernel ?? "Unavailable"))}${metric("HYN agent", summary.agentVersion ?? "Unavailable")}${metric("Last check-in", summary.lastSeenAt ?? "Never")}${metric("CPU model", String(cpu.model ?? "Unavailable"))}${metric("CPU cores", finite(cpu.cores)?.toFixed(0) ?? "Unavailable")}${metric("CPU usage", number(finite(cpu.pct), "%"))}${metric("CPU temperature", number(finite(cpu.temp_c), "°C"))}${metric("Memory", `${byteSize(memory.total)} · ${number(finite(memory.pct), "%")}`)}${metric("Network interface", String(network.iface ?? "Unavailable"))}${metric("Public IP", String(network.public_ip ?? "Unavailable"))}${metric("Local IP", String(network.local_ip ?? "Unavailable"))}${metric("Wi-Fi name", String(network.ssid ?? "Unavailable"))}${metric("Connection", String(network.connection ?? "Unavailable"))}${metric("Link speed", linkMbps === null ? "Unavailable" : `${new Intl.NumberFormat("en-US").format(linkMbps)} Mbps`)}${metric("Current traffic", `${bitsPerSecond(network.rx_bps)} down · ${bitsPerSecond(network.tx_bps)} up`)}${metric("Speed test", `${bitsPerSecond(speedtest.down_bps)} down · ${bitsPerSecond(speedtest.up_bps)} up`)}${metric("Speed-test latency", speedLatency === null ? "Unavailable" : `${(speedLatency / 1000).toFixed(1)} ms`)}${sensorRows}${metric("Highway health", highwayPresent ? String(highway.health ?? "Unknown") : "Not detected")}${metric("Highway version", highwayPresent ? String(highway.version ?? "Unavailable") : "Unavailable")}${metric("Highway services", highwayPresent ? `${finite(highway.units_active)?.toFixed(0) ?? "0"} active · ${finite(highway.units_failed)?.toFixed(0) ?? "0"} failed` : "Unavailable")}<h3 style="margin:24px 0 8px;color:${emailPalette.heading};font-size:16px">Complete reported inventory</h3>${inventory}</section>`;
}

export async function sendResendEmail(args: {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  html: string;
  idempotencyKey?: string;
  fetchImpl?: typeof fetch;
}): Promise<{ ok: true; providerId: string | null } | { ok: false; error: string }> {
  if (!args.apiKey || !args.from || !args.to) {
    return { ok: false, error: "email delivery is not configured" };
  }
  try {
    const response = await (args.fetchImpl ?? fetch)("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
        ...(args.idempotencyKey ? { "Idempotency-Key": args.idempotencyKey } : {}),
      },
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

// Why email is not sending, answered without sending anything.
//
// Every delivery failure in this portal comes from one of four causes, and until
// now none of them was visible: the provider's error string was either discarded
// (the sign-in email) or buried in a notification_log row nobody thinks to query.
// This asks Resend directly and names the cause, so "email is not working"
// becomes a specific, fixable sentence.
//
// It deliberately does not send a message. A diagnostic that mails somebody to
// prove mail works cannot run when mail is broken, which is exactly when it is
// needed.
export type EmailDiagnosis = {
  ok: boolean;
  cause:
    | "ok"
    | "missing-key"
    | "missing-from"
    | "invalid-key"
    | "sender-domain-unverified"
    | "sender-domain-unknown"
    | "provider-unreachable";
  detail: string;
  fromAddress: string | null;
  senderDomain: string | null;
  domains: { name: string; status: string }[];
};

// "HYN-view <reports@hyn-view.info>" and "reports@hyn-view.info" both yield the
// domain, because either form is a legal EMAIL_FROM and both are used in practice.
export function senderDomainOf(from: string | null | undefined): string | null {
  if (!from) return null;
  const angle = from.match(/<([^>]+)>/);
  const address = (angle ? angle[1] : from).trim();
  const at = address.lastIndexOf("@");
  if (at < 0 || at === address.length - 1) return null;
  return address.slice(at + 1).toLowerCase();
}

export async function diagnoseEmailDelivery(args: {
  apiKey: string | undefined;
  from: string | undefined;
  fetchImpl?: typeof fetch;
}): Promise<EmailDiagnosis> {
  const from = args.from?.trim() ?? "";
  const senderDomain = senderDomainOf(from);
  const base: EmailDiagnosis = {
    ok: false, cause: "ok", detail: "", fromAddress: from || null,
    senderDomain, domains: [],
  };
  if (!args.apiKey) {
    return { ...base, cause: "missing-key", detail: "RESEND_API_KEY is not set on the deployment." };
  }
  if (!from || !senderDomain) {
    return {
      ...base, cause: "missing-from",
      detail: from
        ? `EMAIL_FROM ("${from}") has no usable domain. Use "Name <you@your-domain>" or "you@your-domain".`
        : "EMAIL_FROM is not set on the deployment.",
    };
  }
  let payload: unknown;
  let status = 0;
  try {
    const response = await (args.fetchImpl ?? fetch)("https://api.resend.com/domains", {
      headers: { Authorization: `Bearer ${args.apiKey}` },
    });
    status = response.status;
    payload = await response.json().catch(() => ({}));
  } catch (error) {
    return {
      ...base, cause: "provider-unreachable",
      detail: error instanceof Error ? error.message : "could not reach api.resend.com",
    };
  }
  const body = (payload ?? {}) as { data?: unknown; message?: string };
  if (status === 401 || status === 403 || /api key is invalid/i.test(body.message ?? "")) {
    return {
      ...base, cause: "invalid-key",
      detail: body.message ?? `Resend rejected the key with HTTP ${status}.`,
    };
  }
  if (status >= 400) {
    return {
      ...base, cause: "provider-unreachable",
      detail: body.message ?? `Resend returned HTTP ${status}.`,
    };
  }
  const domains = (Array.isArray(body.data) ? body.data : [])
    .map((entry) => entry as { name?: unknown; status?: unknown })
    .flatMap((entry) =>
      typeof entry.name === "string"
        ? [{ name: entry.name.toLowerCase(), status: typeof entry.status === "string" ? entry.status : "unknown" }]
        : []
    );
  const match = domains.find((d) => d.name === senderDomain);
  if (!match) {
    return {
      ...base, domains, cause: "sender-domain-unknown",
      detail: `EMAIL_FROM sends from "${senderDomain}", which is not a domain in this Resend account. `
        + (domains.length
          ? `Verified domains are: ${domains.map((d) => `${d.name} (${d.status})`).join(", ")}.`
          : "This Resend account has no domains configured at all."),
    };
  }
  if (match.status !== "verified") {
    return {
      ...base, domains, cause: "sender-domain-unverified",
      detail: `The sending domain "${senderDomain}" is "${match.status}" in Resend, not "verified". `
        + "Resend refuses every send from an unverified domain.",
    };
  }
  return {
    ...base, ok: true, cause: "ok", domains,
    detail: `Resend accepted the key and "${senderDomain}" is verified.`,
  };
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
        `<li style="margin:0 0 12px"><strong style="color:${emailPalette.heading}">${escapeHtml(event.resolved ? "Resolved" : event.severity.toUpperCase())}</strong> · ${escapeHtml(event.message)}<br><span style="color:${emailPalette.muted}">${escapeHtml(event.ts)}</span></li>`
    )
    .join("");
  return `<section style="font-family:-apple-system,Segoe UI,Arial,sans-serif;color:${emailPalette.text}"><h1 style="color:${emailPalette.heading};font-size:20px;margin:0 0 12px">Incident update</h1><ul style="padding-left:20px;margin:0">${rows}</ul></section>`;
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
