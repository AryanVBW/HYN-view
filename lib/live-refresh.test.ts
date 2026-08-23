import assert from "node:assert/strict";
import test from "node:test";
import { startRecurringRefresh } from "./live-refresh.ts";

test("live pages refresh once a minute and clean up their timer", () => {
  let callback: (() => void) | undefined;
  let delay = 0;
  let cleared: unknown = null;
  let refreshes = 0;
  const token = { timer: 1 };

  const stop = startRecurringRefresh(
    () => { refreshes += 1; },
    (fn, ms) => { callback = fn; delay = ms; return token; },
    (value) => { cleared = value; },
  );

  assert.equal(delay, 60_000);
  callback?.();
  assert.equal(refreshes, 1);
  stop();
  assert.equal(cleared, token);
});
