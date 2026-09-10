import assert from "node:assert/strict";
import { mock, test } from "node:test";

let signedIn = true;
let active = true;
let canMonitor = true;
let unavailable = false;
const calls: { name: string; params: unknown }[] = [];
mock.module("../lib/supabase/config.ts", {
  namedExports: { isSupabaseConfigured: true },
});
mock.module("../lib/supabase/server.ts", {
  namedExports: {
    createClient: async () => ({
      auth: {
        getUser: async () => ({
          data: { user: signedIn ? { id: "caller" } : null },
        }),
      },
      rpc: async (name: string, params: unknown) => {
        calls.push({ name, params });
        return {
          data: name === "hyn_is_active" ? active : name === "hyn_can_monitor" ? canMonitor : "saved-request",
          error: null,
        };
      },
    }),
  },
});
mock.module("../lib/relayer-provider.ts", {
  namedExports: {
    fetchFleet: async () => {
      if (unavailable) throw new Error("offline");
      return { relayers: [{ id: 457, name: "Verified Highway Name" }] };
    },
  },
});
const route = import("../app/api/relayers/requests/route.ts");
const POST = async (request: Request) => (await route).POST(request);
const request = (body: unknown, origin = "https://www.hyn-view.in") =>
  new Request("http://0.0.0.0:3407/api/relayers/requests", {
    method: "POST",
    headers: {
      origin,
      host: "www.hyn-view.in",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

test("request writes accept the Heroku public origin and use provider identity, never a supplied owner", async () => {
  const response = await POST(
    request({
      action: "request",
      query: "#457",
      owner: "someone-else",
      name: "forged",
    }),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(calls.at(-1), {
    name: "hyn_request_relayer",
    params: { p_relayer_id: 457, p_relayer_name: "Verified Highway Name" },
  });
  assert.match(response.headers.get("cache-control")!, /no-store/);
});
test("cross-origin, signed-out and suspended requests never reach a write RPC", async () => {
  calls.length = 0;
  assert.equal(
    (
      await POST(
        request(
          { action: "request", query: "457" },
          "https://untrusted.example",
        ),
      )
    ).status,
    403,
  );
  assert.equal(calls.length, 0);
  signedIn = false;
  assert.equal(
    (await POST(request({ action: "request", query: "457" }))).status,
    401,
  );
  signedIn = true;
  active = false;
  assert.equal(
    (await POST(request({ action: "request", query: "457" }))).status,
    403,
  );
  active = true;
  assert.equal(calls.filter((c) => !(["hyn_is_active", "hyn_can_monitor"].includes(c.name))).length, 0);
});
test("unknown relayers and provider outages cannot create unverified requests", async () => {
  calls.length = 0;
  assert.equal(
    (await POST(request({ action: "request", query: "999" }))).status,
    400,
  );
  unavailable = true;
  assert.equal(
    (await POST(request({ action: "request", query: "457" }))).status,
    502,
  );
  unavailable = false;
  assert.equal(calls.filter((c) => !(["hyn_is_active", "hyn_can_monitor"].includes(c.name))).length, 0);
});

test("read-only roles cannot submit or cancel relayer requests", async () => {
  canMonitor = false;
  calls.length = 0;
  try {
    assert.equal((await POST(request({ action: "request", query: "457" }))).status, 403);
    assert.equal((await POST(request({ action: "cancel", requestId: "10000000-0000-4000-8000-000000000001" }))).status, 403);
    assert.equal(calls.filter(c => !["hyn_is_active", "hyn_can_monitor"].includes(c.name)).length, 0);
  } finally { canMonitor = true; }
});
