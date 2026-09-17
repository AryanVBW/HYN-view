import assert from "node:assert/strict";
import { mock, test } from "node:test";

process.env.HYN_DATA_API_URL = "https://d1.test";
process.env.HYN_DATA_SERVICE_KEY = "svc-key";

const calls: { url: string; headers: Record<string, string> }[] = [];

mock.module("../lib/supabase/server.ts", {
  namedExports: {
    createClient: async () => ({
      auth: {
        getUser: async () => ({
          data: { user: { id: "11111111-1111-4111-8111-111111111111", email: "owner@example.test" } },
        }),
        getSession: async () => ({ data: { session: null } }),
      },
    }),
  },
});

const fetchMock = mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
  const headers = new Headers(init?.headers);
  calls.push({
    url: String(input),
    headers: Object.fromEntries(headers.entries()),
  });
  return Response.json([{ id: "node-1", name: "krishna" }]);
});

const { userDataRpc } = await import("../lib/hyn-data.ts");

test("portal RPCs authenticate with the service key and the signed-in user id", async (t) => {
  t.after(() => fetchMock.mock.restore());
  const result = await userDataRpc("hyn_list_nodes");
  assert.equal(result.error, null);
  assert.deepEqual(result.data, [{ id: "node-1", name: "krishna" }]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, "https://d1.test/rpc/hyn_list_nodes");
  assert.equal(calls[0]?.headers.authorization, "Bearer svc-key");
  assert.equal(calls[0]?.headers["x-hyn-user-id"], "11111111-1111-4111-8111-111111111111");
  assert.equal(calls[0]?.headers["x-hyn-user-email"], "owner@example.test");
});
