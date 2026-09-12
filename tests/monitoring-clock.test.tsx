import assert from "node:assert/strict";
import test from "node:test";
import { act } from "react";
import { JSDOM } from "jsdom";
import { AppRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime.js";
import { ReadingAge } from "../components/dashboard/reading-age";
import { HeartbeatIndicator } from "../components/dashboard/heartbeat-indicator";
import { LiveRefresh } from "../components/live-refresh";
import { MONITORING_EVENT } from "../lib/monitoring-state";

function browser() {
  const dom = new JSDOM('<div id="root"></div>', {url: "https://portal.test/dashboard", pretendToBeVisual: true});
  const replacements = {window: dom.window, self: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, CustomEvent: dom.window.CustomEvent, IS_REACT_ACT_ENVIRONMENT: true};
  const previous = new Map(Object.keys(replacements).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  for (const [key, value] of Object.entries(replacements)) Object.defineProperty(globalThis, key, {value, configurable: true, writable: true});
  return {dom, restore: () => {
    for (const [key, descriptor] of previous) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else Reflect.deleteProperty(globalThis, key);
    }
    dom.window.close();
  }};
}

test("reading ages tick without router refresh and newer server heartbeat props win", async (t) => {
  const {dom, restore} = browser();
  let clock = Date.parse("2026-09-12T12:00:00Z");
  t.mock.method(Date, "now", () => clock);
  const ticks: (() => void)[] = [];
  let cleared = 0;
  t.mock.method(dom.window, "setInterval", (callback: TimerHandler) => {
    assert.equal(typeof callback, "function");
    ticks.push(callback as () => void);
    return ticks.length;
  });
  t.mock.method(dom.window, "clearInterval", () => { cleared++; });
  const {createRoot} = await import("react-dom/client");
  const root = createRoot(document.getElementById("root")!);
  const render = (heartbeat = "2026-09-12T12:00:00Z") => <>
    <p id="reading"><ReadingAge sampleAt="2026-09-12T12:00:00Z" /></p>
    <HeartbeatIndicator nodeId="server" heartbeatAt={heartbeat} />
  </>;
  try {
    await act(async () => root.render(render()));
    assert.equal(document.querySelector("#reading")?.textContent, "0s ago");
    clock += 60_000;
    await act(async () => ticks.forEach(tick => tick()));
    assert.equal(document.querySelector("#reading")?.textContent, "1m 0s ago");
    await act(async () => window.dispatchEvent(new CustomEvent(MONITORING_EVENT, {detail: {nodeId: "server", heartbeatAt: "2026-09-12T12:00:30Z"}})));
    assert.match(document.querySelector('[role="status"]')?.textContent ?? "", /30s ago/);
    await act(async () => root.render(render("2026-09-12T12:00:55Z")));
    assert.match(document.querySelector('[role="status"]')?.textContent ?? "", /5s ago/);
    clock += 120_000;
    await act(async () => ticks.forEach(tick => tick()));
    assert.equal(document.querySelector("#reading")?.textContent, "3m 0s ago · readings delayed");
  } finally {
    await act(async () => root.unmount());
    assert.equal(cleared, 2);
    restore();
  }
});

test("unchanged small polls refresh expired views at five minutes and wait while hidden", async (t) => {
  const {dom, restore} = browser();
  let clock = Date.parse("2026-09-12T12:00:00Z");
  t.mock.method(Date, "now", () => clock);
  let callback: (() => void) | undefined;
  t.mock.method(globalThis, "setInterval", (tick: () => void, delay: number) => {
    assert.equal(delay, 15_000);
    callback = tick;
    return 1 as unknown as ReturnType<typeof setInterval>;
  });
  t.mock.method(globalThis, "clearInterval", () => {});
  let fetches = 0, refreshed = 0;
  t.mock.method(globalThis, "fetch", async () => {
    fetches++;
    return new Response(JSON.stringify({nodeId: "server", revision: "stable", heartbeatAt: "2026-09-12T12:00:00Z"}), {status: 200});
  });
  const router = {back() {}, forward() {}, refresh() {refreshed++;}, hmrRefresh() {}, push() {}, replace() {}, prefetch() {}};
  const {createRoot} = await import("react-dom/client");
  const root = createRoot(document.getElementById("root")!);
  try {
    await act(async () => root.render(<AppRouterContext.Provider value={router}><LiveRefresh nodeId="server" revision="stable" /></AppRouterContext.Provider>));
    clock += 15_000;
    await act(async () => { callback!(); });
    assert.equal(fetches, 1);
    assert.equal(refreshed, 0);
    clock += 285_000;
    await act(async () => { callback!(); });
    assert.equal(refreshed, 1);
    assert.equal(fetches, 1);
    clock += 15_000;
    await act(async () => { callback!(); });
    assert.equal(refreshed, 1);
    assert.equal(fetches, 2);
    Object.defineProperty(document, "visibilityState", {value: "hidden", configurable: true});
    clock += 600_000;
    await act(async () => { callback!(); });
    assert.equal(refreshed, 1);
    Object.defineProperty(document, "visibilityState", {value: "visible", configurable: true});
    await act(async () => document.dispatchEvent(new dom.window.Event("visibilitychange")));
    assert.equal(refreshed, 2);
  } finally {
    await act(async () => root.unmount());
    restore();
  }
});
