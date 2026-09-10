import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime.js";
import { BandwidthPanel } from "../components/admin/bandwidth-panel";
import { ServerAccess } from "../components/admin/server-access";
import { NodeSettings } from "../components/account/node-settings";
import type { AdminClient, AdminNode, Node } from "../lib/types";
const router = { back() {},forward() {},refresh() {},hmrRefresh() {},push() {},replace() {},prefetch() {} };
const clients = [
  {id:"monitor",role:"monitor",status:"active",full_name:"Monitor account"},
  {id:"suspended",role:"viewer",status:"suspended",full_name:"Suspended account"},
  {id:"admin",role:"admin",status:"active",full_name:"Staff account"},
] as AdminClient[];
const nodes = [{id:"server",name:"WAN server",owner_email:"owner@example.test",revoked:false,is_demo:false}] as AdminNode[];
test("bandwidth daily controls start behind collapsed Advanced view without fake usage",()=>{
  const html=renderToStaticMarkup(<BandwidthPanel nodes={nodes}/>);
  assert.match(html,/Advanced view · daily consumption/);
  assert.doesNotMatch(html,/<details[^>]*open/);
  assert.doesNotMatch(html,/0\.00 B/);
  assert.match(html,/All accessible servers/);
});
test("assignments show eligible users and visual server checkboxes",()=>{
  const html=renderToStaticMarkup(<AppRouterContext.Provider value={router}><ServerAccess clients={clients} nodes={nodes} grants={[]} events={[]}/></AppRouterContext.Provider>);
  assert.match(html,/Monitor account/);
  assert.doesNotMatch(html,/Suspended account|Staff account/);
  assert.match(html,/Save assignments/);
  assert.match(html,/WAN server/);
  assert.match(html,/Super admins only/);
  assert.doesNotMatch(html,/<select[^>]*multiple/);
  assert.match(html,/type="checkbox"/);
  assert.match(html,/Assigned only/);
  assert.match(html,/Find a user/);
});

test("shared settings show stored values without exposing save or editable controls", () => {
  const node: Node = {
    id: "server", owner: "owner", name: "WAN server", hostname: "wan-server",
    os: "Ubuntu", agent_version: "1.11.0", is_demo: false, revoked: false,
    created_at: "2026-09-10T10:00:00Z", last_seen_at: null, status: "active",
    paused_until: null, status_reason: null, last_config_pull_at: null,
    last_heartbeat_at: null, config: { auto_update: "check", alert_mem_pct: "80" },
  };
  const html = renderToStaticMarkup(<AppRouterContext.Provider value={router}><NodeSettings nodes={[node]} /></AppRouterContext.Provider>);
  assert.match(html,/Read-only settings/);
  assert.doesNotMatch(html,/Save settings/);
  const fields = html.match(/<(?:input|select)\b[^>]*>/g) ?? [];
  assert.ok(fields.length > 5);
  assert.ok(fields.every(field => /disabled/.test(field)));
  assert.match(html,/value="80"/);
});
