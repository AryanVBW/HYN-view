"use client";

import { useEffect, useRef, useState } from "react";

// Shared by every radial instrument on the simple dashboard (SpeedGauge's
// needle and fill arc, ThermalGauge's needle, EssentialRing's fill) that
// sweeps from zero to a target percentage the first time it scrolls into
// view, rather than the moment the page loads.
//
// Animating on mount meant a gauge below the fold had already finished its
// 0-to-value sweep, invisibly, before anyone scrolled to it -- so a user who
// landed on "highway node" and then scrolled down to "temperature" saw the
// thermal dial sitting at its final reading from the first frame, the exact
// "did this even animate" flatness the sweep exists to avoid. Gating the
// start on IntersectionObserver (rather than a scroll listener -- see
// animate.md's own guidance) means the sweep always happens at the moment a
// person can actually see it, wherever that moment lands in the scroll.
//
// Firing once per element and then disconnecting (rather than restarting
// every time it re-enters the viewport) is deliberate too: a needle that
// resets to zero and re-sweeps on every scroll-past reads as broken, not
// polished -- the "watch it climb" moment is a first-reveal, not a replay.
//
// This drives the animation itself, frame by frame, rather than setting a
// CSS `transition` and letting the browser interpolate: SVG geometry
// attributes -- `d` on <path>, `x1/y1/x2/y2` on <line> -- are presentation
// attributes, not CSS properties, and CSS transitions can only interpolate
// CSS properties. `d` is confirmed non-transitionable in every browser, and
// `x2`/`y2` support is inconsistent (WebKit/Blink added a handful of SVG
// geometry properties -- x, y, cx, cy, r -- as CSS-animatable, but line
// endpoints were never part of that list). Interpolating the number here,
// every frame, and letting each consumer recompute its own geometry from
// that number sidesteps the whole "is this attribute CSS-animatable"
// question, because nothing is ever handed to a CSS transition -- every
// frame is a fresh, already-correct SVG attribute.
export function useAnimatedPct<T extends Element>(
  target: number
): { value: number; ref: React.RefObject<T | null> } {
  const [reduceMotion] = useState(
    () => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches
  );
  // Known synchronously at first render, same reasoning as reduceMotion just
  // above: a browser/environment either has IntersectionObserver or it
  // doesn't, so that fact belongs in a lazy initializer, not a branch inside
  // an effect that then has to call setState to act on it (the shape
  // react-hooks/set-state-in-effect correctly flags -- see that rule's own
  // note on reading a value via useState's initializer instead).
  const [hasObserver] = useState(() => typeof IntersectionObserver !== "undefined");
  const [animated, setAnimated] = useState(0);
  // The value this hook was animating *from* the last time `target` changed,
  // so a live reading that updates mid-sweep eases from wherever the needle
  // actually was, not from zero again.
  const fromRef = useRef(0);
  const elementRef = useRef<T>(null);
  // Whether the element has ever been seen. A plain boolean ref rather than
  // state: flipping it must not itself trigger a re-render, only the RAF loop
  // it unlocks should -- and it only needs to be read inside effects, never
  // rendered. Starts pre-set to true when this environment has no
  // IntersectionObserver at all (very old browsers, a non-DOM test runner):
  // there is nothing to wait for a needle to be visible via, so the fallback
  // is to treat it as always-visible rather than a needle that never sweeps.
  const hasBeenVisibleRef = useRef(!hasObserver);
  const [triggerAnimation, setTriggerAnimation] = useState(!hasObserver);

  // Reduced motion never needs to know about visibility at all: the target
  // is what always renders, so there is nothing to trigger. Likewise skipped
  // when there's no IntersectionObserver to begin with -- hasBeenVisibleRef
  // already starts true in that case, so there is nothing left for this
  // effect to observe or to set.
  useEffect(() => {
    if (reduceMotion || !hasObserver) return;
    const el = elementRef.current;
    if (!el || hasBeenVisibleRef.current) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          hasBeenVisibleRef.current = true;
          setTriggerAnimation(true);
          observer.disconnect();
        }
      },
      // A small negative margin so the sweep starts once the dial is
      // meaningfully on screen, not the instant its very first pixel peeks
      // past the viewport edge.
      { threshold: 0.2 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [reduceMotion, hasObserver]);

  useEffect(() => {
    if (reduceMotion) return;
    // Nothing to animate toward until the element has actually been seen.
    // `target` is still tracked in the dependency array below so a value
    // that changes after the first reveal still eases correctly.
    if (!hasBeenVisibleRef.current) return;
    const from = fromRef.current;
    const distance = target - from;
    if (distance === 0) return;

    // Slower than a typical UI transition on purpose: this is the dial's one
    // hero moment (see animate.md's 500-800ms entrance guidance, doubled
    // again on explicit request) -- a needle that visibly, deliberately
    // climbs across two full seconds reads as a real instrument warming up,
    // where 900ms read as a flick.
    const durationMs = 2200;
    let raf = 0;
    let start: number | null = null;

    // cubic-bezier(0.16, 1, 0.3, 1) has no closed-form inverse worth solving
    // for a two-value sweep; a quintic ease-out (1 - (1-t)^5) is the same
    // "fast start, gentle settle" shape the rest of this dial's motion uses
    // and is exact to compute every frame.
    function ease(t: number): number {
      return 1 - Math.pow(1 - t, 5);
    }

    function tick(now: number) {
      if (start === null) start = now;
      const elapsed = now - start;
      const t = Math.min(1, elapsed / durationMs);
      setAnimated(from + distance * ease(t));
      if (t < 1) {
        raf = requestAnimationFrame(tick);
      } else {
        fromRef.current = target;
      }
    }
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // triggerAnimation forces this effect to re-run the instant visibility
    // is confirmed; its value is never read in the body, only its presence
    // in the deps array matters, which is a legitimate use the exhaustive-deps
    // rule already accepts without a suppression comment.
  }, [target, reduceMotion, triggerAnimation]);

  // Reduced motion never enters the animation loop at all: the target
  // renders directly on every render, so a later value change tracks
  // immediately with no motion, rather than needing a frame loop to reach it.
  return { value: reduceMotion ? target : animated, ref: elementRef };
}
