import assert from "node:assert/strict";
import { test } from "node:test";
import { handlePortalMore } from "../src/portal-more.ts";

test("portal-more RPC handler loads", () => {
  assert.equal(typeof handlePortalMore, "function");
});
