import assert from "node:assert/strict";
import test from "node:test";
import { JSDOM } from "jsdom";
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
  assert.doesNotMatch(html, /your workspace|>Viewer</);
  assert.doesNotMatch(html, /Admin dashboard|Link another server/);
});

test("Monitors can link devices and staff get all-server navigation", () => {
  for (const role of ["viewer","monitor","admin","super_admin"]) {
    const html=render(<DashboardContext role={role} owner="me" accounts={[{id:"me",name:"Owner",own:true}]}/>);
    assert.equal(html.includes("+ Link server"),permissions(role).canLink,role);
    assert.equal(html.includes("All servers"),permissions(role).canAdmin,role);
    assert.equal(html.includes("My devices"), permissions(role).canAdmin, role);
    assert.match(html,/aria-current="page"/);
  }
});

test("dashboard navigation keeps the selected server and hides relayers for server-only shares", () => {
  const accounts = [{id: "shared", name: "Shared account", own: false}];
  const html = render(<DashboardContext role="monitor" owner="shared" accounts={accounts} nodeId="server" section="relayers" />);
  assert.match(html, /href="\/dashboard\?owner=shared&amp;node=server"/);
  const document = new JSDOM(html).window.document;
  assert.equal(document.querySelector('nav [aria-current="page"]')?.getAttribute("href"), "/dashboard?owner=shared&node=server&section=relayers&relayScope=server");
  assert.doesNotMatch(html, /your workspace|Overall data usage|Request a relayer|Connect a Highway relayer|>Monitor</);
  const shared = render(<DashboardContext role="viewer" owner="shared" accounts={accounts} canViewRelayers={false} />);
  assert.doesNotMatch(shared, />Relayers<|Link server/);
  assert.match(shared, />Servers<|Shared account/);
});

test("both dashboard sections select computers by name without account labels", () => {
  const accounts = [
    {id: "me", name: "My devices", own: true},
    {id: "shared", name: "Shared dashboard 0daec582", own: false},
    {id: "unlisted", name: "Demo Account", own: false},
  ];
  const computers = [
    {id: "office", owner: "me", hostname: "office-pc", name: "Office computer"},
    {id: "relay", owner: "shared", hostname: null, name: "Relay tower"},
  ];
  for (const role of ["viewer", "monitor", "admin", "super_admin"]) {
    for (const section of ["servers", "relayers"] as const) {
      const html = render(<DashboardContext role={role} owner="shared" nodeId="relay" accounts={accounts} computers={computers} section={section} />);
      const dom = new JSDOM(html);
      try {
        const document = dom.window.document;
        const links = Array.from(document.querySelectorAll('nav[aria-label="Computers"] a'));
        assert.equal(links.length, 2);
        assert.equal(links[0].querySelector("span")?.textContent, "office-pc");
        assert.equal(links[1].querySelector("span")?.textContent, "Relay tower");
        assert.equal(links[1].getAttribute("aria-current"), "page");
        assert.ok(document.querySelector('input[aria-label="Search computers"]'));
        assert.equal(document.querySelector('nav[aria-label="Dashboards"]'), null);
        assert.doesNotMatch(document.body.textContent ?? "", /All servers|My devices|Demo Account|Shared dashboard/);
        for (const [index, link] of links.entries()) {
          const url = new URL(link.getAttribute("href")!, "https://portal.example.test");
          assert.equal(url.searchParams.get("node"), computers[index].id);
          assert.equal(url.searchParams.get("owner"), computers[index].owner);
          assert.equal(url.searchParams.get("section"), section);
          assert.equal(url.searchParams.get("relayScope"), section === "relayers" ? "server" : null);
        }
      } finally {
        dom.window.close();
      }
    }
  }
});

test("compact reading refresh never includes update or configuration controls", () => {
  for (const role of ["viewer", "monitor", "admin", "super_admin"]) {
    const access = permissions(role);
    const html = render(<AgentUpdateControl compact nodeId="server" nodeName="Server" currentVersion="1.11.0" release={{available: true, latest: "1.12.0", checkedAt: null}} automatic {...access} />);
    assert.equal(html.includes("Refresh reading"), access.canSync, role);
    assert.doesNotMatch(html, /synchronized machine controls|Update to hyn|Automatic updates|CLI/);
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
