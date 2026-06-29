import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:achrona_engine/src/game/player_component.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/rendering.dart';

/// A gun powerup pickup. Scrolls in from the right; on contact it arms the
/// player's gun for [armSeconds]. Rendered procedurally as a neon bolt icon
/// (abstract FX — no art asset needed).
class GunPickupComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<AchronaGame> {
  GunPickupComponent({required super.position, this.armSeconds = 7})
      : super(size: Vector2(52, 52));

  final double armSeconds;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= game.currentScrollSpeed * dt;
    if (position.x < -size.x - 10) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final w = size.x;
    final h = size.y;
    final c = Offset(w / 2, h / 2);
    canvas
      ..drawCircle(
        c,
        w * 0.5,
        Paint()
          ..color = const Color(0x66FF3CE6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawCircle(c, w * 0.36, Paint()..color = const Color(0xFF2A0A52))
      ..drawCircle(
        c,
        w * 0.36,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFF6BFF),
      );
    final bolt = Path()
      ..moveTo(w * 0.56, h * 0.22)
      ..lineTo(w * 0.40, h * 0.52)
      ..lineTo(w * 0.52, h * 0.52)
      ..lineTo(w * 0.45, h * 0.80)
      ..lineTo(w * 0.66, h * 0.44)
      ..lineTo(w * 0.51, h * 0.44)
      ..close();
    canvas.drawPath(bolt, Paint()..color = const Color(0xFF39E6FF));
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerComponent) {
      other.armGun(armSeconds);
      removeFromParent();
    }
  }
}
