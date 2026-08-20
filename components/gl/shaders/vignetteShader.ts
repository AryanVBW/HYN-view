export const VignetteShader = {
  uniforms: {
    tDiffuse: { value: null }, // provided by ShaderPass
    darkness: { value: 1.0 }, // strength of the vignette effect
    offset: { value: 1.0 }, // vignette offset
    // The canvas's own clear color (see components/gl/index.tsx). The vignette
    // blends toward this, not toward black: multiplying rgb by a 0..1 factor
    // only ever darkens, which is invisible on the dark theme's near-black
    // canvas but leaves a grey-to-black ring on the light theme's canvas that
    // never matches the page background around it.
    vignetteColor: { value: [0, 0, 0] },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = vec4(position, 1.0);
    }
  `,
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse;
    uniform float darkness;
    uniform float offset;
    uniform vec3 vignetteColor;
    varying vec2 vUv;
    
    void main() {
      vec4 texel = texture2D(tDiffuse, vUv);
      
      // Calculate distance from center
      vec2 uv = (vUv - 0.5) * 2.0;
      float dist = dot(uv, uv);
      
      // Create vignette effect
      float vignette = 1.0 - smoothstep(offset, offset + darkness, dist);
      
      gl_FragColor = vec4(mix(vignetteColor, texel.rgb, vignette), texel.a);
    }
  `
};
