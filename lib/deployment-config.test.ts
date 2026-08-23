import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function fieldOccurrencesPerDay(field: string, total: number): number {
  if (field === "*") return total;
  if (/^\d+$/.test(field)) return 1;
  return total + 1;
}

test("production cron schedules are deployable on the Vercel Hobby plan", () => {
  const config = JSON.parse(
    readFileSync(new URL("../vercel.json", import.meta.url), "utf8")
  ) as { crons?: Array<{ path: string; schedule: string }> };

  for (const cron of config.crons ?? []) {
    const fields = cron.schedule.trim().split(/\s+/);
    assert.equal(fields.length, 5, `${cron.path} must use a five-field cron expression`);
    const runsPerDay =
      fieldOccurrencesPerDay(fields[0], 60) *
      fieldOccurrencesPerDay(fields[1], 24);
    assert.ok(
      runsPerDay <= 1,
      `${cron.path} runs ${runsPerDay} times per day; Vercel Hobby permits one`
    );
  }
});

test("Vercel Workflow endpoints bypass the authentication proxy", () => {
  const proxy = readFileSync(new URL("../proxy.ts", import.meta.url), "utf8");
  const nextConfig = readFileSync(new URL("../next.config.ts", import.meta.url), "utf8");

  assert.match(proxy, /\.well-known\/workflow\//);
  assert.match(nextConfig, /withWorkflow\(nextConfig\)/);
});

test("accepted telemetry evaluates user email schedules with the daily cron as fallback", () => {
  const agentRoute = readFileSync(
    new URL("../app/api/agent/v1/[action]/route.ts", import.meta.url),
    "utf8",
  );
  const cronRoute = readFileSync(
    new URL("../app/api/cron/email/route.ts", import.meta.url),
    "utf8",
  );

  assert.match(agentRoute, /rpc === "hyn_ingest"[\s\S]*dispatchScheduledEmails\(nodeId\)/);
  assert.match(cronRoute, /dispatchScheduledEmails\(\)/);
  assert.match(cronRoute, /maxDuration = 300/);
});
