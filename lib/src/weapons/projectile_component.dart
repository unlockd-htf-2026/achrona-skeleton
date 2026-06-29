import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:achrona_engine/src/hazards/hazard_component.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/rendering.dart';

/// A player-fired bolt (gun powerup). Travels right and destroys the first
/// hazard it hits, then removes itself. Rendered procedurally as a neon bolt
/// (abstract FX — no art asset needed).
class ProjectileComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<AchronaGame> {
  ProjectileComponent({required super.position}) : super(size: Vector2(34, 12));

  static const double _speed = 800;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x += _speed * dt;
    if (position.x > game.worldWidth + 80) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final r = RRect.fromRectAndRadius(
      Offset.zero & size.toSize(),
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(
        r,
        Paint()
          ..color = const Color(0x8839E6FF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawRRect(r, Paint()..color = const Color(0xFFBDF3FF));
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is HazardComponent) {
      other.onHitByPlayer(); // destroys the hazard
      removeFromParent();
    }
  }
}
