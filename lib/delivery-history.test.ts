import assert from "node:assert/strict";
import test from "node:test";
import { visibleDeliveries } from "./delivery-history.ts";
import type { NotificationLogRow } from "./types.ts";

// The clear on the delivery-history panel is a view control, and the one thing a
// view control must never do is look like data loss. So: a cleared view hides
// what was there when it was cleared, keeps anything that arrives afterwards,
// says it is cleared (the panel needs that to explain itself rather than showing
// "nothing has been sent yet"), and treats a junk cookie as no clear at all.
const row = (id: number, ts: string) =>
  ({ id, ts, kind: "resend-cloud", status: "sent", category: "alert" } as unknown as NotificationLogRow);

const log = [
  row(3, "2026-09-02T12:00:00+00:00"),
  row(2, "2026-09-01T12:00:00+00:00"),
  row(1, "2026-08-31T12:00:00+00:00"),
];

test("no cookie shows everything", () => {
  assert.deepEqual(visibleDeliveries(log, undefined), { rows: log, cleared: false });
  assert.equal(visibleDeliveries(log, null).rows.length, 3);
  assert.equal(visibleDeliveries(log, "").cleared, false);
});

test("a cutoff hides what it covers and keeps what came later", () => {
  const { rows, cleared } = visibleDeliveries(log, "2026-09-01T12:00:00+00:00");
  assert.equal(cleared, true);
  assert.deepEqual(rows.map((r) => r.id), [3]);

  // Clearing from the newest row hides all of them -- and stays cleared, so the
  // panel explains itself instead of claiming nothing was ever sent.
  const all = visibleDeliveries(log, "2026-09-02T12:00:00+00:00");
  assert.deepEqual(all.rows, []);
  assert.equal(all.cleared, true);
});

test("a junk cookie is no cutoff, not an empty panel", () => {
  for (const junk of ["not-a-date", "0", "undefined", "9999-99-99"]) {
    const { rows, cleared } = visibleDeliveries(log, junk);
    assert.equal(rows.length, 3, `"${junk}" blanked the delivery history`);
    assert.equal(cleared, false);
  }
});
