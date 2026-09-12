import assert from "node:assert/strict";
import test from "node:test";
import { JSDOM } from "jsdom";
import { renderToStaticMarkup } from "react-dom/server";
import { DashboardContext } from "../components/dashboard/dashboard-context";
import { DashboardNavigation } from "../components/dashboard/dashboard-navigation";

const sections = ["servers", "relayers", "notifications"] as const;
const destinations = ["/dashboard", "/dashboard?section=relayers", "/notifications"];
const labels = ["Servers", "Relayers", "Notifications"];

function inspect(child: React.ReactNode, check: (nav: HTMLElement) => void) {
  const dom = new JSDOM(renderToStaticMarkup(child));
  try {
    const nav = dom.window.document.querySelector<HTMLElement>('nav[aria-label="Dashboard sections"]');
    assert.ok(nav, "dashboard sections must have a named navigation landmark");
    check(nav);
  } finally {
    dom.window.close();
  }
}

test("dashboard navigation exposes every section and marks only the current page", () => {
  for (const [index, section] of sections.entries()) {
    inspect(<DashboardNavigation section={section} />, (nav) => {
      const links = Array.from(nav.querySelectorAll("a"));
      assert.deepEqual(links.map(link => link.textContent?.trim()), labels);
      assert.deepEqual(links.map(link => link.getAttribute("href")), destinations);
      const current = nav.querySelectorAll('[aria-current="page"]');
      assert.equal(current.length, 1, section);
      assert.equal(current[0], links[index], section);
    });
  }
});

test("explicit server destinations retain their context without scoping the Relayers page", () => {
  const serverHref = "/dashboard?owner=shared%20team&node=server-2";
  inspect(<DashboardNavigation section="relayers" serverHref={serverHref} />, (nav) => {
    assert.deepEqual(
      Array.from(nav.querySelectorAll("a"), link => link.getAttribute("href")),
      [serverHref, destinations[1], destinations[2]],
    );
  });
});

test("dashboard context carries the selected owner and server into section navigation", () => {
  inspect(<DashboardContext
    role="viewer"
    owner="shared team"
    nodeId="server-2"
    section="relayers"
    accounts={[{ id: "shared team", name: "Shared account", own: false }]}
  />, (nav) => {
    const links = nav.querySelectorAll("a");
    const servers = new URL(links[0].getAttribute("href")!, "https://portal.example.test");
    assert.equal(servers.pathname, "/dashboard");
    assert.equal(servers.searchParams.get("owner"), "shared team");
    assert.equal(servers.searchParams.get("node"), "server-2");
    assert.equal(links[1].getAttribute("href"), destinations[1]);
    assert.equal(links[1].getAttribute("aria-current"), "page");
    assert.equal(links[2].getAttribute("href"), destinations[2]);
  });
});

test("server-only access omits Relayers while keeping the visible page selected", () => {
  for (const section of ["servers", "notifications"] as const) {
    inspect(<DashboardNavigation section={section} canViewRelayers={false} />, (nav) => {
      const links = Array.from(nav.querySelectorAll("a"));
      assert.deepEqual(links.map(link => link.textContent?.trim()), ["Servers", "Notifications"]);
      assert.deepEqual(links.map(link => link.getAttribute("href")), [destinations[0], destinations[2]]);
      assert.equal(nav.querySelectorAll('[aria-current="page"]').length, 1);
      assert.equal(nav.querySelector('[aria-current="page"]')?.getAttribute("href"), section === "servers" ? destinations[0] : destinations[2]);
    });
  }
});

test("section links retain native keyboard focus and decorative icons do not alter their labels", () => {
  inspect(<DashboardNavigation section="servers" />, (nav) => {
    const links = Array.from(nav.querySelectorAll("a"));
    assert.equal(links.length, 3);
    for (const [index, link] of links.entries()) {
      assert.equal(link.tabIndex, 0, `${labels[index]} must stay in the native Tab order`);
      assert.ok(link.hasAttribute("href"));
      assert.equal(link.hasAttribute("role"), false, "page links must retain their native link role");
      assert.equal(link.textContent?.trim(), labels[index]);
      const icons = link.querySelectorAll("svg");
      assert.ok(icons.length > 0, `${labels[index]} should have a decorative icon`);
      for (const icon of icons) assert.equal(icon.getAttribute("aria-hidden"), "true");
      link.focus();
      assert.equal(nav.ownerDocument.activeElement, link);
    }
  });
});
