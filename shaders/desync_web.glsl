#version 300 es
// desync_web.glsl — The Curse of Achrona WebGL2 glitch overlay.
//
// Standalone overlay approach: renders scanlines and chromatic-aberration
// colour shifts as an ADDITIVE overlay.  The Flutter game canvas renders
// beneath; this canvas is layered on top with CSS mix-blend-mode additive
// blending, so no game-frame texture is required (sidesteps source-texture
// compositing complexity per RESEARCH §5).
//
// Uniforms:
//   uIntensity — 0.0 = no effect, 1.0 = full glitch
//   uTime      — elapsed seconds (drives animation)
//   uResolution — viewport size in pixels (set each frame)
//
// Effects: scanlines + chromatic aberration colour shifts + wave distortion.

precision mediump float;

uniform float uIntensity;
uniform float uTime;
uniform vec2 uResolution;

out vec4 fragColor;

// Cheap hash noise for glitch banding.
float hash(float n) { return fract(sin(n) * 43758.5453123); }

void main() {
  // Normalised UV: (0,0) bottom-left in WebGL, so flip y for top-left coords.
  vec2 uv = gl_FragCoord.xy / uResolution;
  uv.y = 1.0 - uv.y; // flip so top-left is (0,0)

  // --- Early out: no effect when intensity is zero ----------------------
  if (uIntensity < 0.001) {
    fragColor = vec4(0.0);
    return;
  }

  // --- Chromatic aberration: clearly visible RGB split ------------------
  float chromaOffset = uIntensity * 0.06; // up to ~6% of screen width
  float wave = sin(uv.y * 40.0 + uTime * 6.0) * uIntensity * 0.02;
  float rBand = smoothstep(0.0, 0.5, abs(sin((uv.x + chromaOffset + wave) * 6.28)));
  float bBand = smoothstep(0.0, 0.5, abs(sin((uv.x - chromaOffset - wave) * 6.28)));
  vec3 chroma = vec3(rBand, 0.0, bBand) * 0.6
              + vec3(0.0, bBand * 0.5, rBand * 0.5) * 0.4;

  // --- Glitch blocks: flashing horizontal bands -------------------------
  float band = step(0.6, hash(floor(uv.y * 24.0) + floor(uTime * 8.0)));
  vec3 glitch = vec3(0.6, 0.1, 0.8) * band * uIntensity * 0.5;

  // --- Scanlines: dark, every other row ---------------------------------
  float scan = (mod(floor(gl_FragCoord.y), 2.0) < 1.0)
      ? 1.0
      : (1.0 - 0.45 * uIntensity);

  vec3 color = (chroma + glitch) * scan;

  // --- Flicker: brief intensity surges ----------------------------------
  float flicker = 1.0 + 0.25 * uIntensity * step(0.92, fract(uTime * 18.0));
  color *= flicker;

  // Output additive overlay; alpha clearly visible (0.35) rising to ~0.8.
  float alpha = clamp(0.35 + 0.45 * uIntensity, 0.0, 0.85);
  fragColor = vec4(color * alpha, alpha);
}
