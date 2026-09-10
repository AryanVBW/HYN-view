import test from "node:test";
import assert from "node:assert/strict";
import { byteCount, formatBytes } from "./bandwidth.ts";
test("consumption keeps integers above Number.MAX_SAFE_INTEGER exact", () => {
  assert.equal(byteCount("18446744073709551615") + byteCount("1"), BigInt("18446744073709551616"));
  assert.equal(formatBytes(BigInt("1073741824")), "1.00 GiB");
  assert.equal(formatBytes(BigInt("1536")), "1.50 KiB");
  assert.equal(formatBytes(BigInt("0")), "0.00 B");
});
test("invalid counter text does not produce NaN or negative usage", () => {
  for (const value of ["NaN", "-1", "", "1.5", "Infinity"]) assert.equal(byteCount(value), BigInt(0));
});
