import assert from "node:assert/strict";
import test from "node:test";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { JSDOM } from "jsdom";
import { RelayerRequestForm } from "../components/dashboard/relayer-request-form";

test("customer submits an identity, sees the saved pending request and can cancel it", async () => {
  const dom = new JSDOM('<div id="root"></div>', {
    url: "https://portal.example/dashboard",
  });
  Object.assign(globalThis, {
    window: dom.window,
    document: dom.window.document,
    FormData: dom.window.FormData,
    IS_REACT_ACT_ENVIRONMENT: true,
  });
  const originalFetch = globalThis.fetch;
  const root = createRoot(document.getElementById("root")!);
  const sent: unknown[] = [];
  let refreshed = 0;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, "/api/relayers/requests");
    assert.equal(options?.method, "POST");
    sent.push(JSON.parse(String(options?.body)));
    return Response.json({ ok: true });
  };
  try {
    await act(async () =>
      root.render(
        <RelayerRequestForm
          requests={[]}
          error={null}
          onChanged={() => refreshed++}
        />,
      ),
    );
    document.querySelector("input")!.value = "#457";
    await act(async () => {
      document
        .querySelector("form")!
        .dispatchEvent(
          new dom.window.Event("submit", { bubbles: true, cancelable: true }),
        );
    });
    assert.deepEqual(sent, [{ action: "request", query: "#457" }]);
    assert.equal(refreshed, 1);
    await act(async () =>
      root.render(
        <RelayerRequestForm
          requests={[
            {
              id: "request-id",
              relayer_id: 457,
              relayer_name: "Alice",
              status: "pending",
              created_at: "2026-09-09T00:00:00Z",
            },
          ]}
          error={null}
          onChanged={() => refreshed++}
        />,
      ),
    );
    assert.match(document.body.textContent!, /pending/i);
    const cancel = [...document.querySelectorAll("button")].find((b) =>
      b.textContent?.includes("Cancel"),
    )!;
    await act(async () => cancel.click());
    assert.deepEqual(sent[1], { action: "cancel", requestId: "request-id" });
    assert.equal(refreshed, 2);
    globalThis.fetch = async () =>
      Response.json(
        { error: "Highway search is unavailable" },
        { status: 502 },
      );
    await act(async () => {
      document
        .querySelector("form")!
        .dispatchEvent(
          new dom.window.Event("submit", { bubbles: true, cancelable: true }),
        );
    });
    assert.match(
      document.querySelector('[role="alert"]')!.textContent!,
      /Highway/,
    );
    assert.equal(refreshed, 2);
  } finally {
    await act(async () => root.unmount());
    globalThis.fetch = originalFetch;
    dom.window.close();
  }
});
