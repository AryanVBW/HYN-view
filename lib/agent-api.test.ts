import assert from "node:assert/strict";
import test from "node:test";
import {
  agentRpcForAction,
  enrichIngestWithPublicIp,
  MAX_AGENT_BODY_BYTES,
} from "./agent-api.ts";

test("the hosted API exposes only the agent RPC allowlist", () => {
  assert.equal(agentRpcForAction("hyn_device_start"), "hyn_device_start");
  assert.equal(agentRpcForAction("hyn_device_poll"), "hyn_device_poll");
  assert.equal(agentRpcForAction("hyn_ingest"), "hyn_ingest");
  assert.equal(agentRpcForAction("hyn_record_bandwidth"), "hyn_record_bandwidth");
  assert.equal(agentRpcForAction("hyn_admin_share_server"), null);
  assert.equal(agentRpcForAction("hyn_server_notifications"), null);
  assert.equal(agentRpcForAction("hyn_fetch_config"), "hyn_fetch_config");
  assert.equal(agentRpcForAction("hyn_report_notification"), "hyn_report_notification");
  assert.equal(agentRpcForAction("hyn_claim_node_command"), "hyn_claim_node_command");
  assert.equal(agentRpcForAction("hyn_report_node_command"), "hyn_report_node_command");
  assert.equal(agentRpcForAction("hyn_queue_web_notification"), "hyn_queue_web_notification");
  assert.equal(agentRpcForAction("hyn_admin_overview"), null);
  assert.equal(agentRpcForAction("../hyn_ingest"), null);
});

test("the agent gateway has a bounded request size", () => {
  assert.equal(MAX_AGENT_BODY_BYTES, 1_048_576);
});

test("ingest records the machine public IP observed by the trusted gateway", () => {
  assert.deepEqual(
    enrichIngestWithPublicIp(
      {
        p_node_token: "token",
        p_payload: { network: { iface: "eth0", local_ip: "10.0.0.5/24" } },
      },
      "203.0.113.7, 10.0.0.2",
    ),
    {
      p_node_token: "token",
      p_payload: {
        network: {
          iface: "eth0",
          local_ip: "10.0.0.5/24",
          public_ip: "203.0.113.7",
        },
      },
    },
  );
});

test("the gateway rejects malformed forwarded addresses instead of storing them", () => {
  const body = { p_payload: { network: { iface: "eth0" } } };
  assert.deepEqual(enrichIngestWithPublicIp(body, "<script>alert(1)</script>"), body);
});
