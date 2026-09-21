import assert from "node:assert/strict";
import test from "node:test";
import {
  applyEmailTemplate,
  buildDailyDigestContent,
  buildDeviceLinkedContent,
  buildCommandResultContent,
  buildSignInContent,
  buildSystemSummaryContent,
  novelIncidentEvents,
  renderHynEmailShell,
  scheduleIsDue,
  sendResendEmail,
} from "./cloud-email.ts";

test("every managed lifecycle message uses the shared HYN email shell", () => {
  const contents = [
    buildSignInContent({
      email: "owner@example.com",
      signedInAt: "2026-08-24T12:00:00Z",
      ip: null,
      userAgent: null,
    }),
    buildDeviceLinkedContent({
      nodeName: "relay-01",
      hostname: null,
      os: null,
      agentVersion: null,
      linkedAt: "2026-08-24T12:01:00Z",
    }),
    buildSystemSummaryContent({
      nodeName: "relay-01",
      os: null,
      agentVersion: null,
      lastSeenAt: null,
      payload: null,
    }),
  ];
  for (const content of contents) {
    const rendered = renderHynEmailShell({
      subject: "Status <script>alert(1)</script>",
      preview: "Current system status",
      hostname: "relay<&>",
      severity: "warn",
      content,
    });
    assert.match(rendered, /data-hyn-email="light"/);
    assert.match(rendered, /HYN-view/);
    assert.match(rendered, /Status &lt;script&gt;alert\(1\)&lt;\/script&gt;/);
    assert.match(rendered, /relay&lt;&amp;&gt;/);
    assert.doesNotMatch(rendered, /<script|<form|<iframe|<img[^>]+src=["']https?:/i);
  }
});

test("command result email explains completion and safe recovery", () => {
  const success = buildCommandResultContent({
    command: "update",
    status: "succeeded",
    message: "Updated <cleanly>",
    targetVersion: "1.7.0",
    resultVersion: "1.7.0",
    updatedAt: "2026-08-24T12:10:00Z",
  });
  assert.match(success, /Update completed/);
  assert.match(success, /Updated &lt;cleanly&gt;/);
  assert.doesNotMatch(success, /Updated <cleanly>/);

  const failed = buildCommandResultContent({
    command: "sync",
    status: "failed",
    message: "Upload failed",
    targetVersion: null,
    resultVersion: null,
    updatedAt: "2026-08-24T12:11:00Z",
  });
  assert.match(failed, /sudo hyn doctor/);
  assert.match(failed, /systemctl status hyn-push.timer/);
});

test("scheduled email timing follows the account timezone", () => {
  const now = new Date("2026-08-22T03:00:00.000Z");
  assert.equal(scheduleIsDue(now, "Asia/Kolkata", "08:30", null), true);
  assert.equal(scheduleIsDue(now, "UTC", "08:30", null), false);
  assert.equal(scheduleIsDue(now, "Asia/Kolkata", "08:30", "2026-08-22"), false);
});

test("sign-in and device-link emails explain exactly what happened", () => {
  const signIn = buildSignInContent({
    email: "owner@example.com",
    signedInAt: "2026-08-23T12:00:00.000Z",
    ip: "203.0.113.8",
    userAgent: "Firefox <desktop>",
  });
  assert.match(signIn, /Welcome, you signed in/);
  assert.match(signIn, /203\.0\.113\.8/);
  assert.doesNotMatch(signIn, /<desktop>/);

  const linked = buildDeviceLinkedContent({
    nodeName: "relay-01",
    hostname: "ubuntu-host",
    os: "Ubuntu 24.04",
    agentVersion: "1.6.0",
    linkedAt: "2026-08-23T12:01:00.000Z",
  });
  assert.match(linked, /relay-01 is linked/);
  assert.match(linked, /Ubuntu 24\.04/);
  assert.match(linked, /first telemetry report is being collected now/i);
});

test("incident email ignores repeated copies of the same firing state", () => {
  const previous = [{ id: 10, rule: "disk_root", severity: "warn", message: "Disk / at 86%", resolved: false, ts: "earlier" }];
  const incoming = [
    { id: 11, rule: "disk_root", severity: "warn", message: "Disk / at 86%", resolved: false, ts: "now" },
    { id: 12, rule: "cpu_temp", severity: "crit", message: "CPU at 91C", resolved: false, ts: "now" },
    { id: 13, rule: "cpu_temp", severity: "crit", message: "CPU at 91C", resolved: false, ts: "later" },
  ];
  assert.deepEqual(novelIncidentEvents(incoming, previous).map((event) => event.id), [13]);
});

test("invalid timezones do not make a scheduled email due", () => {
  assert.equal(
    scheduleIsDue(new Date("2026-08-22T03:00:00.000Z"), "Mars/Olympus", "08:30", null),
    false
  );
});

test("admin email wrappers escape metadata while preserving generated content", () => {
  const rendered = applyEmailTemplate(
    "<h1>{{subject}}</h1><div>{{hostname}}</div>{{content}}",
    {
      subject: "Disk <full>",
      hostname: "edge<&>",
      severity: "warn",
      version: "1.6.0",
      content: "<strong>trusted report</strong>",
    }
  );
  assert.equal(
    rendered,
    "<h1>Disk &lt;full&gt;</h1><div>edge&lt;&amp;&gt;</div><strong>trusted report</strong>"
  );
});

test("daily and system emails render absent sensors as unavailable", () => {
  const daily = buildDailyDigestContent({
    nodeName: "edge-01",
    sampleCount: 2,
    cpuAverage: 31.25,
    cpuPeak: 44,
    memoryAverage: 61,
    temperaturePeak: null,
    downloadAverageBps: 125_000_000,
    uploadAverageBps: 25_000_000,
    latencyAverageMs: 8.2,
    uptimeSeconds: 86400,
  });
  assert.match(daily, /Temperature[\s\S]*Unavailable/);
  assert.match(daily, /1,000\.0 Mbps/);

  const system = buildSystemSummaryContent({
    nodeName: "edge-01",
    os: "Ubuntu 24.04",
    agentVersion: "1.6.0",
    lastSeenAt: "2026-08-22T03:00:00.000Z",
    payload: null,
  });
  assert.match(system, /No detailed inventory was reported/);
});

test("first system email summarizes network, speed, hardware, temperature and Highway", () => {
  const system = buildSystemSummaryContent({
    nodeName: "relay-01",
    os: "Ubuntu 24.04",
    agentVersion: "1.6.0",
    lastSeenAt: "2026-08-23T12:02:00.000Z",
    payload: {
      kernel: "6.8.0",
      cpu: { model: "AMD EPYC", cores: 8, temp_c: 54, pct: 12.5 },
      memory: { total: 16_000_000_000, pct: 40 },
      network: {
        iface: "eth0", local_ip: "10.0.0.5/24", public_ip: "203.0.113.7",
        ssid: "Office WiFi", link_mbps: 1000, rx_bps: 12_500_000, tx_bps: 2_500_000,
      },
      speedtest: { down_bps: 100_000_000, up_bps: 20_000_000, latency_us: 8000 },
      sensors: { "nvme Composite": 41 },
      highway: { present: 1, health: "healthy", version: "2.4.1", units_active: 2, units_failed: 0 },
    },
  });

  for (const expected of [
    "203.0.113.7", "10.0.0.5/24", "Office WiFi", "1,000 Mbps",
    "800.0 Mbps", "AMD EPYC", "54.0°C", "nvme Composite", "healthy", "2.4.1",
  ]) assert.match(system, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("managed email delivery sends the exact lifecycle message through Resend", async () => {
  const requests: { url: string; init?: RequestInit }[] = [];
  const result = await sendResendEmail({
    apiKey: "re_test",
    from: "HYN-view <reports@example.com>",
    to: "owner@example.com",
    subject: "Welcome, you signed in",
    html: "<h1>Welcome</h1>",
    idempotencyKey: "email:test:123",
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      return new Response(JSON.stringify({ id: "email_123" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  });

  assert.deepEqual(result, { ok: true, providerId: "email_123" });
  const request = requests[0];
  assert.ok(request, "The delivery must make an HTTP request");
  assert.equal(request?.url, "https://api.resend.com/emails");
  assert.deepEqual(JSON.parse(String(request?.init?.body)), {
    from: "HYN-view <reports@example.com>",
    to: ["owner@example.com"],
    subject: "Welcome, you signed in",
    html: "<h1>Welcome</h1>",
  });
  assert.equal((request?.init?.headers as Record<string, string>)["Idempotency-Key"], "email:test:123");
});

test("managed email delivery returns provider failures for retry and logging", async () => {
  const result = await sendResendEmail({
    apiKey: "re_test",
    from: "reports@example.com",
    to: "owner@example.com",
    subject: "System information",
    html: "<p>Details</p>",
    fetchImpl: async () => new Response(JSON.stringify({ message: "domain not verified" }), { status: 403 }),
  });
  assert.deepEqual(result, { ok: false, error: "domain not verified" });
});
