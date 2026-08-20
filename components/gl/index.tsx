import { Effects } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import { Particles } from "./particles";
import { VignetteShader } from "./shaders/vignetteShader";

// Fixed particle-system defaults. These were previously exposed as live
// Leva debug sliders (dev-only tooling from the v0.app scaffold); the
// values below are the same defaults, just no longer editable at runtime
// so the homepage doesn't mount a debug panel on first render.
const speed = 1.0;
const noiseScale = 0.6;
const noiseIntensity = 0.52;
const timeScale = 1;
const focus = 3.8;
const aperture = 1.79;
const pointSize = 10.0;
const opacity = 0.8;
const planeScale = 10.0;
const size = 512;
const vignetteDarkness = 1.5;
const vignetteOffset = 0.4;
const useManualTime = false;
const manualTime = 0;

export const GL = ({ hovering }: { hovering: boolean }) => {
  // Three.js needs a real hex, not a CSS var -- <color args> is read once by
  // the renderer, not recomputed on every paint the way a CSS custom property
  // is. resolvedTheme is undefined until mount, so this defaults to the dark
  // canvas (matching the SSR/first-paint background) rather than flashing.
  const { resolvedTheme } = useTheme();
  const [background, setBackground] = useState("#000000");
  useEffect(() => {
    setBackground(resolvedTheme === "light" ? "#fafaf9" : "#000000");
  }, [resolvedTheme]);

  return (
    <div id="webgl">
      <Canvas
        camera={{
          position: [
            1.2629783123314589, 2.664606471394044, -1.8178993743288914,
          ],
          fov: 50,
          near: 0.01,
          far: 300,
        }}
      >
        <color attach="background" args={[background]} />
        <Particles
          speed={speed}
          aperture={aperture}
          focus={focus}
          size={size}
          noiseScale={noiseScale}
          noiseIntensity={noiseIntensity}
          timeScale={timeScale}
          pointSize={pointSize}
          opacity={opacity}
          planeScale={planeScale}
          useManualTime={useManualTime}
          manualTime={manualTime}
          introspect={hovering}
        />
        <Effects multisamping={0} disableGamma>
          <shaderPass
            args={[VignetteShader]}
            uniforms-darkness-value={vignetteDarkness}
            uniforms-offset-value={vignetteOffset}
          />
        </Effects>
      </Canvas>
    </div>
  );
};
