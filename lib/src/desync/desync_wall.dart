import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/rendering.dart';

// ignore_for_file: cascade_invocations — render() interleaves many canvas draw
// calls with local paint setup; cascading them all would hurt readability.

/// The Desync corruption wall that chases the player from the left edge.
///
/// This is the single fail state (D-04). When it reaches the player the run
/// ends. Speed is read from [AchronaGame.currentDesyncSpeed] each frame so
/// the difficulty ramp (D-02) is centrally owned by the game class.
///
/// Rendered as an animated wall of corruption — a dark body that brightens
/// into a glowing, glitching leading edge (the side facing the fleeing
/// player), with energy streaks, drifting scanlines, glitch tears, a
/// chromatic fringe, and a glow halo bleeding toward the player. Painted in
/// the component's local space via [render]; the [RectangleHitbox] still drives
/// collision.
class DesyncWall extends PositionComponent
    with CollisionCallbacks, HasGameReference<AchronaGame> {
  DesyncWall({super.position, super.size}) : super(priority: kPriority);

  /// Render priority for the corruption wall. Kept high so the wall renders
  /// ON TOP of every in-world game object (hero, hazards, fragments — all
  /// default priority 0). The wall is very wide and its consumed region is
  /// opaque, so a top z-order makes it visually swallow everything the player
  /// has already passed (anything left of the leading edge), instead of
  /// letting later-spawned hazards/fragments draw over the corruption.
  static const int kPriority = 100;

  // Keep in sync with AchronaGame._wallStartX — the wall is very wide so the
  // consumed corruption fills everything behind the leading edge; its trailing
  // edge stays off-screen all run. The leading edge starts just inside the left
  // screen edge (a sliver always visible) and the wall never recovers past this
  // (clamp in update). Used by reset() on stumble/restart.
  static const double _startX = -1240;

  double _t = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    // currentDesyncSpeed is SIGNED: positive closes on the player, negative
    // recedes (clean-streak recovery). Never recover past the start gap.
    position.x += game.currentDesyncSpeed * dt;
    if (position.x < _startX) position.x = _startX;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final t = _t;
    // Erratic flicker (two detuned sines) — the signal is unstable.
    final flicker =
        (0.72 + 0.28 * math.sin(t * 31) * math.sin(t * 7.3)).clamp(0.0, 1.0);

    // Animated wavy leading-edge contour — the corruption front undulates.
    // Two detuned sines give an organic, non-repeating wobble. Amplitude is
    // small (~10px) so the visual front reads as churning without diverging
    // from the (straight) collision hitbox at x = w. The TOP of the line curls
    // FORWARD (+x, toward the fleeing player) over the upper ~30% so the wall
    // leans/breaks over the runner instead of standing dead vertical.
    double edgeX(double y) {
      final base = w +
          4.0 * math.sin(y * 0.026 + t * 2.4) +
          1.8 * math.sin(y * 0.070 - t * 4.0);
      final u = (y / h).clamp(0.0, 1.0); // 0 at top .. 1 at the ground
      final topCurl = (1 - u / 0.30).clamp(0.0, 1.0); // 1 at top -> 0 by 30%
      // Eased so the curl is strongest at the crest and blends out smoothly.
      return base + topCurl * topCurl * (h * 0.16);
    }

    // Body shape: a huge rectangle to the left, closed off by the wavy front on
    // the right, so the corruption fill follows the undulating edge.
    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(0, h);
    for (var y = h; y >= 0; y -= 6) {
      body.lineTo(edgeX(y), y);
    }
    body.close();

    // ── Consumed corruption field: saturated violet, deepening into the
    //    distance (left), intensifying to the wavy front (right). ──
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          const [Color(0xE62A0A52), Color(0xF0431094), Color(0xFF7E22D6)],
          const [0.0, 0.62, 1.0],
        ),
    );

    // Clip internal glitch to the wavy body so nothing spills past the front.
    canvas
      ..save()
      ..clipPath(body);

    // ── Energy streaks across the whole field (additive, flicker) ──
    final streak = Paint()..blendMode = BlendMode.plus;
    for (var k = 0; k < 22; k++) {
      final sx = _hash(k * 13) * w;
      final phase = 0.5 + 0.5 * math.sin(t * (4 + (k % 7)) + k);
      final a = ((0.04 + 0.11 * phase) * flicker).clamp(0.0, 0.20);
      streak.color = Color.fromRGBO(225, 130, 255, a);
      canvas.drawRect(
        Rect.fromLTWH(sx, 0, 1.0 + _hash(k * 7) * 2.0, h),
        streak,
      );
    }

    // ── Drifting scanlines across the field (signal texture) ──
    final scan = Paint()..color = const Color(0x39000000);
    final off = (t * 40) % 4;
    for (var y = -off; y < h; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, w + 16, 1), scan);
    }

    // ── Glitch tears sweeping the whole field (horizontal, jumping ~12×/s) ──
    final tearSeed = (t * 12).floor();
    final tear = Paint()..blendMode = BlendMode.plus;
    for (var k = 0; k < 6; k++) {
      if (_hash(tearSeed + k * 17) < 0.5) continue;
      final ty = _hash(tearSeed * 5 + k) * h;
      final th = 1.0 + _hash(tearSeed * 9 + k) * 3;
      tear.color = Color.fromRGBO(255, 235, 255, 0.4 * flicker);
      canvas.drawRect(Rect.fromLTWH(0, ty, w + 16, th), tear);
    }

    canvas.restore();

    // ── Wavy leading edge: glow halo + chromatic fringe + bright edge line,
    //    all stroked along the animated contour so the front undulates. ──
    final edge = Path();
    for (var y = 0.0; y <= h; y += 6) {
      final x = edgeX(y);
      y == 0 ? edge.moveTo(x, y) : edge.lineTo(x, y);
    }

    canvas
      // glow halo (wide, blurred — bleeds toward the player)
      ..drawPath(
        edge,
        Paint()
          ..color = Color.fromRGBO(255, 70, 230, 0.4 * flicker)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
      )
      // chromatic fringe (offset copies, additive)
      ..drawPath(
        edge.shift(const Offset(-4.5, 0)),
        Paint()
          ..color = const Color(0x772BE2FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..blendMode = BlendMode.plus,
      )
      ..drawPath(
        edge.shift(const Offset(-1.8, 0)),
        Paint()
          ..color = const Color(0x99FF2E97)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..blendMode = BlendMode.plus,
      )
      // bright event-horizon line
      ..drawPath(
        edge,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFFF6BFF),
            const Color(0xFFFFFFFF),
            0.5 * flicker,
          )!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
  }

  /// Closes the gap toward the player — called on player stumble (D-03).
  void closeGap(double amount) {
    position.x += amount;
  }

  /// Resets the wall to its starting position and ensures it is off-screen.
  // ignore: use_setters_to_change_properties
  void reset({double startX = _startX}) {
    position.x = startX;
  }

  static double _hash(int n) {
    final x = math.sin(n * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }
}
