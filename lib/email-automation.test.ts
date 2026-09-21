import assert from "node:assert/strict";
import test from "node:test";
import { automaticEmailAllowed, automaticEmailKinds } from "./email-automation.ts";
import { sendManagedEmail } from "./delivery-send.ts";
import { deliveryKinds, type MessageKind } from "./delivery-controls.ts";

const everyKind = deliveryKinds
  .map((kind) => kind.key)
  .filter((key): key is MessageKind => key !== "all");

test("only the sign-in security notice may send itself; every other kind is manual", () => {
  assert.deepEqual([...automaticEmailKinds], ["signin"]);
  assert.equal(automaticEmailAllowed("signin"), true);
  for (const kind of everyKind.filter((key) => key !== "signin")) {
    assert.equal(automaticEmailAllowed(kind), false, `${kind} must not send automatically`);
  }
});

// The gate has to refuse before the provider is contacted, otherwise "stopped"
// would still burn quota and still record an attempt. No credentials and no
// fetch implementation are supplied here on purpose: if the refusal did not come
// first, this test would try to reach the network and fail.
test("an automatic non-auth send is refused before the provider is contacted", async () => {
  for (const kind of everyKind.filter((key) => key !== "signin")) {
    const result = await sendManagedEmail({
      delivery: { kind, ownerId: "11111111-1111-1111-1111-111111111111" },
      apiKey: "must-not-be-used",
      from: "HYN-view <reports@example.com>",
      to: "owner@example.com",
      subject: "should never send",
      html: "<p>should never send</p>",
      idempotencyKey: `gate-test:${kind}`,
      fetchImpl: () => {
        throw new Error(`${kind} reached the provider despite being manual-only`);
      },
    });
    assert.equal(result.ok, false);
    assert.equal(result.ok === false && result.deferred, true, `${kind} should defer, not hard-fail`);
    assert.match(result.ok === false ? result.error : "", /switched off|administrator/i);
  }
});

test("an administrator's manual send is not blocked by the automation gate", async () => {
  let reached = false;
  const result = await sendManagedEmail({
    delivery: { kind: "admin_report", ownerId: "11111111-1111-1111-1111-111111111111", manual: true },
    apiKey: "test-key",
    from: "HYN-view <reports@example.com>",
    to: "owner@example.com",
    subject: "manual report",
    html: "<p>manual report</p>",
    idempotencyKey: "gate-test:manual",
    fetchImpl: async () => {
      reached = true;
      return new Response(JSON.stringify({ id: "provider-1" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  });
  assert.equal(reached, true, "a manual send must be allowed through to the provider");
  assert.equal(result.ok, true);
});
