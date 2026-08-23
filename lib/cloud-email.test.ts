import assert from "node:assert/strict";
import test from "node:test";
import {
  applyEmailTemplate,
  buildDailyDigestContent,
  buildSystemSummaryContent,
  novelIncidentEvents,
  scheduleIsDue,
} from "./cloud-email.ts";

test("scheduled email timing follows the account timezone", () => {
  const now = new Date("2026-08-22T03:00:00.000Z");
  assert.equal(scheduleIsDue(now, "Asia/Kolkata", "08:30", null), true);
  assert.equal(scheduleIsDue(now, "UTC", "08:30", null), false);
  assert.equal(scheduleIsDue(now, "Asia/Kolkata", "08:30", "2026-08-22"), false);
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
  assert.match(daily, /Temperature<\/span><strong>Unavailable<\/strong>/);
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
