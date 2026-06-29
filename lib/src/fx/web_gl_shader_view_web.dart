// web_gl_shader_view_web.dart — Real WebGL2 implementation (web only).
//
// Selected by the conditional import in web_gl_shader_view.dart when
// compiling for Flutter web targets.
//
// Uses `package:web` (dart:js_interop typed API) to access the browser DOM
// and the WebGL2RenderingContext.  Registers the platform view factory via
// `dart:ui_web` (Flutter 3.22+, replaces dart:ui platformViewRegistry).
//
// Architecture (RESEARCH §5 / D-17):
//   * A <canvas> element is injected into the Flutter DOM via
//     HtmlElementView platform view.
//   * The canvas is styled `position:absolute; pointer-events:none;
//     z-index:10` — sits above the Flutter CanvasKit layer, transparent
//     background, does NOT capture pointer events (T-06-01).
//   * Renders scanlines + chromatic-aberration as an additive overlay so
//     the game frame underneath shows through unchanged (T-06-04: no frame
//     data leaks to JS layer).
//   * On any init or context-loss failure, sets [failed]=true so
//     ShaderController can switch to the ColorFilter fallback (T-06-02/03).

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

// ─────────────────────────────────────────────────────────────────────────────
// Vertex shader: pass-through quad covering the full viewport.
// ─────────────────────────────────────────────────────────────────────────────

const String _vertexSrc = '''
#version 300 es
in vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
''';

// ─────────────────────────────────────────────────────────────────────────────
// Fragment shader: scanlines + chromatic-aberration additive overlay.
// Logic mirrors desync_web.glsl (inlined so no asset fetch is needed at
// runtime — avoids CORS/path issues in the web build).
// ─────────────────────────────────────────────────────────────────────────────

const String _fragmentSrc = '''
#version 300 es
precision mediump float;

uniform float uIntensity;
uniform float uTime;
uniform vec2 uResolution;

out vec4 fragColor;

// Cheap hash noise for glitch banding.
float hash(float n) { return fract(sin(n) * 43758.5453123); }

void main() {
  vec2 uv = gl_FragCoord.xy / uResolution;
  uv.y = 1.0 - uv.y;

  if (uIntensity < 0.001) {
    fragColor = vec4(0.0);
    return;
  }

  // ── Chromatic aberration: clearly visible RGB split. The R and B bands are
  // offset horizontally; the offset (and thus the colour fringing) grows with
  // intensity. We accumulate coloured tint where the bands separate.
  float chromaOffset = uIntensity * 0.06; // up to ~6% of screen width
  float wave = sin(uv.y * 40.0 + uTime * 6.0) * uIntensity * 0.02;
  float rBand = smoothstep(0.0, 0.5, abs(sin((uv.x + chromaOffset + wave) * 6.28)));
  float bBand = smoothstep(0.0, 0.5, abs(sin((uv.x - chromaOffset - wave) * 6.28)));
  // Teal/magenta corruption fringing.
  vec3 chroma = vec3(rBand, 0.0, bBand) * 0.6
              + vec3(0.0, bBand * 0.5, rBand * 0.5) * 0.4;

  // ── Glitch blocks: horizontal bands that flash on at high intensity.
  float band = step(0.6, hash(floor(uv.y * 24.0) + floor(uTime * 8.0)));
  vec3 glitch = vec3(0.6, 0.1, 0.8) * band * uIntensity * 0.5;

  // ── Scanlines: dark, frequent (every other row), stronger with intensity.
  float scan = (mod(floor(gl_FragCoord.y), 2.0) < 1.0)
      ? 1.0
      : (1.0 - 0.45 * uIntensity);

  // ── Combine into an additive corruption tint.
  vec3 color = (chroma + glitch) * scan;

  // ── Flicker: brief intensity surges.
  float flicker = 1.0 + 0.25 * uIntensity * step(0.92, fract(uTime * 18.0));
  color *= flicker;

  // ── Alpha: clearly visible base (0.35) rising to strong (~0.8) near wall.
  float alpha = clamp(0.35 + 0.45 * uIntensity, 0.0, 0.85);
  fragColor = vec4(color * alpha, alpha);
}
''';

