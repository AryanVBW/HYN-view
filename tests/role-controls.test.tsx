import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime.js";
import { AgentUpdateControl } from "../components/dashboard/agent-update-control";
import { ClientTable } from "../components/admin/tables";
import { SearchParamsContext } from "next/dist/shared/lib/hooks-client-context.shared-runtime.js";
import { ServerSwitcher } from "../components/dashboard/server-switcher";
import { DashboardContext } from "../components/dashboard/dashboard-context";
import { permissions } from "../lib/permissions";
import type { AdminClient } from "../lib/types";

const router = {
  back() {},
  forward() {},
  refresh() {},
  hmrRefresh() {},
  push() {},
  replace() {},
  prefetch() {},
};
const render = (child: React.ReactNode) =>
  renderToStaticMarkup(
    <AppRouterContext.Provider value={router}>
      {child}
    </AppRouterContext.Provider>,
  );
const client: AdminClient = {
  id: "someone-else",
  email: "monitor@example.com",
  full_name: "Monitor account",
  role: "monitor",
  status: "active",
  suspended_reason: null,
  created_at: "2026-09-09T00:00:00Z",
  nodes: 1,
  nodes_active: 1,
  nodes_unlinked: 0,
  notifications_30d: 0,
  notifications_failed_30d: 0,
  last_seen_at: null,
};
test("role controls expose sync to Monitors and updates only to Super admins", () => {
  for (const role of ["viewer", "monitor", "admin", "super_admin"]) {
    const access = permissions(role);
    const html = render(
      <AgentUpdateControl
        nodeId="machine"
        nodeName="Server"
        currentVersion="1.10.0"
        release={{ available: false, latest: null, checkedAt: null }}
        automatic={false}
        {...access}
      />,
    );
    assert.equal(html.includes("Sync now</button>"), access.canSync, role);
    assert.equal(
      html.includes("Check &amp; update CLI"),
      access.canWrite,
      role,
    );
    if (role === "viewer" || role === "admin") assert.equal(html, "");
  }
});
test("Admin account table permits promotion but hides suspension and role editing", () => {
  const html = render(<ClientTable clients={[client]} selfId="admin" />);
  assert.match(html, /Make Admin/);
  assert.doesNotMatch(html, /<select|>Suspend</);
  const superHtml = render(
    <ClientTable clients={[client]} selfId="super" canWrite />,
  );
  assert.match(superHtml, /Role for monitor@example.com/);
  assert.match(superHtml, />Suspend</);
  for (const label of ["Viewer", "Monitor", "Admin", "Super admin"])
    assert.ok(superHtml.includes(label));
});
test("Viewer dashboard selector contains only supplied accessible dashboards", () => {
  const html = render(
    <DashboardContext
      role="viewer"
      owner="shared"
      accounts={[{ id: "shared", name: "Shared with me", own: false }]}
    />,
  );
  assert.match(html, /Shared with me/);
  assert.match(html, /Viewer/);
  assert.doesNotMatch(html, /Admin dashboard|Link another server/);
});

test("Monitors can link devices and staff get all-server navigation", () => {
  for (const role of ["viewer","monitor","admin","super_admin"]) {
    const html=render(<DashboardContext role={role} owner="me" accounts={[{id:"me",name:"Owner",own:true}]}/>);
    assert.equal(html.includes("+ Link server"),permissions(role).canLink,role);
    assert.equal(html.includes("All servers"),permissions(role).canAdmin,role);
    assert.match(html,/My devices/);
    assert.match(html,/aria-current="page"/);
  }
});

test("server switching preserves scope and relayer while identifying the selected device", () => {
  const html=render(<SearchParamsContext.Provider value={new URLSearchParams("owner=all&node=first&relayer=42")}>
    <ServerSwitcher current="first" baseHref="/dashboard?owner=all" accounts={[{id:"me",name:"Owner",own:true},{id:"team",name:"Team",own:false}]} nodes={[
      {id:"first",name:"Gateway",hostname:"wan-01",owner:"me",is_demo:false,status:"active"},
      {id:"second",name:"Gateway",hostname:"wan-02",owner:"team",is_demo:false,status:"active"},
    ]}/>
  </SearchParamsContext.Provider>);
  assert.match(html,/href="\/dashboard\?owner=all&amp;node=second&amp;relayer=42"/);
  assert.match(html,/aria-current="page"[^>]*title="Gateway · Mine"/);
  assert.match(html,/Gateway · Team/);
});
