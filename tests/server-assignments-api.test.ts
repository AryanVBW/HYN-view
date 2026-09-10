import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";
import { JSDOM } from "jsdom";
import type { AdminClient, AdminNode } from "../lib/types";
let failure: string | null = null;
const calls: { name: string; params: unknown }[] = [];
mock.module("next/navigation", { namedExports: { useRouter: () => ({ refresh() {} }) } });
mock.module("../lib/supabase/client.ts", { namedExports: {
  createClient: () => ({ rpc: async (name: string, params: unknown) => {
    calls.push({ name, params });
    return { data: null, error: failure ? { message: failure } : null };
  } }),
} });
const clients = [
  { id: "alice", full_name: "Alice", email: "alice@example.test", status: "active", role: "viewer" },
  { id: "bob", full_name: "Bob", email: "bob@example.test", status: "active", role: "monitor" },
  { id: "owner", full_name: "Owner", email: "owner@example.test", status: "active", role: "monitor" },
] as AdminClient[];
const nodes = [
  { id: "primary", name: "Primary", hostname: "primary-host", owner_id: "owner", owner_status: "active", revoked: false, is_demo: false },
  { id: "backup", name: "Backup", hostname: "backup-host", owner_id: "owner", owner_status: "active", revoked: false, is_demo: false },
  { id: "owned", name: "Own device", hostname: "own-host", owner_id: "alice", owner_status: "active", revoked: false, is_demo: false },
] as AdminNode[];

test("visual assignments save multiple servers for one user while retaining other users and owner access", async () => {
  const { ServerAccess } = await import("../components/admin/server-access");
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/admin?tab=access" });
  Object.assign(globalThis, { window: dom.window, self: dom.window, document: dom.window.document, FormData: dom.window.FormData, IS_REACT_ACT_ENVIRONMENT: true });
  const root = createRoot(document.getElementById("root")!);
  const button = (text: string) => [...document.querySelectorAll("button")].find(element => element.textContent?.includes(text))!;
  const checkbox = (text: string) => [...document.querySelectorAll<HTMLInputElement>('input[type="checkbox"]')].find(element => element.closest("label")?.textContent?.includes(text))!;
  const click = (element: HTMLElement) => act(async () => element.click());
  try {
    await act(async () => root.render(createElement(ServerAccess, {
      clients, nodes, events: [],
      grants: [{ viewer_id: "alice", node_id: "primary", allowed: true, notifications_allowed: false }, { viewer_id: "bob", node_id: "primary", allowed: true }],
    })));
    assert.equal(checkbox("Primary").checked, true);
    assert.equal(checkbox("Backup").checked, false);
    assert.equal(checkbox("Own device").checked, true);
    assert.equal(checkbox("Own device").disabled, true);
    await click(checkbox("Backup"));
    assert.match(document.body.textContent!, /3 servers selected/);
    assert.equal(button("Bob").disabled, true);
    await click(button("Alice"));
    assert.equal(button("Bob").disabled, true);
    await click(button("Save assignments"));
    assert.deepEqual(calls.at(-1), { name: "hyn_admin_set_user_servers", params: { p_viewer: "alice", p_nodes: ["primary", "backup"] } });
    assert.match(document.body.textContent!, /Alice can view 3 servers/);
    assert.equal(button("Bob").disabled, false);
    await click(button("Bob"));
    assert.equal(checkbox("Primary").checked, true);
    assert.equal(checkbox("Backup").checked, false);
    assert.equal(checkbox("Own device").checked, false);
    assert.match(document.body.textContent!, /1 server selected/);
    await click(checkbox("Backup"));
    failure = "Server is no longer available";
    await click(button("Save assignments"));
    assert.match(document.querySelector('[role="alert"]')!.textContent!, /no longer available/);
    assert.equal(checkbox("Backup").checked, true);
    await click(button("Discard changes"));
    assert.equal(checkbox("Backup").checked, false);
    assert.equal(button("Alice").disabled, false);
    failure = null;
    await click(button("Clear selection"));
    await click(button("Save assignments"));
    assert.deepEqual(calls.at(-1), { name: "hyn_admin_set_user_servers", params: { p_viewer: "bob", p_nodes: [] } });
    assert.match(document.body.textContent!, /Bob can view 0 servers/);
  } finally {
    failure = null;
    await act(async () => root.unmount());
    dom.window.close();
  }
});
