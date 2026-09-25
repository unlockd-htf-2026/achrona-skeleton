// opaque.frag — the last pass on the globe: the frame, composited over the
// page's own background, fully opaque.
//
// The globe scene clears to transparent, so its translucent corona and bolts
// leave pixels whose (premultiplied) colour exceeds their alpha. Chrome and
// Firefox clamp those when they composite the canvas over the page; Safari
// (WebKit) blows them out — the void became a solid magenta disc. Doing the
// composite here, the way Chrome does it, gives every browser the same,
// valid, opaque picture.

uniform OpaqueInfo {
  vec4 backdrop; // the page colour behind the scene, display-referred
} opaque;

uniform sampler2D input_color;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  vec4 c = texture(input_color, v_uv);
  frag_color = vec4(c.rgb + opaque.backdrop.rgb * (1.0 - c.a), 1.0);
}