// ─────────────────────────────────────────────────────────────────────────────
// WebGL2 helper — thin wrapper around callMethodVarArgs (js_interop_unsafe).
//
// IMPORTANT: use callMethodVarArgs, NOT callMethod. `callMethod` takes a single
// JSAny arg and the [args] list would be passed as ONE positional JS argument
// (e.g. gl.shaderSource([shader, src]) → JS sees 1 arg → throws "2 arguments
// required, but only 1 present"). callMethodVarArgs spreads [args] into real
// positional JS arguments, which is what every WebGL call needs.
// ─────────────────────────────────────────────────────────────────────────────

extension type _GL(JSObject _) implements JSObject {}

JSAny? _call(_GL gl, String method, List<JSAny?> args) {
  return gl.callMethodVarArgs<JSAny?>(method.toJS, args);
}

/// Synchronous, one-shot WebGL2 capability probe.
///
/// Called ONCE by `ShaderController.load()` on web to pick a stable mode for
/// the whole session — no timer race, no mid-session flip (which churns the
/// platform view and corrupts CanvasKit's rendering surface).
///
/// Creates a throwaway offscreen `<canvas>`, requests a `webgl2` context, and
/// actually compiles + links the trivial vertex/fragment program to be sure
/// the GPU pipeline really works (not just context creation). Returns `true`
/// only if everything succeeds. Any failure → `false` → ColorFilter mode.
///
/// The offscreen canvas is never attached to the DOM, so it has no rendering
/// or input side-effects.
bool probeWebGl2Supported() {
  try {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    final rawCtx = canvas.getContext('webgl2');
    if (rawCtx == null) return false;
    final gl = _GL(rawCtx);

    // Compile the same shaders the overlay uses — a real end-to-end check.
    final vert = _probeCompile(gl, 0x8B31 /* VERTEX_SHADER */, _vertexSrc);
    final frag = _probeCompile(gl, 0x8B30 /* FRAGMENT_SHADER */, _fragmentSrc);
    if (vert == null || frag == null) return false;

    final prog = _call(gl, 'createProgram', []) as JSObject?;
    if (prog == null) return false;
    _call(gl, 'attachShader', [prog, vert]);
    _call(gl, 'attachShader', [prog, frag]);
    _call(gl, 'linkProgram', [prog]);
    final linked =
        (_call(gl, 'getProgramParameter', [prog, 0x8B82.toJS]) as JSBoolean?)
                ?.toDart ??
            false;
    return linked;
  } on Object {
    return false;
  }
}

