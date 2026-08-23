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
