// color_filter_fallback.dart — pure-Flutter "Desync" glitch overlay (web).
//
// This is the PRIMARY web glitch effect (SHDR-02). The WebGL2 HtmlElementView
// path renders but does not reliably composite above the CanvasKit game layer
// on Flutter web (platform-view z-order limitation), so the on-screen effect
// is this CanvasKit-native overlay, which composites reliably.
//
// Two complementary layers:
//   1. REAL distortion of the game via `BackdropFilter` — `FragmentProgram` is
//      broken on Flutter web, but `ImageFilter` (blur + matrix) works, so we
//      sample and DISPLACE the live game pixels: a subtle signal blur plus
//      horizontal "tear" bands that shift the content sideways (datamosh/VHS).
//   2. An additive CRT layer (CustomPaint): scanlines, jittery RGB ghosting,
//      TV-static noise grain, a rolling scan bar, a corruption colour wash, and
//      a vignette — all translucent, painted ON TOP.
//
// RUNG-1 (D-18) — CRITICAL: this is an OVERLAY only. The clean GameWidget is a
// separate Stack sibling underneath (see ShaderController.wrapWithEffect); this
// overlay only blurs/displaces/tints what it samples and can never blank the
// base game. Wrapped in IgnorePointer so input always passes through.
//
// Self-animates via a Ticker. Intensity comes from the game's intensityNotifier
// (subtle baseline, steep ramp as the Desync wall closes in).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// An animated "Desync" glitch overlay. Render ON TOP of the game in a [Stack]
/// (it does not take a child). [intensity] is clamped to `[0.0, 1.0]`.
class ColorFilterFallback extends StatefulWidget {
  const ColorFilterFallback({required this.intensity, super.key});

  /// Effect intensity in the range [0.0, 1.0].
  final double intensity;

  @override
  State<ColorFilterFallback> createState() => _ColorFilterFallbackState();
}

