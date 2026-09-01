import assert from "node:assert/strict";
import test from "node:test";
import { diagnoseEmailDelivery, senderDomainOf } from "./cloud-email.ts";

// Email delivery is the portal's job alone: the monitored machines hold no
// provider credential, sender address or recipient list. So when mail stops, the
// portal is the only thing that can say why -- and every cause below used to look
// identical from the outside, which is to say it looked like nothing at all.
//
// No test here sends a message. The diagnostic must work when mail is broken,
// which rules out proving anything by mailing somebody.

const respondWith = (body: unknown, status = 200) =>
  (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;

test("the sender domain is read from either legal EMAIL_FROM form", () => {
  // Both of these are valid and both are used in practice, including the
  // built-in default "HYN-view <reports@hyn-view.info>".
  assert.equal(senderDomainOf("HYN-view <reports@hyn-view.info>"), "hyn-view.info");
  assert.equal(senderDomainOf("reports@hyn-view.info"), "hyn-view.info");
  // Resend compares domains case-insensitively; so must we, or a capitalised
  // EMAIL_FROM would be reported as an unknown domain.
  assert.equal(senderDomainOf("HYN-view <REPORTS@HYN-VIEW.INFO>"), "hyn-view.info");
  assert.equal(senderDomainOf("not-an-address"), null);
  assert.equal(senderDomainOf("trailing@"), null);
  assert.equal(senderDomainOf(""), null);
  assert.equal(senderDomainOf(undefined), null);
});

test("a missing key and a missing sender are told apart", async () => {
  const noKey = await diagnoseEmailDelivery({
    apiKey: undefined, from: "reports@hyn-view.info", fetchImpl: respondWith({}),
  });
  assert.equal(noKey.cause, "missing-key");
  assert.equal(noKey.ok, false);

  const noFrom = await diagnoseEmailDelivery({
    apiKey: "re_x", from: undefined, fetchImpl: respondWith({}),
  });
  assert.equal(noFrom.cause, "missing-from");

  // Set but unusable is a different mistake from unset, and the message says so.
  const badFrom = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "reports-at-hyn-view.info", fetchImpl: respondWith({}),
  });
  assert.equal(badFrom.cause, "missing-from");
  assert.match(badFrom.detail, /no usable domain/);
});

test("a rejected key is named as a rejected key", async () => {
  const d = await diagnoseEmailDelivery({
    apiKey: "re_revoked", from: "reports@hyn-view.info",
    fetchImpl: respondWith({ name: "validation_error", message: "API key is invalid" }, 400),
  });
  assert.equal(d.cause, "invalid-key");
  // Resend's own words, not a paraphrase: the operator is going to search for it.
  assert.equal(d.detail, "API key is invalid");
});

test("an unverified sending domain is the difference between silence and mail", async () => {
  // The most common real cause, and the one that produces no bounce and no error
  // an operator would ever see: Resend refuses every send from an unverified
  // domain, so mail simply never arrives.
  const pending = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "HYN-view <reports@hyn-view.info>",
    fetchImpl: respondWith({ data: [{ name: "hyn-view.info", status: "pending" }] }),
  });
  assert.equal(pending.cause, "sender-domain-unverified");
  assert.match(pending.detail, /"pending"/);

  // Sending from a domain the account has never heard of fails the same way but
  // needs a different fix, so it gets a different cause and lists what IS usable.
  const unknown = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "reports@typo-domain.in",
    fetchImpl: respondWith({ data: [{ name: "hyn-view.info", status: "verified" }] }),
  });
  assert.equal(unknown.cause, "sender-domain-unknown");
  assert.match(unknown.detail, /hyn-view\.info \(verified\)/);

  const none = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "reports@hyn-view.info", fetchImpl: respondWith({ data: [] }),
  });
  assert.equal(none.cause, "sender-domain-unknown");
  assert.match(none.detail, /no domains configured at all/);
});

test("a healthy configuration is reported as healthy", async () => {
  const d = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "HYN-view <reports@hyn-view.info>",
    fetchImpl: respondWith({ data: [{ name: "hyn-view.info", status: "verified" }] }),
  });
  assert.equal(d.ok, true);
  assert.equal(d.cause, "ok");
  assert.deepEqual(d.domains, [{ name: "hyn-view.info", status: "verified" }]);
});

test("an unreachable provider is not blamed on the key", async () => {
  // Misreporting a network fault as a bad credential sends the operator to
  // rotate a key that was fine, which is worse than saying nothing.
  const d = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "reports@hyn-view.info",
    fetchImpl: (async () => { throw new Error("getaddrinfo ENOTFOUND api.resend.com"); }) as unknown as typeof fetch,
  });
  assert.equal(d.cause, "provider-unreachable");
  assert.match(d.detail, /ENOTFOUND/);

  const serverError = await diagnoseEmailDelivery({
    apiKey: "re_x", from: "reports@hyn-view.info",
    fetchImpl: respondWith({ message: "internal server error" }, 500),
  });
  assert.equal(serverError.cause, "provider-unreachable");
});

test("the diagnosis never carries the credential it checked", async () => {
  const d = await diagnoseEmailDelivery({
    apiKey: "re_super_secret_value", from: "reports@hyn-view.in",
    fetchImpl: respondWith({ data: [{ name: "hyn-view.in", status: "verified" }] }),
  });
  assert.ok(
    !JSON.stringify(d).includes("re_super_secret_value"),
    "a diagnostic that leaks the key it is checking is a worse bug than the one it finds",
  );
});
