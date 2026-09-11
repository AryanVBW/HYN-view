import assert from "node:assert/strict";
import { test } from "node:test";
import { attemptTotal, defaultRule, effectiveDigest, validRules, type DigestSetting } from "./delivery-controls.ts";

test("delivery budgets validate bounded integers, known unique types and explicit booleans", () => {
  const rule = defaultRule("daily");
  assert.equal(validRules([rule]), true);
  assert.equal(validRules([{ ...rule, daily_limit: 0 }]), true);
  assert.equal(validRules([{ ...rule, daily_limit: 100000, max_attempts: 5, retry_minutes: 1440 }]), true);
  for (const patch of [{ daily_limit: -1 }, { daily_limit: 1.5 }, { daily_limit: 100001 }, { daily_limit: "2" }, { enabled: "true" }, { max_attempts: 0 }, { max_attempts: 6 }, { retry_minutes: 0 }, { retry_minutes: 1441 }, { kind: "auth-provider" }]) {
    assert.equal(validRules([{ ...rule, ...patch }]), false, JSON.stringify(patch));
  }
  assert.equal(validRules([]), false);
  assert.equal(validRules(null), false);
  assert.equal(validRules([rule, rule]), false);
});

test("combined digests start off and explicit user opt-outs override global enablement", () => {
  assert.equal(effectiveDigest([], "alice").enabled, false);
  assert.equal(effectiveDigest([], "alice").configured, false);
  const global: DigestSetting = { scope: "global", owner: null, configured: true, enabled: true, send_at: "08:00", timezone: "Asia/Kolkata" };
  const user: DigestSetting = { ...global, scope: "alice", owner: "alice", enabled: false };
  assert.equal(effectiveDigest([global], "alice").enabled, true);
  assert.equal(effectiveDigest([global, user], "alice").enabled, false);
  assert.equal(effectiveDigest([global, user], "bob").timezone, "Asia/Kolkata");
});

test("daily usage counts attempts rather than accepted messages", () => {
  const usage = [{ kind: "daily" as const, attempts: 5, sent: 1, failed: 3, unknown: 1 }, { kind: "incident" as const, attempts: 2, sent: 2, failed: 0, unknown: 0 }];
  assert.equal(attemptTotal(usage), 7);
  assert.equal(attemptTotal(usage, "daily"), 5);
  assert.equal(attemptTotal([], "all"), 0);
});