class _ColorFilterFallbackState extends State<ColorFilterFallback>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _time = elapsed.inMicroseconds / 1e6);
    });
    // ignore: discarded_futures — TickerFuture only completes on stop.
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.intensity.clamp(0.0, 1.0);
    if (i <= 0.001) return const SizedBox.expand();

    // Real signal blur — grows with intensity (quadratic so it stays clean
    // until the wall is near). Asymmetric so it smears slightly horizontally.
    final blurSigma = i * i * 1.7;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              // ── 1a. REAL signal blur over the whole frame ──
              if (blurSigma > 0.06)
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma * 0.35,
                  ),
                  child: const SizedBox.expand(),
                ),

              // ── 1b. REAL horizontal tear bands (displace game pixels) ──
              ..._tearBands(size, i, _time),

              // ── 2. Additive CRT layer ──
              CustomPaint(
                painter: _GlitchOverlayPainter(intensity: i, time: _time),
                size: size,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Horizontal bands that sample the game behind them and shift it sideways,
  /// producing real tearing. Absent when calm; a few near the wall.
  List<Widget> _tearBands(Size size, double intensity, double time) {
    if (intensity < 0.32 || size.isEmpty) return const [];
    final count = ((intensity - 0.32) * 9).floor().clamp(0, 5);
    if (count == 0) return const [];

    // Update tears ~14×/s so they jump (digital), not drift (analogue).
    final step = (time * 14).floor();
    final bands = <Widget>[];
    for (var k = 0; k < count; k++) {
      final ry = _hash(step * 7 + k * 53);
      final rh = _hash(step * 13 + k * 17);
      final rd = _hash(step * 23 + k * 31) - 0.5;
      final y = ry * size.height;
      final h = (6 + rh * 26) * (0.6 + intensity);
      final dx = rd * (14 + 46 * intensity); // sideways shift in px
      bands.add(
        Positioned(
          left: 0,
          right: 0,
          top: y.clamp(0.0, size.height - h),
          height: h,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.matrix(_translateX(dx)),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }
    return bands;
  }

  /// Column-major 4×4 translation matrix (dx, 0) for [ui.ImageFilter.matrix].
  static Float64List _translateX(double dx) => Float64List.fromList(
        <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, dx, 0, 0, 1],
      );

  static double _hash(int n) {
    final x = math.sin(n * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }
}

/// Additive CRT layer: scanlines + RGB ghosting + noise grain + rolling scan
/// bar + corruption wash + vignette. Translucent so the game shows through;
/// every element scales from faint at baseline → heavy near max.
class _GlitchOverlayPainter extends CustomPainter {
  const _GlitchOverlayPainter({required this.intensity, required this.time});

  final double intensity;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.001 || size.isEmpty) return;
    final i = intensity;
    final rect = Offset.zero & size;

    // ── Corruption colour wash: teal→magenta, pulsing. Faint at baseline. ──
    final pulse = 0.85 + 0.15 * math.sin(time * 6);
    final washA = (0.015 + i * 0.20).clamp(0.0, 0.22) * pulse;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(40, 230, 220, washA),
            Color.fromRGBO(190, 40, 230, washA),
          ],
        ).createShader(rect),
    );

    // ── RGB ghosting: full-width red/cyan copies offset horizontally, with a
    // few jittering bands and the odd big "jump". Additive (plus) blend. ──
    final ghostA = (0.02 + i * 0.22).clamp(0.0, 0.26);
    final baseSplit = 1.0 + 26.0 * i;
    final red = Paint()
      ..color = Color.fromRGBO(255, 45, 70, ghostA)
      ..blendMode = BlendMode.plus;
    final cyan = Paint()
      ..color = Color.fromRGBO(45, 235, 255, ghostA)
      ..blendMode = BlendMode.plus;
    canvas
      ..drawRect(rect.shift(Offset(baseSplit, 0)), red)
      ..drawRect(rect.shift(Offset(-baseSplit, 0)), cyan);
    final bands = 4 + (i * 7).floor();
    final bandH = size.height / bands;
    for (var b = 0; b < bands; b++) {
      var off = math.sin(time * 4 + b * 1.9) * baseSplit;
      // Occasional violent jump on a band.
      if (_hash((time * 9).floor() * 5 + b) > 0.86) off *= 4;
      final y = b * bandH;
      canvas
        ..drawRect(Rect.fromLTWH(off, y, size.width, bandH * 0.5), red)
        ..drawRect(
          Rect.fromLTWH(-off, y + bandH * 0.5, size.width, bandH * 0.5),
          cyan,
        );
    }

    // ── Scanlines: faint+sparse when calm → dark+dense near max. ──
    final scanA = (0.05 + i * 0.34).clamp(0.0, 0.40);
    final scanStep = 4.0 - 2.0 * i;
    final scan = Paint()
      ..color = Color.fromRGBO(0, 0, 0, scanA)
      ..strokeWidth = 1 + i;
    for (double y = 0; y < size.height; y += scanStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
    }

    // ── Rolling CRT scan bar: a soft bright band sweeping downward. ──
    final barH = size.height * 0.16;
    final barY = ((time * 90) % (size.height + barH)) - barH;
    canvas.drawRect(
      Rect.fromLTWH(0, barY, size.width, barH),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(0, barY),
          Offset(0, barY + barH),
          [
            const Color(0x00FFFFFF),
            Color.fromRGBO(180, 210, 255, 0.05 + i * 0.06),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // ── TV-static noise grain: scattered faint points, more near max. ──
    final grainCount = (40 + i * 220).floor();
    final seed = (time * 24).floor();
    final grain = Paint()
      ..blendMode = BlendMode.plus
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final pts = <Offset>[];
    for (var n = 0; n < grainCount; n++) {
      pts.add(Offset(
        _hash(seed * 3 + n * 7) * size.width,
        _hash(seed * 5 + n * 11) * size.height,
      ),);
    }
    grain.color =
        Color.fromRGBO(220, 220, 255, (0.04 + i * 0.16).clamp(0.0, 0.2));
    canvas.drawPoints(ui.PointMode.points, pts, grain);

    // ── Datamosh blocks: shifting coloured bars, only near the wall. ──
    if (i > 0.4) {
      final blockA = ((i - 0.4) * 0.6).clamp(0.0, 0.34);
      final bseed = (time * 11).floor();
      final n = (i * 5).floor();
      for (var k = 0; k < n; k++) {
        if (_hash(bseed + k * 31) < 1.0 - i * 0.7) continue;
        final by = _hash(bseed * 7 + k) * size.height;
        final bh = (4 + _hash(bseed * 13 + k) * 24) * (0.5 + i);
        final bx = (_hash(bseed * 17 + k) - 0.5) * 60 * i;
        final c = _hash(bseed * 19 + k) > 0.5
            ? Color.fromRGBO(150, 30, 230, blockA)
            : Color.fromRGBO(30, 220, 230, blockA);
        canvas.drawRect(
          Rect.fromLTWH(bx, by, size.width, bh),
          Paint()
            ..color = c
            ..blendMode = BlendMode.plus,
        );
      }
    }

    // ── Vignette: edge darkening that deepens with intensity. ──
    final vigA = (0.10 + i * 0.30).clamp(0.0, 0.42);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.62,
          [
            const Color(0x00000000),
            Color.fromRGBO(20, 0, 35, vigA),
          ],
          const [0.62, 1.0],
        ),
    );
  }

  double _hash(int n) {
    final x = math.sin(n * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(_GlitchOverlayPainter oldDelegate) =>
      oldDelegate.intensity != intensity || oldDelegate.time != time;
}
