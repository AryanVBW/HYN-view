import assert from "node:assert/strict";
import test from "node:test";
import { agentRpcForAction, MAX_AGENT_BODY_BYTES } from "./agent-api.ts";

test("the hosted API exposes only the five agent RPCs", () => {
  assert.equal(agentRpcForAction("hyn_device_start"), "hyn_device_start");
  assert.equal(agentRpcForAction("hyn_device_poll"), "hyn_device_poll");
  assert.equal(agentRpcForAction("hyn_ingest"), "hyn_ingest");
  assert.equal(agentRpcForAction("hyn_fetch_config"), "hyn_fetch_config");
  assert.equal(agentRpcForAction("hyn_report_notification"), "hyn_report_notification");
  assert.equal(agentRpcForAction("hyn_admin_overview"), null);
  assert.equal(agentRpcForAction("../hyn_ingest"), null);
});

test("the agent gateway has a bounded request size", () => {
  assert.equal(MAX_AGENT_BODY_BYTES, 1_048_576);
});
