import 'dart:ui' as ui;

import 'package:achrona_engine/src/fx/color_filter_fallback.dart';
import 'package:achrona_engine/src/fx/web_gl_shader_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Web-mode selector for [ShaderController] on Flutter web builds.
enum _WebMode {
  /// WebGL2 overlay is active.
  webgl,

  /// WebGL2 unsupported — using the additive [ColorFilterFallback] overlay.
  colorFilter,

  /// Not web — native shader path, or web with no effect active.
  none,
}

/// Manages the desync glitch effect across native and web builds.
///
/// ### Native builds (iOS, Android, macOS, Windows, Linux)
/// Loads `shaders/desync.frag` via [ui.FragmentProgram.fromAsset] and
/// composites it as a full-screen post-pass over the game canvas.
/// [wrapWithEffect] returns the child unchanged (the shader is applied at
/// canvas level via [applyToCanvas]).
///
/// ### Web builds ([kIsWeb] == true)
/// [ui.FragmentProgram] is broken on CanvasKit/skwasm (flutter/flutter#114121).
/// Instead, [load] runs a SYNCHRONOUS one-shot WebGL2 capability probe
/// ([probeWebGl2Supported]) and picks ONE stable mode for the whole session —
/// no timer race, no mid-session flip. A mid-session flip would mount/unmount
/// the WebGL [HtmlElementView] platform view, which corrupts CanvasKit's web
/// rendering surface (blank/purple screen on cold loads — the D-18 regression
/// this design avoids).
///
/// [wrapWithEffect] always renders the game as the clean base layer of a
/// [Stack] and only adds the effect ON TOP, so Rung-1 (D-18) is guaranteed:
/// - `_WebMode.webgl` → `Stack([child, WebGlShaderView(intensity)])`
/// - `_WebMode.colorFilter` → `Stack([child, ColorFilterFallback(intensity)])`
///   (an additive overlay — NEVER a `ColorFiltered` wrap around the game)
/// - `_WebMode.none` (native) → `child` unchanged
///
/// ### Threat mitigations
/// T-06-01: WebGL canvas is `pointer-events: none`; the fallback overlay is
///   wrapped in `IgnorePointer`.
/// T-06-02: WebGL context loss → [WebGlShaderView.failed]; handled without
///   remounting churn (the base game keeps rendering regardless).
/// T-05-03: Native [load] catches all exceptions; degrades to no-op.
class ShaderController {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  double _intensity = 0;
  double _time = 0;

  _WebMode _webMode = _WebMode.none;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Whether the native shader loaded successfully and is ready to paint.
  ///
  /// Always `false` on web (shader is applied via [wrapWithEffect] instead).
  bool get isReady => !kIsWeb && _shader != null;

