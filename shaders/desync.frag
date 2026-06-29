#include <flutter/runtime_effect.glsl>

// desync.frag — The Curse of Achrona glitch post-process (native builds).
//
// A full-screen post-pass over the captured game frame. Because native builds
// support FragmentProgram, this can SAMPLE and DISTORT the real frame (true
// chromatic aberration, UV warp, tearing) — higher fidelity than the web
// CustomPaint overlay, which can only add colour on top.
//
// Uniforms (bound in ShaderController.applyToCanvas, in declaration order):
//   float intensity     0.0 = clean, 1.0 = full corruption
//   float time          elapsed seconds (drives animation)
//   vec2  uResolution   viewport size in pixels (avoids textureSize())
//   sampler2D uScene    the captured scene frame
//
// Effects: UV warp + horizontal tear bands + edge-weighted chromatic
// aberration + scanlines + rolling scan bar + noise grain + corruption tint +
// vignette. Everything scales with `intensity` and `mix`es back to the clean
// frame so intensity 0 is pixel-identical to no shader.

uniform float intensity;
uniform float time;
uniform vec2 uResolution;
uniform sampler2D uScene;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uResolution;
  float i = intensity;

  vec4 clean = texture(uScene, uv);

  // ── Horizontal tear bands: shift uv.x in occasional rows, jumping ~14x/s ──
  float band = floor(uv.y * 28.0);
  float jump = hash(vec2(band, floor(time * 14.0)));
  float tear = (jump > 0.92 ? (jump - 0.5) : 0.0) * 0.07 * i;

  // ── Wave warp ──
  float warp = sin(uv.y * 16.0 + time * 6.0) * 0.004 * i;

  vec2 duv = vec2(uv.x + warp + tear, uv.y);

  // ── Chromatic aberration, stronger toward the screen edges ──
  float edge = abs(uv.x - 0.5) * 2.0;
  float ca = (0.0018 + 0.012 * edge) * i;
  vec4 col;
  col.r = texture(uScene, vec2(duv.x + ca, duv.y)).r;
  col.g = texture(uScene, duv).g;
  col.b = texture(uScene, vec2(duv.x - ca, duv.y)).b;
  col.a = 1.0;

  // ── Scanlines ──
  float scan = 0.85 + 0.15 * sin(uv.y * uResolution.y * 3.14159);
  col.rgb *= mix(1.0, scan, 0.5 * i);

  // ── Rolling bright scan bar ──
  float barPos = fract(time * 0.25);
  float bar = smoothstep(0.0, 0.06, abs(uv.y - barPos));
  col.rgb += (1.0 - bar) * 0.12 * i * vec3(0.7, 0.8, 1.0);

  // ── Noise grain ──
  float n = hash(uv * uResolution + time * 60.0);
  col.rgb += (n - 0.5) * 0.12 * i;

  // ── Corruption tint (teal → magenta across x), additive near max ──
  vec3 tint = mix(vec3(0.15, 0.9, 0.85), vec3(0.85, 0.2, 0.95), uv.x);
  col.rgb = mix(col.rgb, col.rgb + tint * 0.12, i * 0.5);

  // ── Vignette ──
  float vig = 1.0 - smoothstep(0.5, 1.1, length(uv - 0.5) * 1.3) * (0.3 + 0.3 * i);
  col.rgb *= vig;

  fragColor = mix(clean, col, i);
}
