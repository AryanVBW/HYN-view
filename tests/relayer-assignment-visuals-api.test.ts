import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { mock, test } from "node:test";
import { act, createElement } from "react";
import { JSDOM } from "jsdom";
import type { NodeRelayerLink, RelayerAssignment, RelayerDashboardData } from "../lib/relayer";

registerHooks({ load(url, context, nextLoad) {
  if (url.endsWith(".css")) return { format: "module", source: "export default {};", shortCircuit: true };
  return nextLoad(url, context);
} });
const ownerId = "10000000-0000-4000-8000-000000000001";
const saved: RelayerAssignment = {
  id: "30000000-0000-4000-8000-000000000001", owner: ownerId,
  relayer_id: 456, relayer_name: "Existing gateway", created_at: "2026-09-11T00:00:00Z",
};
const fleet = [
  { id: 456, name: "Existing gateway", city: "Delhi", tier: "Standard" },
  { id: 457, name: "North gateway", city: "Mumbai", tier: "Standard" },
  { id: 458, name: "South gateway", city: "Pune", tier: "Standard" },
];
const assigned: { owner: string; relayer: number }[] = [];
const removed: string[] = [];
let failingId: number | null = null;
let throwingId: number | null = null;
let removalError = false;
let params = new URLSearchParams();
mock.module("next/navigation", { namedExports: {
  usePathname: () => "/dashboard", useSearchParams: () => params,
  useRouter: () => ({ refresh() {}, push() {}, replace() {} }),
} });
mock.module("../app/admin/relayer-actions.ts", { namedExports: {
  assignRelayer: async (owner: string, relayer: number) => {
    assigned.push({ owner, relayer });
    if (relayer === throwingId) throw new Error("Connection interrupted");
    return relayer === failingId ? { ok: false, error: "Assignment rejected" } : { ok: true };
  },
  removeRelayer: async (id: string) => {
    removed.push(id);
    return removalError ? { ok: false, error: "Removal rejected" } : { ok: true };
  },
} });

async function setup() {
  assigned.length = 0;
  removed.length = 0;
  failingId = null;
  throwingId = null;
  removalError = false;
  params = new URLSearchParams();
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/admin?tab=access" });
  Object.assign(globalThis, { window: dom.window, self: dom.window, document: dom.window.document, FormData: dom.window.FormData, IS_REACT_ACT_ENVIRONMENT: true });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async input => {
    const url = new URL(String(input), "https://portal.example");
    assert.equal(url.pathname, "/api/admin/relayers", "the embedded assignment panel must not poll relay readings");
    const query = (url.searchParams.get("q") ?? "").toLowerCase();
    return new Response(JSON.stringify({ relayers: fleet.filter(item => item.name.toLowerCase().includes(query)) }), { status: 200 });
  };
  const { createRoot } = await import("react-dom/client");
  const { RelayerManager } = await import("../components/admin/relayer-manager");
  const root = createRoot(document.getElementById("root")!);
  const props = {
    ownerId, ownerName: "Alice", assignments: [saved], error: null, showReadings: false,
    links: [{ node_id: "server", assignment_id: saved.id }] as NodeRelayerLink[] | undefined,
    nodes: [{ id: "server", name: "Office computer" }],
  };
  const render = (overrides: Partial<typeof props> = {}) => act(async () => root.render(createElement(RelayerManager, { ...props, ...overrides })));
  const button = (text: string) => {
    const target = [...document.querySelectorAll("button")].find(element => element.textContent?.trim() === text);
    assert.ok(target, `Expected button: ${text}`);
    return target;
  };
  const click = (element: HTMLElement) => act(async () => element.click());
  const search = async (value: string) => {
    const input = document.querySelector<HTMLInputElement>('input[aria-label="Search Highway relayers"]')!;
    const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, "value")!.set!;
    await act(async () => {
      setter.call(input, value);
      input.dispatchEvent(new dom.window.Event("input", { bubbles: true }));
    });
    await act(async () => { await new Promise(resolve => setTimeout(resolve, 350)); });
  };
  const choose = (name: string) => {
    const target = document.querySelector<HTMLButtonElement>(`button[aria-label="Select relay: ${name}"]`);
    assert.ok(target, `Expected search result: ${name}`);
    return click(target);
  };
  const close = async () => {
    await act(async () => root.unmount());
    globalThis.fetch = originalFetch;
    dom.window.close();
  };
  return { root, dom, render, button, click, search, choose, close };
}

