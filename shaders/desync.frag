// desync.frag — The Curse of Achrona glitch, as a flutter_scene PostEffect.
//
// Ported from ../achrona's native-only `desync.frag` (FragmentProgram), which
// throws on web and so shipped beside a second, pure-Flutter web overlay.
// Here it runs through flutter_scene's post stack — one implementation, every
// platform, and on web it samples and distorts the real frame too.
//
// Runs after tone mapping (display-referred), like the original: it glitches
// the finished picture. `intensity` 0 is pixel-identical to no effect.

uniform DesyncInfo {
  float intensity;
  float _pad0;
  float _pad1;
  float _pad2;
} desync;

uniform PostFrameInfo {
  vec2 resolution;
  vec2 texel_size;
  float time;
  float _pad;
} frame;

uniform sampler2D input_color;

in vec2 v_uv;
out vec4 frag_color;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 uv = v_uv;
  float i = desync.intensity;
  float time = frame.time;
  vec4 clean = texture(input_color, uv);

  // Horizontal tear bands: shift uv.x in occasional rows, jumping ~14x/s.
  float band = floor(uv.y * 28.0);
  float jump = hash(vec2(band, floor(time * 14.0)));
  float tear = (jump > 0.92 ? (jump - 0.5) : 0.0) * 0.07 * i;

  // Wave warp.
  float warp = sin(uv.y * 16.0 + time * 6.0) * 0.004 * i;
  vec2 duv = vec2(uv.x + warp + tear, uv.y);

  // Chromatic aberration, stronger toward the screen edges.
  float edge = abs(uv.x - 0.5) * 2.0;
  float ca = (0.0018 + 0.012 * edge) * i;
  vec4 col;
  col.r = texture(input_color, vec2(duv.x + ca, duv.y)).r;
  col.g = texture(input_color, duv).g;
  col.b = texture(input_color, vec2(duv.x - ca, duv.y)).b;
  col.a = clean.a;

  // Scanlines.
  float scan = 0.85 + 0.15 * sin(uv.y * frame.resolution.y * 3.14159);
  col.rgb *= mix(1.0, scan, 0.5 * i);

  // Rolling bright scan bar.
  float barPos = fract(time * 0.25);
  float bar = smoothstep(0.0, 0.06, abs(uv.y - barPos));
  col.rgb += (1.0 - bar) * 0.12 * i * vec3(0.7, 0.8, 1.0);

  // Noise grain.
  float n = hash(uv * frame.resolution + time * 60.0);
  col.rgb += (n - 0.5) * 0.12 * i;

  // Corruption tint (teal -> magenta across x).
  vec3 tint = mix(vec3(0.15, 0.9, 0.85), vec3(0.85, 0.2, 0.95), uv.x);
  col.rgb = mix(col.rgb, col.rgb + tint * 0.12, i * 0.5);

  // Vignette.
  float vig = 1.0 - smoothstep(0.5, 1.1, length(uv - 0.5) * 1.3) * (0.3 + 0.3 * i);
  col.rgb *= vig;

  frag_color = mix(clean, col, i);
}
