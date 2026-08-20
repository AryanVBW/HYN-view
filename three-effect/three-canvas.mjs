// ThreeCanvas — animated particle flow-field background effect.
//
// Reconstructed effect (not decompiled — the original site ships only a
// compiled <canvas data-engine="three.js r177"> with no recoverable source).
// Built to match the site's own "System Calibration" control panel, which
// exposes these exact parameters: Flux Dynamics, Processing Threads,
// Clock Rate, Density, Energy Profile (color).
//
// Usage:
//   import { ThreeCanvas } from "./three-canvas.mjs";
//   const effect = new ThreeCanvas(document.getElementById("hero-canvas"));
//   effect.setColor("#f97316"); // orange | "#3b82f6" blue | "#10b981" green
//   effect.destroy(); // stop animation + free GPU resources
//
// Params (match the calibration panel sliders 1:1):
//   fluxDynamics       0–2.0   default 0.6  — turbulence strength
//   processingThreads  0.1–2.0 default 0.9  — particle speed multiplier
//   clockRate          0–0.5   default 0.1  — time scale (overall speed)
//   density            0.1–1.0 default 0.8  — fraction of max particles shown

import * as THREE from "./vendor/three.mjs";

const MAX_PARTICLES = 4000;

export class ThreeCanvas {
  constructor(canvas, params = {}) {
    this.canvas = canvas;
    this.params = {
      fluxDynamics: 0.6,
      processingThreads: 0.9,
      clockRate: 0.1,
      density: 0.8,
      color: "#f97316",
      ...params,
    };

    this.clock = new THREE.Clock();
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(60, 1, 0.1, 100);
    this.camera.position.z = 30;

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: true,
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    this._buildParticles();
    this._onResize = () => this.resize();
    window.addEventListener("resize", this._onResize);
    this.resize();

    this._raf = requestAnimationFrame(this._tick.bind(this));
  }

  _buildParticles() {
    const geometry = new THREE.BufferGeometry();
    const positions = new Float32Array(MAX_PARTICLES * 3);
    const seeds = new Float32Array(MAX_PARTICLES); // per-particle phase offset

    for (let i = 0; i < MAX_PARTICLES; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 60;
      positions[i * 3 + 1] = (Math.random() - 0.5) * 40;
      positions[i * 3 + 2] = (Math.random() - 0.5) * 40;
      seeds[i] = Math.random() * Math.PI * 2;
    }

    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute("seed", new THREE.BufferAttribute(seeds, 1));

    this.material = new THREE.PointsMaterial({
      color: new THREE.Color(this.params.color),
      size: 0.12,
      transparent: true,
      opacity: 0.85,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });

    this.points = new THREE.Points(geometry, this.material);
    this.scene.add(this.points);
    this._basePositions = positions.slice();
    this._seeds = seeds;
  }

  // Flow-field displacement: cheap curl-noise stand-in using layered sines.
  // ponytail: real curl noise (e.g. simplex-based) would look smoother at
  // high fluxDynamics, but sine layering is O(1) per vertex and matches the
  // "operational grid" aesthetic well enough. Swap in a noise lib if the
  // motion needs to look organic rather than mechanical.
  _tick() {
    this._raf = requestAnimationFrame(this._tick.bind(this));
    const dt = this.clock.getDelta();
    const t = this.clock.elapsedTime * (this.params.clockRate * 10);
    const { fluxDynamics, processingThreads, density } = this.params;

    const pos = this.points.geometry.attributes.position.array;
    const visibleCount = Math.floor(MAX_PARTICLES * density);

    for (let i = 0; i < MAX_PARTICLES; i++) {
      if (i >= visibleCount) {
        pos[i * 3 + 1] = 9999; // park hidden particles off-frame
        continue;
      }
      const seed = this._seeds[i];
      const speed = processingThreads;
      const bx = this._basePositions[i * 3];
      const by = this._basePositions[i * 3 + 1];
      const bz = this._basePositions[i * 3 + 2];

      pos[i * 3] = bx + Math.sin(t * speed + seed) * fluxDynamics * 3;
      pos[i * 3 + 1] =
        by + Math.cos(t * speed * 0.8 + seed * 1.3) * fluxDynamics * 2;
      pos[i * 3 + 2] = bz + Math.sin(t * speed * 0.6 + seed * 0.7) * fluxDynamics * 2;
    }

    this.points.geometry.attributes.position.needsUpdate = true;
    this.points.rotation.y += dt * 0.02;

    this.renderer.render(this.scene, this.camera);
  }

  setColor(hex) {
    this.params.color = hex;
    this.material.color.set(hex);
  }

  setParams(partial) {
    Object.assign(this.params, partial);
  }

  resize() {
    const { clientWidth, clientHeight } = this.canvas.parentElement || this.canvas;
    const width = clientWidth || window.innerWidth;
    const height = clientHeight || window.innerHeight;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  destroy() {
    cancelAnimationFrame(this._raf);
    window.removeEventListener("resize", this._onResize);
    this.points.geometry.dispose();
    this.material.dispose();
    this.renderer.dispose();
  }
}