JSObject? _probeCompile(_GL gl, int type, String src) {
  final shader = _call(gl, 'createShader', [type.toJS]) as JSObject?;
  if (shader == null) return null;
  _call(gl, 'shaderSource', [shader, src.toJS]);
  _call(gl, 'compileShader', [shader]);
  final ok =
      (_call(gl, 'getShaderParameter', [shader, 0x8B81.toJS]) as JSBoolean?)
              ?.toDart ??
          false;
  return ok ? shader : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// WebGlShaderView
// ─────────────────────────────────────────────────────────────────────────────

/// Flutter widget that renders a WebGL2 glitch overlay via [HtmlElementView].
///
/// The overlay canvas is transparent and positioned above the Flutter game
/// canvas. It does NOT intercept pointer events (`pointer-events: none`).
///
/// [failed] is set to `true` if WebGL2 context creation, shader compilation,
/// or rendering fails. ShaderController polls this flag to fall back to
/// the ColorFilterFallback path.
class WebGlShaderView extends StatefulWidget {
  const WebGlShaderView({
    required this.intensity,
    super.key,
  });

  /// Current effect intensity (0.0–1.0). Drives the `uIntensity` uniform.
  final double intensity;

  /// Whether WebGL2 initialisation failed on this device/browser (T-06-02/03).
  ///
  /// Set to `true` by the state on context loss or compilation error.
  /// ShaderController reads this after the 500ms timeout to decide whether
  /// to fall back to ColorFilter mode.
  static bool failed = false;

  @override
  State<WebGlShaderView> createState() => _WebGlShaderViewState();
}

class _WebGlShaderViewState extends State<WebGlShaderView> {
  static const String _viewType = 'desync-webgl';

  /// Ensures the platform-view factory is only registered once per app run.
  static bool _factoryRegistered = false;

  // WebGL rendering state (initialised in the platform-view factory callback).
  _GL? _gl;
  JSObject? _program;
  JSObject? _uIntensityLoc;
  JSObject? _uTimeLoc;
  JSObject? _uResolutionLoc;
  web.HTMLCanvasElement? _canvas;
  bool _rafRunning = false;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _registerFactory();
  }

  void _registerFactory() {
    if (_factoryRegistered) return;
    _factoryRegistered = true;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      _buildCanvas,
    );
  }

  /// Platform-view factory callback — called once when HtmlElementView mounts.
  web.Element _buildCanvas(int viewId) {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;

    // ── CSS: transparent overlay, above Flutter canvas, no pointer capture ──
    canvas.style
      ..position = 'absolute'
      ..top = '0'
      ..left = '0'
      ..width = '100%'
      ..height = '100%'
      ..pointerEvents = 'none' // T-06-01: input passes through
      ..zIndex = '10'
      ..background = 'transparent';

    try {
      final rawCtx = canvas.getContext('webgl2');
      if (rawCtx == null) {
        WebGlShaderView.failed = true;
        return canvas;
      }
      final gl = _GL(rawCtx);

      final prog = _buildProgram(gl);
      if (prog == null) {
        WebGlShaderView.failed = true;
        return canvas;
      }

      _gl = gl;
      _program = prog;
      _canvas = canvas;

      _uIntensityLoc =
          _call(gl, 'getUniformLocation', [prog, 'uIntensity'.toJS])
              as JSObject?;
      _uTimeLoc =
          _call(gl, 'getUniformLocation', [prog, 'uTime'.toJS]) as JSObject?;
      _uResolutionLoc =
          _call(gl, 'getUniformLocation', [prog, 'uResolution'.toJS])
              as JSObject?;

      _uploadQuad(gl, prog);

      // T-06-02: handle context loss gracefully.
      canvas.addEventListener(
        'webglcontextlost',
        ((web.Event event) {
          WebGlShaderView.failed = true;
          _rafRunning = false;
        }).toJS,
      );

      _rafRunning = true;
      _scheduleRaf();
    } on Object catch (e) {
      debugPrint('[WebGlShaderView] WebGL2 init failed: $e');
      WebGlShaderView.failed = true;
    }

    return canvas;
  }

  // ── Shader compilation ───────────────────────────────────────────────────

  JSObject? _compileShader(_GL gl, int type, String src) {
    final shader = _call(gl, 'createShader', [type.toJS]) as JSObject?;
    if (shader == null) return null;
    _call(gl, 'shaderSource', [shader, src.toJS]);
    _call(gl, 'compileShader', [shader]);
    final ok =
        (_call(gl, 'getShaderParameter', [shader, 0x8B81.toJS]) as JSBoolean?)
                ?.toDart ??
            false;
    if (!ok) return null;
    return shader;
  }

  JSObject? _buildProgram(_GL gl) {
    const vertType = 0x8B31; // VERTEX_SHADER
    const fragType = 0x8B30; // FRAGMENT_SHADER

    final vert = _compileShader(gl, vertType, _vertexSrc);
    final frag = _compileShader(gl, fragType, _fragmentSrc);
    if (vert == null || frag == null) return null;

    final prog = _call(gl, 'createProgram', []) as JSObject?;
    if (prog == null) return null;

    _call(gl, 'attachShader', [prog, vert]);
    _call(gl, 'attachShader', [prog, frag]);
    _call(gl, 'linkProgram', [prog]);

    final ok =
        (_call(gl, 'getProgramParameter', [prog, 0x8B82.toJS]) as JSBoolean?)
                ?.toDart ??
            false;
    if (!ok) return null;
    return prog;
  }

  void _uploadQuad(_GL gl, JSObject prog) {
    // Two triangles (TRIANGLE_STRIP) covering NDC [-1, 1].
    // WebGL bufferData needs a typed array (Float32Array), NOT a plain JS
    // Array — pass a Float32List converted via toJS.
    final vertices = Float32List.fromList(
      const [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
    );
    final buf = _call(gl, 'createBuffer', []) as JSObject?;
    if (buf == null) return;
    _call(gl, 'bindBuffer', [0x8892.toJS /* ARRAY_BUFFER */, buf]);
    _call(gl, 'bufferData', [
      0x8892.toJS /* ARRAY_BUFFER */,
      vertices.toJS,
      0x88B8.toJS, // STATIC_DRAW
    ]);
    _call(gl, 'useProgram', [prog]);
    final posLoc =
        (_call(gl, 'getAttribLocation', [prog, 'aPosition'.toJS]) as JSNumber?)
            ?.toDartInt;
    if (posLoc == null) return;
    _call(gl, 'enableVertexAttribArray', [posLoc.toJS]);
    _call(gl, 'vertexAttribPointer', [
      posLoc.toJS,
      2.toJS,
      0x1406.toJS, // FLOAT
      false.toJS,
      0.toJS,
      0.toJS,
    ]);
  }

  // ── Render loop ──────────────────────────────────────────────────────────

  void _scheduleRaf() {
    if (!_rafRunning) return;
    web.window.requestAnimationFrame(
      ((JSNumber ts) {
        _elapsed += 1.0 / 60.0;
        _drawFrame();
        _scheduleRaf();
      }).toJS,
    );
  }

  void _drawFrame() {
    final gl = _gl;
    final canvas = _canvas;
    final prog = _program;
    if (gl == null || canvas == null || prog == null) return;
    if (WebGlShaderView.failed) {
      _rafRunning = false;
      return;
    }

    final w = canvas.clientWidth;
    final h = canvas.clientHeight;
    if (w <= 0 || h <= 0) return;

    // Resize backing buffer to match CSS size (handles window resizes).
    if (canvas.width != w) canvas.width = w;
    if (canvas.height != h) canvas.height = h;

    _call(gl, 'viewport', [0.toJS, 0.toJS, w.toJS, h.toJS]);
    _call(gl, 'clearColor', [0.0.toJS, 0.0.toJS, 0.0.toJS, 0.0.toJS]);
    _call(gl, 'clear', [0x4000.toJS]); // COLOR_BUFFER_BIT

    // Premultiplied-alpha blending: ONE / ONE_MINUS_SRC_ALPHA. The shader
    // outputs vec4(color * alpha, alpha) (premultiplied), so ONE as the source
    // factor avoids double-multiplying by alpha — the overlay reads at its
    // intended strength instead of being washed out.
    _call(gl, 'enable', [0x0BE2.toJS]); // BLEND
    // ONE = 0x0001, ONE_MINUS_SRC_ALPHA = 0x0303
    _call(gl, 'blendFunc', [0x0001.toJS, 0x0303.toJS]);

    _call(gl, 'useProgram', [prog]);

    _uniform1f(gl, _uIntensityLoc, widget.intensity);
    _uniform1f(gl, _uTimeLoc, _elapsed);
    _uniform2f(gl, _uResolutionLoc, w.toDouble(), h.toDouble());

    // TRIANGLE_STRIP = 0x0005, draw 4 vertices.
    _call(gl, 'drawArrays', [0x0005.toJS, 0.toJS, 4.toJS]);
  }

  void _uniform1f(_GL gl, JSObject? loc, double v) {
    if (loc == null) return;
    _call(gl, 'uniform1f', [loc, v.toJS]);
  }

  void _uniform2f(_GL gl, JSObject? loc, double x, double y) {
    if (loc == null) return;
    _call(gl, 'uniform2f', [loc, x.toJS, y.toJS]);
  }

  @override
  Widget build(BuildContext context) {
    return const HtmlElementView(viewType: _viewType);
  }

  @override
  void dispose() {
    _rafRunning = false;
    super.dispose();
  }
}
