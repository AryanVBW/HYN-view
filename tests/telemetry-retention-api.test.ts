import assert from "node:assert/strict";
import { mock, test } from "node:test";

let calls = 0;
let remaining = 0;
let fail = false;
mock.module("@supabase/supabase-js", {namedExports: {
  createClient: () => ({rpc: async (name: string, args: unknown) => {
    calls++;
    assert.equal(name, "hyn_prune_telemetry");
    assert.deepEqual(args, {p_batch: 5000});
    return fail ? {data: null, error: {message: "private database diagnostic"}}
      : {data: {status: "ok", has_more: --remaining > 0}, error: null};
  }}),
}});
mock.module("../lib/supabase/config.ts", {namedExports: {SUPABASE_URL: "https://example.test"}});
const endpoint = import("../app/api/cron/telemetry/route");

test("retention endpoint authenticates before database access and bounds cleanup", async () => {
  const {GET} = await endpoint;
  const previousSecret = process.env.CRON_SECRET;
  const previousKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.CRON_SECRET = "test-cron-only";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-only";
  const request = () => new Request("https://example.test/api/cron/telemetry", {
    headers: {authorization: "Bearer test-cron-only"},
  });
  try {
    calls = 0;
    assert.equal((await GET(new Request("https://example.test/api/cron/telemetry"))).status, 401);
    assert.equal(calls, 0);
    remaining = 100;
    const response = await GET(request());
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(calls, 4, "one invocation must not drain an unbounded backlog");
    assert.equal((await response.json()).has_more, true);
    calls = 0;
    remaining = 1;
    assert.equal((await GET(request())).status, 200);
    assert.equal(calls, 1);
    fail = true;
    const failed = await GET(request());
    assert.equal(failed.status, 503);
    assert.doesNotMatch(await failed.text(), /private database diagnostic/);
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    assert.equal((await GET(request())).status, 503);
  } finally {
    fail = false;
    if (previousSecret === undefined) delete process.env.CRON_SECRET;
    else process.env.CRON_SECRET = previousSecret;
    if (previousKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = previousKey;
  }
});
