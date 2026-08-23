import assert from "node:assert/strict";
import test from "node:test";
import { heartbeatState } from "./heartbeat.ts";

const now = Date.parse("2026-08-24T12:00:00Z");

test("heartbeat state allows three one-minute checks before gone quiet", () => {
  assert.deepEqual(heartbeatState("2026-08-24T11:59:31Z", now), {
    key: "connected", ageSeconds: 29, label: "Connected · 29s ago",
  });
  assert.deepEqual(heartbeatState("2026-08-24T11:57:31Z", now), {
    key: "delayed", ageSeconds: 149, label: "Delayed · 2m 29s ago",
  });
  assert.deepEqual(heartbeatState("2026-08-24T11:57:00Z", now), {
    key: "quiet", ageSeconds: 180, label: "Gone quiet · 3m ago",
  });
});

test("missing, invalid, and future heartbeats are reported honestly", () => {
  assert.deepEqual(heartbeatState(null, now), {
    key: "unknown", ageSeconds: null, label: "Heartbeat unknown",
  });
  assert.deepEqual(heartbeatState("not-a-date", now), {
    key: "unknown", ageSeconds: null, label: "Heartbeat unknown",
  });
  assert.equal(heartbeatState("2026-08-24T12:00:30Z", now).ageSeconds, 0);
});
