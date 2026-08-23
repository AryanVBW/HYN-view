import assert from "node:assert/strict";
import test from "node:test";
import {
  commandIsActive,
  commandStageIndex,
  commandSteps,
  normalizeNodeCommand,
  readAgentRelease,
} from "./node-command.ts";

const valid = {
  id: "command-id",
  node_id: "node-id",
  command: "sync",
  status: "running",
  stage: "collecting",
  message: "Collecting",
  target_version: null,
  result_version: null,
  requested_at: "2026-08-24T00:00:00Z",
  started_at: "2026-08-24T00:00:05Z",
  finished_at: null,
  updated_at: "2026-08-24T00:00:10Z",
};

test("agent release metadata is parsed defensively", () => {
  assert.deepEqual(readAgentRelease({
    agent_update: { latest: "1.7.0", available: true, checked_at: 1_787_514_000 },
  }), { latest: "1.7.0", available: true, checkedAt: 1_787_514_000 });
  assert.deepEqual(readAgentRelease(null), { latest: null, available: false, checkedAt: null });
});

test("sync and update expose different observable progress contracts", () => {
  assert.deepEqual(commandSteps("sync").map((step) => step.key), [
    "queued", "collecting", "uploading", "verifying", "completed",
  ]);
  assert.deepEqual(commandSteps("update").map((step) => step.key), [
    "queued", "checking", "installing", "restarting", "verifying", "completed",
  ]);
  assert.equal(commandStageIndex("sync", "accepted"), 1);
  assert.equal(commandStageIndex("sync", "failed"), -1);
});

test("command normalization rejects unknown kinds and cross-kind stages", () => {
  const command = normalizeNodeCommand(valid);
  assert.equal(command?.command, "sync");
  assert.equal(command?.stage, "collecting");
  assert.equal(commandIsActive(command), true);
  assert.equal(normalizeNodeCommand({ ...valid, command: "erase" }), null);
  assert.equal(normalizeNodeCommand({ ...valid, stage: "installing" }), null);
  assert.equal(normalizeNodeCommand({ ...valid, status: "approved" }), null);
});
