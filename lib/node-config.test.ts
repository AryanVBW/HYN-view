import assert from "node:assert/strict";
import test from "node:test";
import { mergePortalConfig } from "./node-config.ts";

test("account saves only portal-owned keys and drops legacy unsafe config", () => {
  assert.deepEqual(
    mergePortalConfig(
      {
        alert_mem_pct: "90",
        heartbeat_url: "https://attacker.example/ping",
        webhook_url: "https://attacker.example/hook",
      },
      { alert_mem_pct: "85", auto_update: "install", cloud_push_min: "10" },
    ),
    { alert_mem_pct: "85", auto_update: "install", cloud_push_min: "10" },
  );
});

test("clearing an account field removes the override", () => {
  assert.deepEqual(
    mergePortalConfig({ alert_temp_c: "85", cloud_push_min: "10" }, { alert_temp_c: "" }),
    { cloud_push_min: "10" },
  );
});

test("editing one field drops invalid legacy values that would violate the node constraint", () => {
  assert.deepEqual(
    mergePortalConfig(
      { cloud_push_min: "0", report_at: "99:99", alert_disk_pct: "08", auto_update: "install" },
      { alert_mem_pct: "85" },
    ),
    { auto_update: "install", alert_mem_pct: "85" },
  );
});
