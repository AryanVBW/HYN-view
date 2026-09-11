import assert from "node:assert/strict";
import { mock, test } from "node:test";

let enabled = true;
let contentError = false;
let permitted = true;
const calls: { name: string; params: Record<string, unknown> }[] = [];
const sent: Record<string, unknown>[] = [];
const owner = "e1000000-0000-4000-8000-000000000001";
const nodes = [
  { id: "node-1", name: "Mumbai <gateway>", hostname: "gateway", status: "online", telemetry_mode: "cloud", last_heartbeat_at: "2026-09-11T00:00:00Z", sample_count: 24, cpu_average: 20, cpu_peak: 40, memory_average: 30, temperature_peak: 50, download_average: 100, upload_average: 200, latency_average: 20, uptime: 86400 },
  { id: "node-2", name: "Pune worker", hostname: "worker", status: "online", telemetry_mode: "local", last_heartbeat_at: "2026-09-11T00:00:00Z", sample_count: 0, cpu_average: null, cpu_peak: null, memory_average: null, temperature_peak: null, download_average: null, upload_average: null, latency_average: null, uptime: null },
];
process.env.SUPABASE_SERVICE_ROLE_KEY = "fake-service-key-for-isolated-test";
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.RESEND_API_KEY = "fake-provider-key-for-isolated-test";
mock.module("@supabase/supabase-js", { namedExports: { createClient: () => ({
  rpc: async (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    if (name === "hyn_due_user_digests") return { data: [{ owner, local_date: "2026-09-11" }], error: null };
    assert.equal(name, "hyn_user_digest_content");
    return { data: contentError ? null : { name: "Alice", recipient: "alice@example.test", nodes: permitted ? nodes : [] }, error: contentError ? { message: "Database unavailable" } : null };
  },
  from: (table: string) => {
    assert.equal(table, "notification_templates");
    const result = Promise.resolve({ data: { html: null }, error: null });
    const query: object = new Proxy({}, { get: (_target, key) => key === "then" ? result.then.bind(result) : () => query });
    return query;
  },
}) } });
mock.module("../lib/delivery-send.ts", { namedExports: {
  deliveryControlsEnabled: () => enabled,
  sendManagedEmail: async (args: Record<string, unknown>) => { sent.push(args); return { ok: true, providerId: "test-provider" }; },
} });

test("daily dispatch sends one combined email per user, with a stable key and a complete scope recheck", async () => {
  const { dispatchUserDigests } = await import("../lib/user-digest");
  sent.length = 0; calls.length = 0;
  const result = await dispatchUserDigests("node-1");
  assert.equal(result.sent, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].idempotencyKey, `user-digest:${owner}:2026-09-11`);
  assert.deepEqual(sent[0].delivery, { kind: "daily", ownerId: owner, nodeIds: ["node-1", "node-2"] });
  assert.equal(sent[0].to, "alice@example.test");
  assert.match(String(sent[0].html), /Mumbai &lt;gateway&gt;/);
  assert.match(String(sent[0].html), /Pune worker/);
  assert.equal(String(sent[0].html).includes("Mumbai <gateway>"), false);
  assert.deepEqual(calls[0], { name: "hyn_due_user_digests", params: { p_trigger_node: "node-1" } });
});

test("disabled controls, empty permissions and content failures send no emails", async () => {
  const { dispatchUserDigests } = await import("../lib/user-digest");
  sent.length = 0; calls.length = 0;
  enabled = false;
  await dispatchUserDigests();
  assert.equal(calls.length, 0);
  enabled = true; permitted = false;
  await dispatchUserDigests();
  assert.equal(sent.length, 0);
  permitted = true; contentError = true;
  const result = await dispatchUserDigests();
  assert.equal(result.failed, 1);
  assert.equal(sent.length, 0);
  contentError = false;
});
