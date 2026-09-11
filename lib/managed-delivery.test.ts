import assert from "node:assert/strict";
import { test } from "node:test";
import { runManagedDelivery, type DeliveryReservation, type ProviderDelivery } from "./managed-delivery.ts";

function harness(reservation: DeliveryReservation, outcome: ProviderDelivery = { ok: true, providerId: "provider-1" }) {
  let sends = 0;
  const completions: unknown[][] = [];
  const dependencies = {
    reserve: async () => reservation,
    send: async () => { sends++; return outcome; },
    complete: async (...args: [string, "sent" | "failed" | "unknown", string | null, string | null]) => { completions.push(args); },
  };
  return { dependencies, completions, sends: () => sends };
}

test("refused reservations and failed database calls never contact the provider", async () => {
  const h = harness({ allowed: false, reason: "Daily limit reached" });
  assert.equal((await runManagedDelivery(h.dependencies)).ok, false);
  assert.equal(h.sends(), 0);
  assert.equal(h.completions.length, 0);
  const result = await runManagedDelivery({ ...h.dependencies, reserve: async () => { throw new Error("Database unavailable"); } });
  assert.equal(result.ok, false);
  assert.equal(h.sends(), 0);
});

test("an accepted idempotency key is reused without another email", async () => {
  const h = harness({ allowed: false, already_sent: true, provider_id: "existing" });
  assert.deepEqual(await runManagedDelivery(h.dependencies), { ok: true, providerId: "existing", reused: true });
  assert.equal(h.sends(), 0);
});

test("accepted sends and definite failures retain their exact attempt outcomes", async () => {
  const h = harness({ allowed: true, attempt_id: "attempt-1" });
  assert.equal((await runManagedDelivery(h.dependencies)).ok, true);
  assert.equal(h.sends(), 1);
  assert.deepEqual(h.completions, [["attempt-1", "sent", "provider-1", null]]);
  const failure = harness({ allowed: true, attempt_id: "attempt-2" }, { ok: false, error: "Provider rejected recipient" });
  assert.equal((await runManagedDelivery(failure.dependencies)).ok, false);
  assert.deepEqual(failure.completions, [["attempt-2", "failed", null, "Provider rejected recipient"]]);
});

test("ambiguous outcomes are recorded as unknown rather than retried blindly", async () => {
  const h = harness({ allowed: true, attempt_id: "attempt-3" }, { ok: false, error: "Timeout", uncertain: true });
  const result = await runManagedDelivery(h.dependencies);
  assert.equal(result.ok, false);
  assert.equal(h.completions[0][1], "unknown");
  const thrown = harness({ allowed: true, attempt_id: "attempt-4" });
  await runManagedDelivery({ ...thrown.dependencies, send: async () => { throw new Error("Network interrupted"); } });
  assert.equal(thrown.completions[0][1], "unknown");
});

test("a failed completion write cannot turn provider acceptance into a resend", async () => {
  const h = harness({ allowed: true, attempt_id: "attempt-5" });
  const result = await runManagedDelivery({ ...h.dependencies, complete: async () => { throw new Error("Database lost"); } });
  assert.equal(result.ok, true);
  assert.equal(h.sends(), 1);
});
