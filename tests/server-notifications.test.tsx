import assert from "node:assert/strict";
import test from "node:test";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { JSDOM } from "jsdom";
import { AppRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime.js";
import { ServerNotifications } from "../components/dashboard/server-notifications";
import type { ServerNotification } from "../lib/server-notifications";

test("inbox marks read locally, asks permission only on click, and notifies only new events", async () => {
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/notifications" });
  let requests = 0;
  const sent: string[] = [];
  class BrowserNotification {
    static permission = "default";
    static async requestPermission() { requests++; this.permission = "granted"; return "granted"; }
    constructor(title: string) { sent.push(title); }
    close() {}
  }
  Object.assign(globalThis, { window: dom.window, self: dom.window, document: dom.window.document, localStorage: dom.window.localStorage, Event: dom.window.Event, Notification: BrowserNotification, IS_REACT_ACT_ENVIRONMENT: true });
  const router = { back() {}, forward() {}, refresh() {}, hmrRefresh() {}, push() {}, replace() {}, prefetch() {} };
  const first: ServerNotification = { id:"alert:1", node_id:"one", owner:"owner", node_name:"Shared node", ts:"2026-09-10T10:00:00Z", severity:"warn", message:"Memory high", kind:"alert" };
  const root = createRoot(document.getElementById("root")!);
  const render = async (events: ServerNotification[]) => {
    await act(async () => root.render(<AppRouterContext.Provider value={router}><ServerNotifications userId="viewer" events={events} /></AppRouterContext.Provider>));
  };
  const button = (label: string) => [...document.querySelectorAll("button")].find(button => button.textContent === label)!;
  try {
    await render([first]);
    assert.equal(requests, 0);
    assert.equal(sent.length, 0);
    await act(async () => button("Mark all read").click());
    assert.match(document.body.textContent!, /0 unread/);
    assert.deepEqual(JSON.parse(localStorage.getItem("hyn:notifications:read:viewer")!), ["alert:1"]);
    await act(async () => button("Enable browser notifications").click());
    assert.equal(requests, 1);
    assert.equal(sent.length, 0);
    const next = { ...first, id:"alert:2", message:"CPU high" };
    await render([next, first]);
    assert.equal(sent.length, 1);
    assert.match(document.body.textContent!, /1 unread/);
    await render([next, first]);
    assert.equal(sent.length, 1);
    await render([]);
    assert.doesNotMatch(document.body.textContent!, /Memory high|CPU high/);
  } finally {
    await act(async () => root.unmount());
    dom.window.close();
  }
});
