import assert from "node:assert/strict";
import { test } from "node:test";
import { utcDays } from "../src/bandwidth.ts";

test("utcDays returns the requested calendar window ending today", () => {
  const days = utcDays(3, new Date("2026-09-17T10:00:00.000Z"));
  assert.deepEqual(days, ["2026-09-17", "2026-09-16", "2026-09-15"]);
});
