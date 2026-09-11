import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { act, createElement } from "react";
import { JSDOM } from "jsdom";
import { defaultRule, type DeliverySnapshot } from "../lib/delivery-controls";

let signedIn = true;
let superAdmin = true;
let databaseError: string | null = null;
const writes: { name: string; params: unknown }[] = [];
const navigations: string[] = [];
const owner = "d1000000-0000-4000-8000-000000000001";
mock.module("next/cache", { namedExports: { revalidatePath() {} } });
mock.module("next/navigation", { namedExports: { useRouter: () => ({ refresh() {}, push: (href: string) => navigations.push(href) }) } });
mock.module("../lib/supabase/server.ts", { namedExports: { createClient: async () => ({
  auth: { getUser: async () => ({ data: { user: signedIn ? { id: owner } : null } }) },
  rpc: async (name: string, params: unknown) => {
    if (name === "hyn_is_super_admin") return { data: superAdmin, error: null };
    writes.push({ name, params });
    return { data: null, error: databaseError ? { message: databaseError } : null };
  },
}) } });

test("delivery actions enforce super-admin access, limits and explicit global confirmation", async () => {
  const actions = await import("../app/admin/delivery-actions");
  writes.length = 0;
  assert.equal((await actions.saveDeliveryRules("invalid", [defaultRule("all")])).ok, false);
  assert.equal((await actions.saveDeliveryRules(owner, [{ ...defaultRule("all"), daily_limit: -1 }])).ok, false);
  assert.equal((await actions.saveDailyDigest(null, true, "08:00", "UTC")).ok, false);
  signedIn = false;
  assert.equal((await actions.saveDeliveryRules(owner, [defaultRule("all")])).ok, false);
  signedIn = true; superAdmin = false;
  assert.equal((await actions.saveDailyDigest(owner, true, "08:00", "UTC")).ok, false);
  assert.equal((await actions.stopDelivery(owner)).ok, false);
  superAdmin = true;
  assert.equal(writes.length, 0);
  assert.deepEqual(await actions.saveDailyDigest(null, true, "08:00", "Asia/Kolkata", false, true), { ok: true });
  assert.deepEqual(writes.at(-1), { name: "hyn_admin_set_digest", params: { p_owner: null, p_enabled: true, p_at: "08:00", p_timezone: "Asia/Kolkata", p_inherit: false, p_confirm_all: true } });
  assert.deepEqual(await actions.saveDailyDigest(owner, false, "08:00", "UTC", true), { ok: true });
  databaseError = "Selected user is inactive";
  assert.deepEqual(await actions.saveDeliveryRules(owner, [defaultRule("all")]), { ok: false, error: databaseError });
  databaseError = null;
  assert.ok(writes.every(call => call.name.startsWith("hyn_admin_")), "settings do not invoke a sender");
});

test("delivery dashboard names users, keeps combined email off, confirms global changes and retains attempts", async () => {
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/admin/deliveries" });
  Object.assign(globalThis, { window: dom.window, self: dom.window, document: dom.window.document, IS_REACT_ACT_ENVIRONMENT: true });
  const { createRoot } = await import("react-dom/client");
  const { DeliveryDashboard } = await import("../components/admin/delivery-dashboard");
  const root = createRoot(document.getElementById("root")!);
  const now = "2026-09-11T10:00:00Z";
  const snapshot: DeliverySnapshot = {
    as_of: now, started_at: now, day_start: "2026-09-11T00:00:00Z", rules: [{ ...defaultRule("all"), scope: "global", owner: null, daily_limit: 100 }],
    digest_settings: [{ scope: "global", owner: null, configured: false, enabled: false, send_at: "08:00", timezone: "UTC" }],
    users: [{ id: owner, name: "Alice Example", email: "alice@example.test", status: "active" }],
    usage: [{ kind: "incident", attempts: 2, sent: 0, failed: 2, unknown: 0 }], global_usage: [{ kind: "incident", attempts: 2, sent: 0, failed: 2, unknown: 0 }],
    total: 1, legacy: [], events: [{ id: "d2000000-0000-4000-8000-000000000001", owner, owner_name: "Alice Example", owner_email: "alice@example.test", node_name: "Mumbai gateway", kind: "incident", subject: "Heartbeat delayed", recipient: "alice@example.test", status: "failed", reason: "Provider unavailable", attempt_count: 2, attempt_limit: 3, terminal: false, updated_at: now, next_retry_at: now,
      attempts: [{ id: "attempt-1", started_at: now, finished_at: now, status: "failed", error: "Provider unavailable", provider_id: null }, { id: "attempt-2", started_at: now, finished_at: now, status: "failed", error: "Rate limited", provider_id: null }] }],
  };
  const props = { snapshot, owner: null, kind: "all" as const, status: "all", page: 1, canWrite: true, enforced: true, providerConfigured: true, previewHtml: "<p>Sample only</p>" };
  const button = (text: string) => [...document.querySelectorAll("button")].find(element => element.textContent?.includes(text))!;
  try {
    await act(async () => root.render(createElement(DeliveryDashboard, props)));
    assert.match(document.body.textContent!, /Alice Example[\s\S]*Mumbai gateway/);
    assert.match(document.body.textContent!, /One user\. One daily email/);
    assert.match(document.body.textContent!, /not the provider's plan allowance/);
    const digest = [...document.querySelectorAll<HTMLInputElement>('input[type="checkbox"]')].find(element => element.closest("label")?.textContent?.includes("Enable combined"))!;
    assert.equal(digest.checked, false);
    assert.equal(button("Save daily schedule").disabled, true);
    assert.equal(document.querySelector("iframe")?.getAttribute("sandbox"), "");
    writes.length = 0;
    await act(async () => button("Stop retries").click());
    assert.equal(writes.length, 0);
    await act(async () => button("Confirm stop").click());
    assert.equal(writes.at(-1)?.name, "hyn_admin_stop_delivery");
    assert.match(document.body.textContent!, /Attempt history \(2\)/);
    assert.match(document.body.textContent!, /Rate limited/);
    const select = document.querySelector("select")!;
    await act(async () => { select.value = owner; select.dispatchEvent(new dom.window.Event("change", { bubbles: true })); });
    assert.equal(navigations.at(-1), `/admin/deliveries?owner=${owner}`);
    await act(async () => root.render(createElement(DeliveryDashboard, { ...props, canWrite: false })));
    assert.equal(document.querySelector("form fieldset")?.hasAttribute("disabled"), true);
    assert.equal([...document.querySelectorAll("button")].some(element => element.textContent === "Stop retries"), false);
  } finally { await act(async () => root.unmount()); dom.window.close(); }
});
