"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";

// Ported from three-effect/three-canvas.mjs (the standalone ThreeCanvas
// class) to a React-friendly hook-based component that imports the app's own
// `three` install instead of the vendored copy in three-effect/vendor -- one
// copy of the library in the bundle, not two. The particle math, parameter
// names (fluxDynamics/processingThreads/clockRate/density) and the additive
// point-cloud flow field are unchanged from the original; see that file's
// header comment for why sine layering was used instead of real curl noise.
const MAX_PARTICLES = 4000;

export type ParticleFieldParams = {
  fluxDynamics?: number;
  processingThreads?: number;
  clockRate?: number;
  density?: number;
  color?: string;
};

const DEFAULTS: Required<ParticleFieldParams> = {
  fluxDynamics: 0.6,
  processingThreads: 0.9,
  clockRate: 0.1,
  density: 0.8,
  color: "#FFC700",
};

// Reads the page's own --background (see globals.css :root / .dark) so the
// renderer's clear colour always matches the real theme instead of guessing
// light vs dark from a prop. Falls back to black only if the variable is
// somehow unresolvable (no computed style yet, e.g. during a detached test).
function resolveBackground(el: Element): string {
  const value = getComputedStyle(el).getPropertyValue("--background").trim();
  return value || "#000000";
}

/**
 * Full-bleed animated particle background, fixed behind page content.
 *
 * `blur` controls how much of the effect shows through versus staying a
 * quiet texture behind readable content -- see globals.css `.particle-field`
 * for the actual blur values per tier:
 *   - "crisp"   -- sign-in: little content to compete with, so the effect is
 *                  the page's visual anchor.
 *   - "subtle"  -- dashboards, account, admin: dense with real data, so the
 *                  field has to recede almost to a soft glow, never a shape
 *                  that competes with a chart line.
 *   - "soft"    -- everything else (link, legal): a middle ground.
 */
export function ParticleField({
  blur = "soft",
  params,
  className = "",
}: {
  blur?: "crisp" | "soft" | "subtle";
  params?: ParticleFieldParams;
  className?: string;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    // Respect the same motion preference the rest of the site does (see
    // globals.css) -- a field that never stops moving is exactly what that
    // setting is asking for less of. Static points are still drawn once.
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const merged = { ...DEFAULTS, ...params };
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 100);
    camera.position.z = 30;

    // alpha:true + additive blending is the trap here: an additively-blended
    // point writes colour*srcAlpha into a framebuffer that starts fully
    // transparent, so the pixel's own alpha stays near zero even where the
    // point is bright. Compositing that over a *light* page still shows the
    // colour (the RGB nudge is visible against near-white through whatever
    // alpha survives), but compositing the same low-alpha pixel over a
    // *black* page is indistinguishable from black -- alpha compositing
    // scales the source colour by its own alpha before adding, and a near-
    // zero alpha times any colour rounds to nothing. Solid canvas + reading
    // the actual page background (see resolveBackground) avoids the alpha
    // math entirely: the renderer clears to a real opaque colour every
    // frame, so additive points always have *something* correct to add onto.
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(resolveBackground(canvas), 1);

    const positions = new Float32Array(MAX_PARTICLES * 3);
    const seeds = new Float32Array(MAX_PARTICLES);
    for (let i = 0; i < MAX_PARTICLES; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 60;
      positions[i * 3 + 1] = (Math.random() - 0.5) * 40;
      positions[i * 3 + 2] = (Math.random() - 0.5) * 40;
      seeds[i] = Math.random() * Math.PI * 2;
    }
    const basePositions = positions.slice();

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));

    const material = new THREE.PointsMaterial({
      color: new THREE.Color(merged.color),
      size: 0.12,
      transparent: true,
      opacity: 0.85,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });

    const points = new THREE.Points(geometry, material);
    scene.add(points);

    function resize() {
      const parent = canvas!.parentElement;
      const width = parent?.clientWidth || window.innerWidth;
      const height = parent?.clientHeight || window.innerHeight;
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    }
    resize();
    window.addEventListener("resize", resize);

    // next-themes toggles the `dark` class on <html> rather than reloading
    // the page, so the clear colour set at mount would otherwise go stale
    // the moment someone clicks the theme toggle while looking at this exact
    // canvas. Under reduced motion there's no render loop to pick the new
    // colour up on its own, so re-render the single static frame too.
    const observer = new MutationObserver(() => {
      renderer.setClearColor(resolveBackground(canvas), 1);
      if (reduceMotion) renderer.render(scene, camera);
    });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });

    let raf = 0;
    let elapsed = 0;
    let previousFrame = performance.now();
    function tick(now: number) {
      raf = requestAnimationFrame(tick);
      const dt = Math.min((now - previousFrame) / 1000, 0.1);
      previousFrame = now;
      elapsed += dt;
      const t = elapsed * (merged.clockRate * 10);
      const { fluxDynamics, processingThreads, density } = merged;
      const pos = geometry.attributes.position.array as Float32Array;
      const visibleCount = Math.floor(MAX_PARTICLES * density);

      for (let i = 0; i < MAX_PARTICLES; i++) {
        if (i >= visibleCount) {
          pos[i * 3 + 1] = 9999;
          continue;
        }
        const seed = seeds[i];
        const speed = processingThreads;
        const bx = basePositions[i * 3];
        const by = basePositions[i * 3 + 1];
        const bz = basePositions[i * 3 + 2];
        pos[i * 3] = bx + Math.sin(t * speed + seed) * fluxDynamics * 3;
        pos[i * 3 + 1] = by + Math.cos(t * speed * 0.8 + seed * 1.3) * fluxDynamics * 2;
        pos[i * 3 + 2] = bz + Math.sin(t * speed * 0.6 + seed * 0.7) * fluxDynamics * 2;
      }
      geometry.attributes.position.needsUpdate = true;
      points.rotation.y += dt * 0.02;
      renderer.render(scene, camera);
    }

    if (reduceMotion) {
      renderer.render(scene, camera);
    } else {
      raf = requestAnimationFrame(tick);
    }

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      observer.disconnect();
      geometry.dispose();
      material.dispose();
      renderer.dispose();
    };
    // params is a plain object literal at call sites; comparing it deeply on
    // every render would cost more than just letting a genuinely new object
    // remount the effect, which happens rarely (page-level, not per-frame).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params?.fluxDynamics, params?.processingThreads, params?.clockRate, params?.density, params?.color]);

  return (
    <div aria-hidden className={`particle-field particle-field--${blur} ${className}`}>
      <canvas ref={canvasRef} className="size-full" />
    </div>
  );
}
