import assert from "node:assert/strict";
import { mock, test } from "node:test";
let allowed = false;
let active = true;
let signedIn = true;
let canMonitor = false;
const reads: string[] = [];
const checks: unknown[] = [];
let providerReads = 0;
mock.module("../lib/supabase/config.ts", {
  namedExports: { isSupabaseConfigured: true },
});
mock.module("../lib/supabase/server.ts", {
  namedExports: {
    createClient: async () => ({
      auth: {
        getUser: async () => ({
          data: { user: signedIn ? { id: "viewer" } : null },
        }),
      },
      rpc: async (name: string, params: unknown) => {
        if (name === "hyn_can_view_dashboard") {
          checks.push(params);
          return { data: allowed, error: null };
        }
        return {
          data:
            name === "hyn_is_active"
              ? active
              : name === "hyn_can_monitor"
                ? canMonitor
                : false,
          error: null,
        };
      },
      from: (table: string) => {
        const query = {
          select() {
            return query;
          },
          eq(column: string, value: string) {
            if (table === "relayer_assignments" && column === "owner")
              reads.push(value);
            return query;
          },
          in() {
            return query;
          },
          order() {
            return query;
          },
          limit() {
            return query;
          },
          then(resolve: (result: unknown) => unknown) {
            return Promise.resolve(resolve({ data: [], error: null }));
          },
        };
        return query;
      },
    }),
  },
});
mock.module("../lib/relayer-data.ts", {
  namedExports: {
    readAssignedRelayers: async () => {
      providerReads++;
      return { readings: [] };
    },
  },
});
const route = import("../app/api/relayers/route.ts");
const get = async (owner?: string) =>
  (await route).GET(
    new Request(
      `https://portal.example/api/relayers${owner ? `?owner=${owner}` : ""}`,
    ),
  );

test("foreign dashboard relayers require an explicit database access check before provider reads", async () => {
  reads.length = 0;
  providerReads = 0;
  assert.equal((await get("private-owner")).status, 403);
  assert.equal(reads.length, 0);
  assert.equal(providerReads, 0);
  allowed = true;
  assert.equal((await get("shared-owner")).status, 200);
  assert.deepEqual(reads, ["shared-owner"]);
  assert.deepEqual(checks.at(-1), { p_owner: "shared-owner" });
  allowed = false;
});
test("viewer sees no relayer request controls while monitor can request access", async () => {
  assert.equal((await (await get()).json()).canRequest, false);
  canMonitor = true;
  assert.equal((await (await get()).json()).canRequest, true);
  canMonitor = false;
});
test("signed-out and suspended sessions never read provider telemetry", async () => {
  providerReads = 0;
  signedIn = false;
  assert.equal((await get()).status, 401);
  signedIn = true;
  active = false;
  assert.equal((await get()).status, 403);
  active = true;
  assert.equal(providerReads, 0);
});
