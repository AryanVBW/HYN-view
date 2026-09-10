import assert from "node:assert/strict";
import test from "node:test";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { JSDOM } from "jsdom";
import { SearchParamsContext } from "next/dist/shared/lib/hooks-client-context.shared-runtime.js";
import { AdminTabs } from "../components/admin/admin-tabs";

test("client navigation reveals assignment controls and returning to Clients hides them", async () => {
  const dom = new JSDOM('<div id="root"></div>', {
    url: "https://portal.example/admin?tab=clients",
  });
  Object.assign(globalThis, {
    window: dom.window,
    document: dom.window.document,
    IS_REACT_ACT_ENVIRONMENT: true,
  });
  const root = createRoot(document.getElementById("root")!);
  const render = async (query: string, client: boolean) => {
    await act(async () =>
      root.render(
        <SearchParamsContext.Provider value={new URLSearchParams(query)}>
          <AdminTabs
            overview="Overview"
            clients="Accounts"
            fleet="Fleet"
            templates="Templates"
            notifications="Deliveries"
            audit="Audit"
            relayers={<button>Review relayer assignments</button>}
            badges={{}}
            initialActive={client ? "client" : "clients"}
            client={client ? <button>Assign relayer</button> : undefined}
          />
        </SearchParamsContext.Provider>,
      ),
    );
  };
  try {
    await render("tab=clients", false);
    await render("tab=client&client=alice", true);
    const assignment = [...document.querySelectorAll("button")].find(
      (b) => b.textContent === "Assign relayer",
    )!;
    assert.equal(
      assignment.closest("[role=tabpanel]")!.hasAttribute("hidden"),
      false,
    );
    await render("tab=clients&client=alice", true);
    assert.equal(
      assignment.closest("[role=tabpanel]")!.hasAttribute("hidden"),
      true,
    );
    await render("tab=client&client=alice", true);
    assert.equal(
      assignment.closest("[role=tabpanel]")!.hasAttribute("hidden"),
      false,
    );
    const clients = [
      ...document.querySelectorAll<HTMLButtonElement>("[role=tab]"),
    ].find((b) => b.textContent?.includes("Clients"))!;
    await act(async () => clients.click());
    assert.equal(
      new URL(window.location.href).searchParams.get("tab"),
      "clients",
    );
    await render("tab=relayers", false);
    assert.equal(document.querySelector('#admin-panel-relayers')?.hasAttribute("hidden"), false);
    assert.match(document.querySelector('#admin-panel-relayers')?.textContent ?? "", /Review relayer assignments/);
    const relayers = document.querySelector<HTMLButtonElement>('#admin-tab-relayers')!;
    assert.equal(relayers.tabIndex, 0);
    await act(async () => relayers.dispatchEvent(new dom.window.KeyboardEvent("keydown", {key: "ArrowLeft", bubbles: true})));
    assert.equal(new URL(window.location.href).searchParams.get("tab"), "fleet");
    assert.equal(document.activeElement?.id, "admin-tab-fleet");
    await render("tab=overview", false);
    assert.equal(document.querySelector('#admin-panel-relayers')?.textContent, "", "hidden relayers must not mount a polling dashboard");
  } finally {
    await act(async () => root.unmount());
    dom.window.close();
  }
});