test("admin selects multiple relays across searches, skips existing assignments and assigns only the selected user's relays", async () => {
  const view = await setup();
  try {
    await view.render();
    assert.deepEqual([...document.querySelectorAll(".relay-assignment-totals dd")].map(item => item.textContent), ["1", "1", "0"]);
    assert.match(document.querySelector(".relay-access-list")!.textContent!, /Also below Running on Office computer/);
    assert.equal(document.querySelector(".relay-access-actions a")?.getAttribute("href"), "/admin?tab=relayers&relayer=456");
    await view.search("Existing");
    assert.equal(document.querySelector<HTMLButtonElement>('button[aria-label="Already assigned: Existing gateway"]')!.disabled, true);
    await view.search("North");
    await view.choose("North gateway");
    await view.search("South");
    await view.choose("South gateway");
    const tray = document.querySelector('[aria-label="Relays selected to assign"]')!;
    assert.match(tray.textContent!, /North gateway/);
    assert.match(tray.textContent!, /South gateway/);
    assert.match(tray.textContent!, /2 selected, not yet assigned/);
    assert.equal(document.querySelectorAll(".relay-access-row").length, 1, "pending selection must not be shown as saved access");
    await view.click(view.button("Assign 2 relays"));
    assert.deepEqual(assigned, [{ owner: ownerId, relayer: 457 }, { owner: ownerId, relayer: 458 }]);
    assert.equal(document.querySelector('[aria-label="Relays selected to assign"]'), null);
    assert.match(document.querySelector(".relayer-assignment-message")!.textContent!, /2 relays assigned to Alice/);
    await view.render({ assignments: [saved, ...fleet.slice(1).map(item => ({ ...saved, id: `assignment-${item.id}`, relayer_id: item.id, relayer_name: item.name }))] });
    assert.deepEqual([...document.querySelectorAll(".relay-assignment-totals dd")].map(item => item.textContent), ["3", "1", "2"]);
    assert.equal(document.querySelectorAll(".relay-access-actions a").length, 3);
    assert.equal(document.querySelectorAll(".relay-access-note").length, 2);
  } finally { await view.close(); }
});

test("partial assignment failure keeps only failed relays selected and reports an interrupted retry without losing selection", async () => {
  const view = await setup();
  try {
    await view.render();
    await view.search("gateway");
    await view.choose("North gateway");
    await view.choose("South gateway");
    failingId = 458;
    await view.click(view.button("Assign 2 relays"));
    assert.match(document.querySelector('[role="alert"]')!.textContent!, /South gateway: Assignment rejected/);
    const selection = () => document.querySelector('[aria-label="Relays selected to assign"]')!.textContent!;
    assert.match(selection(), /South gateway/);
    assert.doesNotMatch(selection(), /North gateway/);
    assert.match(document.querySelector(".relayer-assignment-message")!.textContent!, /1 relay assigned to Alice/);
    failingId = null;
    throwingId = 458;
    await view.click(view.button("Assign 1 relay"));
    assert.match(document.querySelector('[role="alert"]')!.textContent!, /Could not confirm the assignment/);
    assert.match(selection(), /South gateway/);
    throwingId = null;
    await view.click(view.button("Assign 1 relay"));
    assert.deepEqual(assigned.map(call => call.relayer), [457, 458, 458, 458]);
    assert.equal(document.querySelector('[aria-label="Relays selected to assign"]'), null);
    assert.equal(document.querySelector('[role="alert"]'), null);
  } finally { await view.close(); }
});

test("removing an assigned relay requires confirmation, explains the server link and retains failures", async () => {
  const view = await setup();
  try {
    await view.render();
    await view.click(view.button("Remove"));
    assert.deepEqual(removed, []);
    assert.match(document.querySelector('[role="group"]')!.textContent!, /also removes its link below Running on Office computer/);
    await view.click(view.button("Cancel"));
    assert.deepEqual(removed, []);
    assert.equal(document.querySelector('[role="group"]'), null);
    await view.click(view.button("Remove"));
    removalError = true;
    await view.click(view.button("Confirm removal"));
    assert.match(document.querySelector('[role="alert"]')!.textContent!, /Removal rejected/);
    assert.ok(document.querySelector('[role="group"]'));
    removalError = false;
    await view.click(view.button("Confirm removal"));
    assert.deepEqual(removed, [saved.id, saved.id]);
    assert.match(document.querySelector(".relayer-assignment-message")!.textContent!, /Other users' assignments have not changed/);
    await view.render({ links: undefined });
    assert.deepEqual([...document.querySelectorAll(".relay-assignment-totals dd")].map(item => item.textContent), ["1", "Unknown", "Unknown"]);
    assert.match(document.querySelector(".relay-access-list")!.textContent!, /Server link information is unavailable/);
  } finally { await view.close(); }
});

test("user relay cards preserve the complete assigned list and clear unrelated server and owner scopes from relay links", async () => {
  const view = await setup();
  try {
    params = new URLSearchParams("section=relayers&node=shared-server&relayScope=server&owner=someone-else&relayer=457");
    const reads: string[] = [];
    const dashboard: RelayerDashboardData = { error: null, readings: fleet.slice(1).map(item => ({
      assignment: { ...saved, id: `assignment-${item.id}`, relayer_id: item.id, relayer_name: item.name },
      relayer: null, chain: null, sourceAt: null, fetchedAt: null, providerLatencyMs: null, error: null, chainError: null,
    })) };
    globalThis.fetch = async input => {
      reads.push(String(input));
      return new Response(JSON.stringify(dashboard), { status: 200 });
    };
    const { RelayerDashboard } = await import("../components/dashboard/relayer-dashboard");
    await act(async () => view.root.render(createElement(RelayerDashboard)));
    assert.deepEqual(reads, ["/api/relayers?relayer=457"]);
    const cards = () => [...document.querySelectorAll<HTMLAnchorElement>('[aria-label="Assigned relay directory"] li a')];
    assert.equal(cards().length, 2);
    assert.equal(cards()[1].getAttribute("href"), "/dashboard?section=relayers&relayer=458");
    params = new URLSearchParams("section=relayers&relayer=458");
    await act(async () => view.root.render(createElement(RelayerDashboard)));
    assert.equal(cards().length, 2);
    assert.equal(reads.at(-1), "/api/relayers?relayer=458");
    assert.equal(document.querySelector('[aria-current="page"]')?.getAttribute("href"), "/dashboard?section=relayers&relayer=458");
  } finally { await view.close(); }
});
