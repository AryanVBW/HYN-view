import assert from "node:assert/strict";
import test from "node:test";
import { act, createElement } from "react";
import { JSDOM } from "jsdom";
import type { RelayerReading } from "../lib/relayer";

const readings: RelayerReading[] = [
  { id: 457, name: "Mumbai gateway" },
  { id: 458, name: "Pune gateway" },
].map(({ id, name }) => ({
  assignment: { id: `assignment-${id}`, owner: "alice", relayer_id: id, relayer_name: name, created_at: "2026-09-11T00:00:00Z" },
  relayer: null, chain: null, sourceAt: null, fetchedAt: null, providerLatencyMs: null, error: null, chainError: null,
}));

test("relay directory shows named cards, filters assigned relays and keeps every relay when selection changes", async () => {
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/dashboard?section=relayers" });
  Object.assign(globalThis, { window: dom.window, self: dom.window, document: dom.window.document, IS_REACT_ACT_ENVIRONMENT: true });
  const { createRoot } = await import("react-dom/client");
  const { RelayerDirectory } = await import("../components/dashboard/relayer-directory");
  const root = createRoot(document.getElementById("root")!);
  const props = { readings, current: 457, hrefFor: (id: number) => `/dashboard?section=relayers&relayer=${id}` };
  const links = () => [...document.querySelectorAll<HTMLAnchorElement>("li a")];
  try {
    await act(async () => root.render(createElement(RelayerDirectory, props)));
    assert.equal(links().length, 2);
    assert.match(document.querySelector('h3')!.textContent!, /Assigned relays2/);
    assert.deepEqual([...document.querySelectorAll("h4")].map(item => item.textContent), ["Mumbai gateway", "Pune gateway"]);
    assert.doesNotMatch(document.body.textContent!, /Shared dashboard|#457|#458|My devices/);
    assert.equal(document.querySelector('[aria-current="page"]')?.getAttribute("href"), props.hrefFor(457));
    assert.equal(links()[1].getAttribute("href"), props.hrefFor(458));
    await act(async () => root.render(createElement(RelayerDirectory, { ...props, current: 458 })));
    assert.equal(links().length, 2, "viewing a relay must not remove the user's other assignments");
    assert.equal(document.querySelector('[aria-current="page"]')?.getAttribute("href"), props.hrefFor(458));
    const input = document.querySelector("input")!;
    const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, "value")!.set!;
    const type = (value: string) => act(async () => {
      setter.call(input, value);
      input.dispatchEvent(new dom.window.Event("input", { bubbles: true }));
    });
    await type("pune");
    assert.equal(links().length, 1);
    assert.match(document.querySelector('[role="status"]')!.textContent!, /1 of 2 assigned relays shown/);
    await type("not-assigned");
    assert.equal(links().length, 0);
    assert.match(document.body.textContent!, /No assigned relays match/);
    await act(async () => document.querySelector("button")!.click());
    assert.equal(links().length, 2);
  } finally {
    await act(async () => root.unmount());
    dom.window.close();
  }
});

test("fleet relay directory deduplicates a relay assigned to multiple accounts", async () => {
  const dom = new JSDOM('<div id="root"></div>', { url: "https://portal.example/admin?tab=relayers" });
  Object.assign(globalThis, { window: dom.window, self: dom.window, document: dom.window.document, IS_REACT_ACT_ENVIRONMENT: true });
  const { createRoot } = await import("react-dom/client");
  const { RelayerDirectory } = await import("../components/dashboard/relayer-directory");
  const root = createRoot(document.getElementById("root")!);
  try {
    await act(async () => root.render(createElement(RelayerDirectory, {
      readings: [...readings, { ...readings[0], assignment: { ...readings[0].assignment, id: "bob-assignment", owner: "bob" } }],
      current: null, fleet: true, hrefFor: (id: number) => `/admin?tab=relayers&relayer=${id}`,
    })));
    assert.match(document.querySelector("h3")!.textContent!, /Fleet relays2/);
    assert.equal(document.querySelectorAll("li a").length, 2);
    assert.equal(document.querySelector('[aria-current="page"]'), null);
  } finally {
    await act(async () => root.unmount());
    dom.window.close();
  }
});
