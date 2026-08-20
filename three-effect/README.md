# three-effect

A standalone, animated particle flow-field background — reconstructed to
match the "ThreeCanvas" hero effect and its "System Calibration" control
panel (Flux Dynamics, Processing Threads, Clock Rate, Density, Energy
Profile) seen on the FlowForge page.

## Important: this is a reconstruction, not a copy

The original site's scraped snapshot (`backdound-forHYN-view/`) only
contained the rendered `<canvas data-engine="three.js r177">` output and the
raw Three.js library — no scene-building source (camera/geometry/material/
animation-loop code) was present anywhere in the scrape to copy. I searched
every `.js`/`.mjs` bundle and the HTML; the closest matches were a
`WebGLRenderer.prototype.render` monkey-patch (screenshot tooling, unrelated
to the visual) and the raw library files. So this effect was built fresh in
plain Three.js r177, using the calibration panel's exact parameter names as
a guide to what the original likely tuned.

## Contents

- `vendor/three.mjs`, `vendor/three.core.mjs` — Three.js r177, copied
  verbatim from the source site's assets (same version it used).
- `three-canvas.mjs` — the effect itself: `ThreeCanvas` class, a
  GPU-friendly additive-blended particle system with a sine-layered
  flow field.
- `demo.html` — open directly in a browser (via a local static server,
  ES modules need http(s), not `file://`) to see it live with sliders
  for every calibration parameter.
- `self-check.mjs` — `node self-check.mjs` — structural + math smoke test.

## Using it on your other site

```js
import { ThreeCanvas } from "./three-effect/three-canvas.mjs";

const effect = new ThreeCanvas(document.getElementById("your-canvas"));
effect.setParams({ fluxDynamics: 0.6, processingThreads: 0.9, clockRate: 0.1, density: 0.8 });
effect.setColor("#f97316"); // or #3b82f6 / #10b981
// ...
effect.destroy(); // on unmount, to free GPU resources
```

Just copy this whole folder into your project and point the canvas element
at it. No build step or bundler required — it's plain ES modules.

## Known limitations (ponytail: intentional shortcuts)

- Flow field uses layered `sin`/`cos` instead of real curl noise — cheap
  (O(1)/particle) but looks more "mechanical grid" than "organic smoke".
  Swap in a simplex/curl noise function if you need smoother motion.
- Particle count is fixed at 4000 with a `density` slider that hides the
  tail rather than reallocating the buffer — avoids GC churn but means
  memory cost is always for the max, even at low density.
