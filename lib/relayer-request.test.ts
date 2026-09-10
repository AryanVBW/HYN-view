import assert from "node:assert/strict";
import test from "node:test";
import { normalizeRelayer } from "./relayer.ts";
import { requestedRelayer } from "./relayer-request.ts";

const fleet = [
  normalizeRelayer({ chainRelayerId: 457, onChainName: "Alice" })!,
  normalizeRelayer({ chainRelayerId: 458, onChainName: "Bob" })!,
];
test("relayer requests resolve exact names or copied IDs without guessing a partial match", () => {
  assert.equal(requestedRelayer(fleet, " alice ").id, 457);
  assert.equal(requestedRelayer(fleet, "#458").id, 458);
  assert.throws(() => requestedRelayer(fleet, "ali"), /not found/i);
  assert.throws(() => requestedRelayer(fleet, ""), /name or/i);
  assert.throws(() => requestedRelayer(fleet, "0"), /not found/i);
  assert.throws(
    () => requestedRelayer([...fleet, { ...fleet[0], id: 459 }], "Alice"),
    /numeric/i,
  );
});
