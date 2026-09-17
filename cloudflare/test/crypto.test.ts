import assert from "node:assert/strict";
import { test } from "node:test";
import { equalHex, normalizeUserCode, sha256Hex, userCode } from "../src/crypto.ts";

test("user codes are eight crockford characters with a dash", () => {
  const code = userCode();
  assert.match(code, /^[2-9A-HJ-NP-TV-Z]{4}-[2-9A-HJ-NP-TV-Z]{4}$/);
  assert.equal(normalizeUserCode("qkb8 d6vq"), "QKB8-D6VQ");
});

test("hex compare is length-checked", async () => {
  const a = await sha256Hex("token");
  const b = await sha256Hex("token");
  const c = await sha256Hex("other");
  assert.equal(equalHex(a, b), true);
  assert.equal(equalHex(a, c), false);
  assert.equal(equalHex(a, a.slice(1)), false);
});
