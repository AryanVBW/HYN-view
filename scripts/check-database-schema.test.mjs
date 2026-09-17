import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { test } from "node:test";

async function runGate(reply, extraConfig = {}) {
  const server = createServer((request, response) => {
    const name = request.url.split("/").at(-1);
    const result = reply(name, request.url);
    response.writeHead(result.status, { "Content-Type": "application/json" });
    response.end(JSON.stringify(result.body));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  try {
    const child = spawn(process.execPath, [new URL("./check-database-schema.mjs", import.meta.url).pathname]);
    let output = "";
    child.stdout.on("data", chunk => { output += chunk; });
    child.stderr.on("data", chunk => { output += chunk; });
    const origin = `http://127.0.0.1:${server.address().port}`;
    const extra = typeof extraConfig === "function" ? extraConfig(origin) : extraConfig;
    child.stdin.end(JSON.stringify({
      NEXT_PUBLIC_SUPABASE_URL: origin,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "release-gate-test-key",
      SUPABASE_SERVICE_ROLE_KEY: "release-gate-service-fixture",
      ...extra,
    }));
    const code = await new Promise((resolve, reject) => {
      child.on("close", resolve);
      child.on("error", reject);
    });
    return { code, output };
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

const denied = () => ({ status: 401, body: { code: "42501", message: "permission denied" } });

for (const missing of ["hyn_dashboard_accounts", "hyn_is_super_admin", "hyn_can_link", "hyn_admin_delivery_dashboard", "hyn_reserve_delivery", "hyn_due_user_digests", "hyn_metric_history", "hyn_fleet_metric_history", "hyn_prune_telemetry"]) {
  test(`release fails when ${missing} is missing even if server access functions exist`, async () => {
    const result = await runGate(name => name === missing
      ? { status: 404, body: { code: "PGRST202", message: "function missing" } }
      : denied());
    assert.notEqual(result.code, 0);
    assert.match(result.output, new RegExp(missing));
    assert.match(result.output, /PGRST202/);
  });
}

test("release accepts installed functions that deny anonymous access", async () => {
  const result = await runGate(denied);
  assert.equal(result.code, 0, result.output);
});

test("release rejects anonymous dashboard access", async () => {
  const result = await runGate(name => name === "hyn_dashboard_accounts"
    ? { status: 200, body: [] }
    : denied());
  assert.notEqual(result.code, 0);
  assert.match(result.output, /hyn_dashboard_accounts/);
});

test("D1 cutover checks the worker health endpoint instead of PostgREST", async () => {
  const result = await runGate((_name, url) => url === "/health"
    ? { status: 200, body: { service: "hyn-agent-v1", store: "d1" } }
    : { status: 500, body: { message: "postgres should not be probed" } },
  (origin) => ({ HYN_DATA_API_URL: origin, HYN_DATA_SERVICE_KEY: "d1-key" }));
  assert.equal(result.code, 0, result.output);
  assert.match(result.output, /D1 worker/);
});

test("D1 cutover fails when the worker is not serving D1", async () => {
  const result = await runGate(() => ({ status: 200, body: { store: "postgres" } }),
    (origin) => ({ HYN_DATA_API_URL: origin, HYN_DATA_SERVICE_KEY: "d1-key" }));
  assert.notEqual(result.code, 0);
  assert.match(result.output, /D1 worker health/);
});
