import assert from "node:assert/strict";
import { mock, test } from "node:test";
import type { RelayerAssignment } from "../lib/relayer";
let allowed = false;
let active = true;
let signedIn = true;
let canMonitor = false;
let canAdmin = false;
let nodeAllowed = false;
let nodeRows: RelayerAssignment[] = [];
let nodeError: { code: string } | null = null;
const nodeReads: unknown[] = [];
const providerAssignments: unknown[][] = [];
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
        if (name === "hyn_node_relayer") {
          nodeReads.push(params);
          return { data: nodeAllowed ? nodeRows : null, error: nodeError ?? (nodeAllowed ? null : { code: "42501" }) };
        }
        if (name === "hyn_can_view_dashboard") {
          checks.push(params);
          return { data: allowed, error: null };
        }
        return {
          data:
            name === "hyn_is_active"
              ? active
              : name === "hyn_is_admin"
                ? canAdmin
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
    readAssignedRelayers: async (assignments: unknown[]) => {
      providerReads++;
      providerAssignments.push(assignments);
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

test("all-relayer view is restricted to admins and never filters owner to the literal all", async () => {
  reads.length = 0;
  providerReads = 0;
  assert.equal((await get("all")).status,403);
  assert.equal(providerReads,0);
  canAdmin = true;
  assert.equal((await get("all")).status,200);
  assert.deepEqual(reads,[]);
  assert.equal(providerReads,1);
  canAdmin = false;
});

test("server scope loads only its explicit link and respects server access independently of account access", async () => {
  const nodeId = "20000000-0000-4000-8000-000000000001";
  const getNode = (query = `node=${nodeId}`) => route.then(module => module.GET(new Request(`https://portal.example/api/relayers?${query}`)));
  nodeReads.length = 0;
  providerReads = 0;
  assert.equal((await getNode("node=invalid")).status, 400);
  assert.equal(nodeReads.length, 0);
  assert.equal((await getNode()).status, 404);
  assert.equal(providerReads, 0);
  nodeAllowed = true;
  try {
    nodeRows = [];
    assert.deepEqual(await (await getNode()).json(), { readings: [], error: null });
    assert.equal(providerReads, 0);
    nodeRows = [{ id: "assignment", owner: "server-owner", relayer_id: 457, relayer_name: "This server's relay", created_at: "2026-09-11T08:00:00Z" }];
    reads.length = 0;
    checks.length = 0;
    const response = await getNode(`node=${nodeId}&owner=another-owner&relayer=999`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get("cache-control")!, /private, no-store/);
    assert.deepEqual(nodeReads.at(-1), { p_node: nodeId });
    assert.deepEqual(providerAssignments.at(-1), nodeRows);
    assert.deepEqual(reads, []);
    assert.deepEqual(checks, []);
    assert.equal(providerReads, 1);
    nodeError = { code: "42883" };
    assert.equal((await getNode()).status, 503);
    assert.equal(providerReads, 1);
  } finally {
    nodeAllowed = false;
    nodeRows = [];
    nodeError = null;
  }
});
