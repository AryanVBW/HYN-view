import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizeNodeUpdate,
  readAgentRelease,
  updateIsActive,
  updateStageIndex,
} from "./node-update.ts";

test("agent release metadata is parsed defensively", () => {
  assert.deepEqual(readAgentRelease({
    agent_update: { latest: "1.7.0", available: true, checked_at: 1_787_514_000 },
  }), { latest: "1.7.0", available: true, checkedAt: 1_787_514_000 });
  assert.deepEqual(readAgentRelease(null), { latest: null, available: false, checkedAt: null });
});

test("node update commands retain only known lifecycle states", () => {
  const command = normalizeNodeUpdate({
    id: "command-id",
    node_id: "node-id",
    status: "running",
    stage: "installing",
    message: "Installing",
    target_version: "1.7.0",
    result_version: null,
    requested_at: "2026-08-24T00:00:00Z",
    started_at: "2026-08-24T00:00:05Z",
    finished_at: null,
    updated_at: "2026-08-24T00:00:10Z",
  });
  assert.equal(command?.stage, "installing");
  assert.equal(updateIsActive(command), true);
  assert.equal(updateStageIndex(command!.stage), 2);
  assert.equal(normalizeNodeUpdate({ ...command, stage: "delete-everything" }), null);
});

test("accepted commands advance to the registry-check progress position", () => {
  assert.equal(updateStageIndex("accepted"), 1);
  assert.equal(updateStageIndex("failed"), -1);
});