  /// Load the shader.
  ///
  /// **Native:** loads `shaders/desync.frag` via [ui.FragmentProgram.fromAsset].
  /// Exceptions are caught and logged — the controller degrades to a no-op
  /// (T-05-03).
  ///
  /// **Web:** runs a synchronous WebGL2 capability probe ONCE and locks in a
  /// stable mode ([_WebMode.webgl] or [_WebMode.colorFilter]) for the whole
  /// session. No timer, no mid-session flip.
  Future<void> load() async {
    if (kIsWeb) {
      _initWebMode();
      return;
    }
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'packages/achrona_engine/shaders/desync.frag',
      );
      _shader = _program!.fragmentShader();
    } on Exception catch (e) {
      // Degraded gracefully — shader pass is skipped for the run.
      debugPrint('[ShaderController] Shader load failed (T-05-03): $e');
    }
  }

  /// Update the effect intensity (0.0–1.0).
  ///
  /// Driven each frame by `max(waveProximity, zoneIntensity)` (D-16).
  void setIntensity(double value) {
    _intensity = value.clamp(0.0, 1.0);
  }

  /// Update the time uniform (elapsed seconds) for animation.
  // ignore: use_setters_to_change_properties — matches ShaderController API contract
  void setTime(double elapsedSeconds) {
    _time = elapsedSeconds;
  }

  /// Composite the native shader over [frameImage] onto [canvas].
  ///
  /// [size] must be the logical viewport size in pixels.
  /// On web or when [isReady] is false, this is a no-op.
  void applyToCanvas(ui.Canvas canvas, ui.Size size, ui.Image frameImage) {
    if (!isReady) return;

    // Uniform layout must match desync.frag (declaration order):
    //   0: float intensity
    //   1: float time
    //   2,3: vec2 uResolution (width, height)
    //   sampler 0: uScene
    _shader!
      ..setFloat(0, _intensity)
      ..setFloat(1, _time)
      ..setFloat(2, size.width)
      ..setFloat(3, size.height)
      ..setImageSampler(0, frameImage);

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
      ui.Paint()..shader = _shader,
    );
  }

  /// Wraps [child] with the active glitch effect for the current platform.
  ///
  /// Call this from the `GamePage` widget to surround the game surface:
  /// ```dart
  /// shaderController.wrapWithEffect(
  ///   child: GameWidget(game: game),
  ///   intensity: currentIntensity,
  /// )
  /// ```
  ///
  /// Return values by mode (the game is ALWAYS the clean base layer):
  /// - **native / none:** returns [child] unchanged (shader applied at canvas
  ///   level via [applyToCanvas]).
  /// - **webgl:** `Stack([child, Positioned.fill(WebGlShaderView(intensity))])`
  ///   — the transparent WebGL canvas overlays the game.
  /// - **colorFilter:** `Stack([child, Positioned.fill(ColorFilterFallback(
  ///   intensity))])` — an ADDITIVE overlay on top of the game; it never wraps
  ///   or filters the game, so the base game + HUD always render (D-18).
  ///
  /// The mode is fixed for the whole session (chosen synchronously in [load]),
  /// so the platform view is never mounted/unmounted mid-session.
  Widget wrapWithEffect({required Widget child, required double intensity}) {
    if (!kIsWeb) {
      // Native: shader is applied at canvas level — just return child.
      return child;
    }

    switch (_webMode) {
      case _WebMode.webgl:
        // StackFit.expand gives the non-positioned base child (the game) tight
        // full-size constraints so the GameWidget fills the viewport.
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: WebGlShaderView(intensity: intensity),
            ),
          ],
        );

      case _WebMode.colorFilter:
        // Additive overlay — game stays the clean base layer (D-18).
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: ColorFilterFallback(intensity: intensity),
            ),
          ],
        );

      case _WebMode.none:
        // Web with mode explicitly cleared (shouldn't happen in normal flow).
        return child;
    }
  }

  /// Release GPU resources.
  void dispose() {
    _shader?.dispose();
    _program = null;
    _shader = null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _initWebMode() {
    // Reset failure flag from any previous game session.
    WebGlShaderView.failed = false;

    // ALWAYS use the pure-Flutter ColorFilter overlay on web (ISSUE 2).
    //
    // The WebGL2 HtmlElementView path renders correctly (canvas sized, render
    // loop active) but does NOT reliably composite ABOVE the CanvasKit game
    // layer on Flutter web — a platform-view z-order limitation. The user
    // never sees it. The plan explicitly allows "WebGL2 overlay OR a
    // ColorFilter approximation" for SHDR-02, so we force the Flutter-overlay
    // mode, which CanvasKit reliably paints on top of the GameWidget.
    //
    // The WebGL code remains in the repo (probeWebGl2Supported / WebGlShaderView)
    // as evidence for the Phase 5 Architecture-B web-shader fidelity gate, but
    // is no longer used for the on-screen effect.
    _webMode = _WebMode.colorFilter;
    debugPrint(
      '[ShaderController] Web shader mode locked: Flutter ColorFilter overlay '
      '(WebGL2 platform view does not composite above CanvasKit — ISSUE 2).',
    );
  }
}
