import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:achrona_engine/src/game/player_component.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

/// A collectible fragment that scrolls left with the world.
///
/// Rendered as a [SpriteComponent] using fragment.png (48×48).
/// When the [PlayerComponent] passes through it, the fragment is collected and
/// removed from the game tree.
class FragmentComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<AchronaGame> {
  FragmentComponent({required super.position}) : super(size: Vector2(54, 54));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
    final sprite = await game.loadSprite('fragment.png');
    add(SpriteComponent(sprite: sprite, size: size));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= game.currentScrollSpeed * dt;
    // Remove once off-screen left.
    if (position.x < -size.x - 10) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerComponent) {
      game.fragmentManager.collect();
      removeFromParent();
    }
  }
}
