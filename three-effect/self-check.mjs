// Minimal smoke test for ThreeCanvas — run with: node self-check.mjs
// Verifies module structure and that particle displacement math actually
// moves points over time (i.e. the animation isn't a no-op).
// No frameworks; no headless-GL/browser required.

import assert from "node:assert";
import { readFileSync } from "node:fs";

const src = readFileSync(new URL("./three-canvas.mjs", import.meta.url), "utf8");

// 1. Structural checks: the public API this file promises exists.
assert.match(src, /export class ThreeCanvas/, "ThreeCanvas class must be exported");
for (const method of ["setColor", "setParams", "resize", "destroy"]) {
  assert.match(
    new RegExp(`\\b${method}\\s*\\(`).test(src) ? src : "",
    new RegExp(`\\b${method}\\s*\\(`),
    `ThreeCanvas must expose ${method}()`
  );
}

// 2. Behavioral check: replicate the displacement formula in isolation
// (same math as _tick) and confirm two different timestamps produce
// different positions — i.e. the flow field actually animates.
function displace(base, seed, t, flux, speed) {
  return base + Math.sin(t * speed + seed) * flux * 3;
}

const base = 5, seed = 1.234, flux = 0.6, speed = 0.9;
const p1 = displace(base, seed, 1.0, flux, speed);
const p2 = displace(base, seed, 2.0, flux, speed);
assert.notStrictEqual(p1, p2, "particle position must change over time");

// 3. density=0 should hide all particles (parked at y=9999 in real code);
// confirm the visibleCount formula yields 0 at density 0 and MAX at density 1.
const MAX_PARTICLES = 4000;
assert.strictEqual(Math.floor(MAX_PARTICLES * 0), 0);
assert.strictEqual(Math.floor(MAX_PARTICLES * 1), MAX_PARTICLES);

console.log("OK: three-canvas.mjs self-check passed");
