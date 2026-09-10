import test from "node:test";
import assert from "node:assert/strict";
import { portalOrigin } from "./portal-origin.ts";

test("Heroku callback uses either public portal domain rather than the internal listener", () => {
  for (const host of ["www.hyn-view.in", "hyn-view.in"]) {
    const request = { url: "http://0.0.0.0:3407/auth/callback", headers: new Headers({ host }) };
    assert.equal(portalOrigin(request), `https://${host}`);
  }
});

test("redirects refuse host injection and allow only the configured custom origin", () => {
  const request = { url: "http://0.0.0.0:3407/auth/callback", headers: new Headers({ host: "evil.example", "x-forwarded-host": "www.hyn-view.in@evil.example" }) };
  assert.equal(portalOrigin(request), "https://www.hyn-view.in");
  request.headers.set("host", "custom.example");
  assert.equal(portalOrigin(request, "https://custom.example"), "https://custom.example");
});
