import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";
import { JSDOM } from "jsdom";
import type { RelayerAssignment } from "../lib/relayer";

let signedIn = true;
let superAdmin = true;
let databaseError: string | null = null;
let refreshes = 0;
const writes: unknown[] = [];
const revalidated: string[] = [];
const nodeId = "20000000-0000-4000-8000-000000000001";
const otherNode = "20000000-0000-4000-8000-000000000002";
const assignments: RelayerAssignment[] = [1, 2, 3].map(value => ({
  id: `30000000-0000-4000-8000-00000000000${value}`,
  owner: "account", relayer_id: 456 + value, relayer_name: `Relay ${value}`, created_at: "2026-09-11T08:00:00Z",
}));
mock.module("next/cache", { namedExports: { revalidatePath: (path: string) => revalidated.push(path) } });
mock.module("next/navigation", { namedExports: { useRouter: () => ({ refresh: () => refreshes++ }) } });
mock.module("../lib/supabase/server.ts", { namedExports: {
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: signedIn ? { id: "actor" } : null } }) },
    rpc: async (name: string, params: unknown) => {
      if (name === "hyn_is_super_admin") return { data: superAdmin, error: null };
      assert.equal(name, "hyn_admin_set_node_relayer");
      writes.push(params);
      return { data: null, error: databaseError ? { message: databaseError } : null };
    },
  }),
} });
mock.module("../lib/relayer-provider.ts", { namedExports: {
  fetchFleet: async () => { throw new Error("Existing assignments must not require a provider fetch to link."); },
} });
const actions = import("../app/admin/relayer-actions");

test("link actions require a Super admin, validate identifiers and propagate database conflicts", async () => {
  const { setNodeRelayer } = await actions;
  writes.length = 0;
  revalidated.length = 0;
  assert.equal((await setNodeRelayer("invalid", assignments[0].id)).ok, false);
  assert.equal((await setNodeRelayer(nodeId, "invalid")).ok, false);
  signedIn = false;
  assert.equal((await setNodeRelayer(nodeId, assignments[0].id)).ok, false);
  signedIn = true;
  superAdmin = false;
  assert.equal((await setNodeRelayer(nodeId, assignments[0].id)).ok, false);
  superAdmin = true;
  assert.equal(writes.length, 0);
  assert.deepEqual(await setNodeRelayer(nodeId, assignments[0].id), { ok: true });
  assert.deepEqual(writes.at(-1), { p_node_id: nodeId, p_assignment_id: assignments[0].id });
  assert.deepEqual(revalidated, ["/admin", "/dashboard"]);
  assert.equal((await setNodeRelayer(nodeId, null)).ok, true);
  assert.deepEqual(writes.at(-1), { p_node_id: nodeId, p_assignment_id: null });
  revalidated.length = 0;
  databaseError = "This relayer is linked to another server. Unlink it there first";
  assert.deepEqual(await setNodeRelayer(nodeId, assignments[1].id), { ok: false, error: databaseError });
  assert.deepEqual(revalidated, []);
  databaseError = null;
});

test("server setting labels occupied relayers, saves an explicit link, unlinks and displays save errors", async () => {
  const { NodeRelayerSetting } = await import("../components/admin/node-relayer-setting");
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/admin" });
  Object.assign(globalThis, { window: dom.window, document: dom.window.document, FormData: dom.window.FormData, IS_REACT_ACT_ENVIRONMENT: true });
  const root = createRoot(document.getElementById("root")!);
  const props = {
    nodeId, nodeName: "Gateway", assignments, canWrite: true,
    nodes: [{ id: nodeId, name: "Gateway" }, { id: otherNode, name: "Backup server" }],
    links: [{ node_id: nodeId, assignment_id: assignments[0].id }, { node_id: otherNode, assignment_id: assignments[1].id }],
  };
  const choose = async (value: string) => act(async () => {
    const select = document.querySelector("select")!;
    select.value = value;
    select.dispatchEvent(new dom.window.Event("change", { bubbles: true }));
  });
  const submit = async () => act(async () => {
    document.querySelector("form")!.dispatchEvent(new dom.window.Event("submit", { bubbles: true, cancelable: true }));
  });
  try {
    await act(async () => root.render(createElement(NodeRelayerSetting, props)));
    assert.equal(document.querySelector("select")!.value, assignments[0].id);
    const occupied = document.querySelector(`option[value="${assignments[1].id}"]`) as HTMLOptionElement;
    assert.equal(occupied.disabled, true);
    assert.match(occupied.textContent!, /linked to Backup server/);
    await choose(assignments[2].id);
    await submit();
    assert.deepEqual(writes.at(-1), { p_node_id: nodeId, p_assignment_id: assignments[2].id });
    assert.match(document.body.textContent!, /Relayer linked to Gateway/);
    assert.equal(refreshes, 1);
    await choose("");
    await submit();
    assert.deepEqual(writes.at(-1), { p_node_id: nodeId, p_assignment_id: null });
    assert.match(document.body.textContent!, /Relayer unlinked from Gateway/);
    databaseError = "Relayer assignment no longer exists";
    await choose(assignments[0].id);
    await submit();
    assert.match(document.querySelector('[role="alert"]')!.textContent!, /no longer exists/);
    assert.equal(refreshes, 2);
    await act(async () => root.render(createElement(NodeRelayerSetting, { ...props, canWrite: false })));
    assert.equal(document.querySelector("select")!.disabled, true);
    assert.equal(document.querySelector("button"), null);
  } finally {
    databaseError = null;
    await act(async () => root.unmount());
    dom.window.close();
  }
});
