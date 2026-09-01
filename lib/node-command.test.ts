import assert from "node:assert/strict";
import test from "node:test";
import {
  commandBlockedReason,
  commandIsActive,
  commandRecovery,
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

test("an administrative refusal is not answered with server recovery commands", () => {
  // The bug: every failure printed "sudo hyn doctor / restart hyn-push.timer",
  // including "active node not found" for a machine that was simply paused --
  // sending the operator to repair an agent that was working correctly.
  const paused = commandRecovery(
    "monitoring is paused for this machine until 2026-09-02 04:15 UTC, so it is not accepting readings or commands. Resume it in the portal."
  );
  assert.equal(paused.where, "portal");
  assert.deepEqual(paused.commands, []);

  assert.equal(commandRecovery("this machine is suspended, so it is not accepting readings").where, "portal");
  assert.equal(commandRecovery("this is demo data rather than a real server").where, "portal");
  assert.equal(commandRecovery("that machine belongs to another account").where, "portal");

  // Revoked is the one refusal whose fix really is on the machine.
  const revoked = commandRecovery("this machine's credential was revoked. Pair it again: sudo hyn link");
  assert.equal(revoked.where, "server");
  assert.deepEqual(revoked.commands, ["sudo hyn link"]);

  // An agent-side failure or a timeout keeps the server recovery it needs.
  const timeout = commandRecovery("the machine did not check in within 10 minutes");
  assert.equal(timeout.where, "server");
  assert.ok(timeout.commands.some((line) => line.includes("hyn doctor")));
  assert.equal(commandRecovery(null).where, "server");
});

test("a machine that cannot accept a command says so before it is clicked", () => {
  const active = { status: "active" as const, revoked: false, is_demo: false };
  assert.equal(commandBlockedReason(active), null);
  assert.match(commandBlockedReason({ ...active, status: "paused" }) ?? "", /paused/);
  assert.match(commandBlockedReason({ ...active, status: "suspended" }) ?? "", /suspended/);
  assert.match(commandBlockedReason({ ...active, revoked: true }) ?? "", /hyn link/);
  assert.match(commandBlockedReason({ ...active, is_demo: true }) ?? "", /Demo/);
});
