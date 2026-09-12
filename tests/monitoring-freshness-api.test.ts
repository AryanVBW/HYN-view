import assert from "node:assert/strict";
import { mock, test } from "node:test";

const id = "11111111-1111-4111-8111-111111111111";
let signedIn = true;
let active = true;
let allowed = true;
let failed = false;
let nodeReads = 0;
mock.module("../lib/supabase/server.ts", {namedExports: {createClient: async () => ({
  auth: {getUser: async () => ({data: {user: signedIn ? {id: "account"} : null}, error: null})},
  from: (table: string) => {
    if (table === "nodes") nodeReads++;
    const query = {
      select: (columns: string) => { assert.doesNotMatch(columns, /token_hash|payload/); return query; },
      eq: (key: string, value: unknown) => {
        if (table === "nodes" && key === "id") assert.equal(value, id);
        if (table === "nodes" && key === "revoked") assert.equal(value, false);
        return query;
      },
      maybeSingle: async () => table === "profiles" ? {data: {status: active ? "active" : "suspended"}, error: null}
        : {data: allowed ? {id, status: "active", last_metric_at: "2026-09-12T12:00:00Z", last_heartbeat_at: "2026-09-12T12:00:24Z"} : null, error: failed ? {message: "private database failure"} : null},
    };
    return query;
  },
})}});
const route = import("../app/api/dashboard/freshness/route");
const request = (node = id) => new Request(`https://portal.test/api/dashboard/freshness?node=${node}`);

test("freshness reads a small authorized node state and never sends full telemetry", async () => {
  const response = await (await route).GET(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  const body = await response.json();
  assert.deepEqual(Object.keys(body).sort(), ["heartbeatAt", "nodeId", "revision"]);
  assert.equal(body.heartbeatAt, "2026-09-12T12:00:24Z");
});

test("freshness stops on invalid, signed-out, suspended, revoked or inaccessible nodes", async () => {
  const {GET} = await route;
  nodeReads = 0;
  assert.equal((await GET(request("invalid"))).status, 400);
  signedIn = false;
  assert.equal((await GET(request())).status, 401);
  signedIn = true; active = false;
  assert.equal((await GET(request())).status, 403);
  assert.equal(nodeReads, 0);
  active = true; allowed = false;
  assert.equal((await GET(request())).status, 404);
  allowed = true; failed = true;
  const response = await GET(request());
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /private database failure/);
  failed = false;
});
