import assert from "node:assert/strict";
import test from "node:test";

import { buildPasswordSignUpRequest, normalizeInternalPath } from "./legal-consent.ts";

test("post-authentication redirects accept only local single-slash paths", () => {
  assert.equal(normalizeInternalPath("/dashboard?node=abc"), "/dashboard?node=abc");
  assert.equal(normalizeInternalPath("javascript:alert(1)"), "/dashboard");
  assert.equal(normalizeInternalPath("https://attacker.example/"), "/dashboard");
  assert.equal(normalizeInternalPath("//attacker.example/"), "/dashboard");
  assert.equal(normalizeInternalPath("/\\attacker.example/"), "/dashboard");
  assert.equal(normalizeInternalPath("/dashboard\njavascript:alert(1)"), "/dashboard");
});

test("password registration refuses to proceed without affirmative legal acceptance", () => {
  assert.throws(
    () =>
      buildPasswordSignUpRequest({
        email: "owner@example.com",
        password: "correct horse battery staple",
        emailRedirectTo: "https://www.hyn-view.in/auth/callback",
        acceptedTerms: false,
        acceptedAt: new Date("2026-08-21T10:30:00.000Z"),
      }),
    /accept the Terms of Use and acknowledge the Privacy Notice/,
  );
});

test("password registration records the accepted legal version and time", () => {
  assert.deepEqual(
    buildPasswordSignUpRequest({
      email: " owner@example.com ",
      password: "correct horse battery staple",
      emailRedirectTo: "https://www.hyn-view.in/auth/callback?next=%2Fdashboard",
      acceptedTerms: true,
      acceptedAt: new Date("2026-08-21T10:30:00.000Z"),
    }),
    {
      email: "owner@example.com",
      password: "correct horse battery staple",
      options: {
        emailRedirectTo: "https://www.hyn-view.in/auth/callback?next=%2Fdashboard",
        data: {
          legal_terms_version: "2026-08-21",
          legal_terms_accepted_at: "2026-08-21T10:30:00.000Z",
          legal_terms_url: "https://www.hyn-view.in/terms",
          privacy_notice_url: "https://www.hyn-view.in/privacy",
        },
      },
    },
  );
});
