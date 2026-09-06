import assert from "node:assert/strict";
import test from "node:test";
import {
  ageSeconds,
  bitmapMember,
  freshness,
  normalizeRelayer,
  relayerChecks,
  tokenAmount,
  type RelayerReading,
} from "./relayer.ts";
import { parseFleet } from "./relayer-provider.ts";

const now = Date.parse("2026-09-06T14:00:00Z");
const at = (secondsAgo: number) =>
  new Date(now - secondsAgo * 1000).toISOString();
const raw = {
  chainRelayerId: 457,
  onChainName: "praveen256",
  flags: {
    registered: true,
    online: true,
    authorized: false,
    inActiveSetMosaic: false,
    heartbeating: true,
  },
  lastCheckinAt: at(60),
  lastHeartbeatAt: at(120),
  country: "IN",
  city: "Pune",
};
function reading(): RelayerReading {
  return {
    assignment: {
      id: "assignment",
      owner: "alice",
      relayer_id: 457,
      relayer_name: "praveen256",
      created_at: at(500),
    },
    relayer: normalizeRelayer(raw),
    sourceAt: at(5),
    fetchedAt: at(1),
    providerLatencyMs: 100,
    error: null,
    chainError: null,
    chain: {
      observedAt: at(5),
      registered: true,
      authorized: true,
      inActiveSet: true,
      block: 100,
      epoch: 2,
      earningWeight: "500000",
      rewardsBalance: "1587.75",
      managerBalance: "0",
      managerExists: false,
      tokenSymbol: "TMOS",
      rewardsWallet: null,
      managerWallet: null,
      operationalKeys: [],
      blsKey: null,
      p2pKey: null,
    },
  };
}
test("normalizes provider fields without exposing arbitrary upstream data", () => {
  const r = normalizeRelayer({
    ...raw,
    password: "never-forward",
    latitude: -18.5,
    longitude: 181,
  })!;
  assert.equal(r.id, 457);
  assert.equal(r.latitude, -18.5);
  assert.equal(r.longitude, null);
  assert.equal(r.authorized, false);
  assert.equal(r.inActiveSet, false);
  assert.equal("password" in r, false);
  assert.equal(normalizeRelayer({ chainRelayerId: "457" }), null);
  assert.equal(normalizeRelayer({ chainRelayerId: 0 }), null);
  assert.equal(normalizeRelayer({ chainRelayerId: 2.5 }), null);
  assert.equal(
    normalizeRelayer({ chainRelayerId: 1, flags: { registered: "true" } })
      ?.registered,
    null,
  );
});
test("check-in and heartbeat limits are strict and missing timestamps stay unknown", () => {
  assert.equal(freshness(at(299), 300, now), true);
  assert.equal(freshness(at(300), 300, now), false);
  assert.equal(freshness(at(659), 660, now), true);
  assert.equal(freshness(at(660), 660, now), false);
  assert.equal(ageSeconds(null, now), null);
  assert.equal(ageSeconds("bad timestamp", now), null);
  assert.equal(ageSeconds(at(-120), now), null);
  assert.equal(ageSeconds(at(-5), now), 0);
});
test("finalized registry flags take precedence over lagging fleet flags", () => {
  const result = relayerChecks(reading(), now);
  assert.equal(result.label, "Healthy");
  assert.equal(result.passed, 5);
});
test("stale provider or chain observations cannot display all checks passing", () => {
  const r = reading();
  r.sourceAt = at(121);
  assert.equal(relayerChecks(r, now).checks[1].value, null);
  assert.notEqual(relayerChecks(r, now).label, "Healthy");
  r.sourceAt = at(5);
  r.chain!.observedAt = at(121);
  assert.equal(relayerChecks(r, now).checks[2].value, null);
  assert.equal(relayerChecks(r, now).checks[3].value, null);
});
test("failed requests, absent records and false flags stay visible", () => {
  const r = reading();
  r.error = "failed";
  assert.equal(relayerChecks(r, now).checks[4].value, null);
  r.error = null;
  r.relayer!.heartbeating = false;
  assert.equal(relayerChecks(r, now).label, "Needs attention");
  r.relayer = null;
  r.chain = null;
  assert.equal(relayerChecks(r, now).passed, 0);
});
test("ages advance without a new fetch; positive flags cannot hide an overdue heartbeat", () => {
  const r = reading();
  r.relayer!.lastHeartbeatAt = at(660);
  assert.equal(relayerChecks(r, now).checks[4].value, false);
});
test("Highway bitmaps use ID minus one, including byte boundaries", () => {
  assert.equal(bitmapMember("0x8101", 1), true);
  assert.equal(bitmapMember("0x8101", 2), false);
  assert.equal(bitmapMember("0x8101", 8), true);
  assert.equal(bitmapMember("0x8101", 9), true);
  assert.equal(bitmapMember("0x8101", 17), false);
  assert.equal(bitmapMember("0x0", 1), null);
  assert.equal(bitmapMember("0xff", 0), null);
});
test("u128 token values retain precision, including zero and hexadecimal encoding", () => {
  assert.equal(
    tokenAmount("1587750000000000000001", 18),
    "1587.750000000000000001",
  );
  assert.equal(tokenAmount("0x0", 18), "0");
  assert.equal(tokenAmount("0x01", 18), "0.000000000000000001");
  assert.equal(tokenAmount("500000", 0), "500000");
  assert.equal(tokenAmount(null, 18), null);
  assert.equal(tokenAmount(-1, 18), null);
  assert.equal(tokenAmount(Number.MAX_SAFE_INTEGER + 1, 18), null);
});
test("feed schema errors and duplicate IDs fail closed; a missing source timestamp stays missing", () => {
  assert.throws(() => parseFleet({ rows: [] }, at(0), 20));
  assert.throws(() => parseFleet({ relayers: [raw, raw] }, at(0), 20));
  assert.throws(() =>
    parseFleet({ relayers: [{ chainRelayerId: -1 }] }, at(0), 20),
  );
  const result = parseFleet({ relayers: [raw] }, at(0), 20);
  assert.equal(result.sourceAt, null);
});
