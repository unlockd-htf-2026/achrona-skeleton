// web_gl_shader_view.dart — Public API for the WebGL2 glitch overlay.
//
// Uses a conditional import to select the correct implementation:
//   - On Flutter web: web_gl_shader_view_web.dart
//     (real WebGL2 + HtmlElementView)
//   - On native builds: web_gl_shader_view_stub.dart (no-op stub)
//
// This file exports [WebGlShaderView] to the rest of the engine package.
// Callers only import this file; they never import the _web or _stub variants
// directly.
//
// T-06-01: The web canvas is styled `pointer-events: none` — ensured by the
// web implementation.
// T-06-02/03: On WebGL context loss or init failure, [WebGlShaderView.failed]
// is set to `true`; ShaderController switches to ColorFilter fallback.

export 'web_gl_shader_view_stub.dart'
    if (dart.library.js_interop) 'web_gl_shader_view_web.dart';
