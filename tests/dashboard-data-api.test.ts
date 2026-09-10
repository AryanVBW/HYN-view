import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { renderToStaticMarkup } from "react-dom/server";

let role: unknown = "monitor";
let status = "active";
let signedIn = true;
let profileError = false;
let reportError = false;
let throws = false;
const calls: { name: string; args: unknown }[] = [];
mock.module("next/navigation", { namedExports: { redirect: (path: string) => { throw new Error(`redirect:${path}`); } } });
mock.module("../lib/supabase/server.ts", {
  namedExports: {
    createClient: async () => {
      if (throws) throw new Error("Offline");
      return {
        auth: { getUser: async () => ({data: {user: signedIn ? {id: "account"} : null}}) },
        from: (table: string) => {
          assert.equal(table, "profiles", "legacy usage route must not load fleet data");
          const query = {
            select: () => query, eq: () => query,
            maybeSingle: async () => ({data: {role, status}, error: profileError ? {message: "Unavailable"} : null}),
          };
          return query;
        },
        rpc: async (name: string, args: unknown) => {
          calls.push({name, args});
          return {data: {sampled_at: "2026-09-11T08:00:00Z", since: "2026-09-01", iface: "eth0", ingress_bytes: "1024", egress_bytes: "2048", days: []}, error: reportError ? {message: "Access changed"} : null};
        },
      };
    },
  },
});
const usage = import("../app/usage/page");
const bandwidth = import("../components/dashboard/server-bandwidth");

test("old usage bookmarks route only active administrators into reports", async () => {
  const {default: page} = await usage;
  for (role of ["viewer", "monitor", "admin", "super_admin", "unknown", null]) {
    const expected = role === "admin" || role === "super_admin" ? "/admin?tab=bandwidth" : "/dashboard";
    await assert.rejects(page(), {message: `redirect:${expected}`});
  }
  role = "super_admin";
  status = "suspended";
  await assert.rejects(page(), {message: "redirect:/dashboard"});
  status = "active";
  profileError = true;
  await assert.rejects(page(), {message: "redirect:/dashboard"});
  profileError = false;
  signedIn = false;
  await assert.rejects(page(), {message: "redirect:/signin?next=%2Fusage"});
  signedIn = true;
});

test("user counters read only the selected server and degrade cleanly on access or connection failure", async () => {
  const {ServerBandwidth} = await bandwidth;
  const html = renderToStaticMarkup(await ServerBandwidth({nodeId: "shared-server"}));
  assert.deepEqual(calls, [{name: "hyn_bandwidth_report", args: {p_node: "shared-server", p_days: 7}}]);
  assert.match(html, /3\.00 KiB/);
  reportError = true;
  const unavailable = renderToStaticMarkup(await ServerBandwidth({nodeId: "shared-server"}));
  assert.match(unavailable, /temporarily unavailable/);
  assert.doesNotMatch(unavailable, /KiB/);
  reportError = false;
  throws = true;
  const offline = renderToStaticMarkup(await ServerBandwidth({nodeId: "shared-server"}));
  assert.match(offline, /temporarily unavailable/);
  throws = false;
});
