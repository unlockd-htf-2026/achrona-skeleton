import 'dart:math';

import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:achrona_engine/src/game/player_component.dart';
import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

/// A live hazard component spawned from a [Hazard] data record.
///
/// Scrolls leftward at [AchronaGame.currentScrollSpeed] and applies the
/// [Behavior] variant specified by the student (D-07).
///
/// Rendered using a [SpriteComponent] based on [HazardType]:
///   - [HazardType.spike]   → hazard_spike.png (64×64)
///   - [HazardType.glitch]  → hazard_glitch.png (64×64)
///   - [HazardType.barrier] → hazard_barrier.png (64×64)
///
/// Collision with the player is handled by the player component which calls
/// [AchronaGame.onPlayerStumble] — the player is NOT removed (D-03).
/// After being hit the hazard removes itself so it cannot trigger twice.
class HazardComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<AchronaGame>, HasVisibility {
  HazardComponent({
    required this.hazard,
    required double trackCenterY,
    required Vector2 viewportSize,
    required Random rng,
  })  : _viewportSize = viewportSize,
        _rng = rng {
    // Fixed box (independent of the data `height`) sized to read clearly at the
    // bigger sprite scale; dodging is vertical movement around it.
    size = Vector2(70, 70);
    // Spawn off the right edge, centred on the track; scroll left toward the
    // player (whose x is fixed).
    position = Vector2(viewportSize.x + size.x, trackCenterY - size.y / 2);
  }

  /// The data record this component was spawned from.
  final Hazard hazard;

  final Vector2 _viewportSize;
  final Random _rng;

  // Blink state
  double _blinkTimer = 0;
  static const double _blinkInterval = 0.4; // seconds per blink half-cycle

  // JumpsLanes behavior state (now hops between vertical tracks).
  double _laneJumpTimer = 0;
  static const double _laneJumpInterval = 2; // seconds between track jumps

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
    final spriteName = _spriteForType(hazard.type);
    final sprite = await game.loadSprite(spriteName);
    add(SpriteComponent(sprite: sprite, size: size));
  }

  @override
  void update(double dt) {
    super.update(dt);

    final speed = _effectiveSpeed();
    final extraDrift = hazard.behavior == Behavior.driftsLeft ? 40.0 : 0;
    position.x -= (speed + extraDrift) * dt;

    // Remove once off-screen left.
    if (position.x + size.x < 0) {
      removeFromParent();
      return;
    }

    _applyBehaviorEffects(dt);
  }

  double _effectiveSpeed() {
    final base = game.currentScrollSpeed;
    return hazard.behavior == Behavior.speedsUp ? base * 1.5 : base;
  }

  void _applyBehaviorEffects(double dt) {
    switch (hazard.behavior) {
      case Behavior.blinks:
        _blinkTimer += dt;
        if (_blinkTimer >= _blinkInterval) {
          _blinkTimer = 0;
          isVisible = !isVisible;
        }
      case Behavior.jumpsLanes:
        _laneJumpTimer += dt;
        if (_laneJumpTimer >= _laneJumpInterval) {
          _laneJumpTimer = 0;
          _doTrackJump();
        }
      case Behavior.static:
      case Behavior.driftsLeft:
      case Behavior.speedsUp:
        break;
    }
  }

  void _doTrackJump() {
    // Same track centres as the player so a track-jumping hazard lands on a
    // track the player actually occupies. Only y changes (x keeps scrolling).
    final trackPositions = PlayerComponent.trackCenters(_viewportSize.y);
    final newTrack = _rng.nextInt(trackPositions.length);
    position.y = trackPositions[newTrack] - size.y / 2;
  }

  /// Called by the player component when a collision is detected.
  /// Removes this hazard so it cannot trigger stumble more than once.
  void onHitByPlayer() {
    removeFromParent();
  }

  static String _spriteForType(HazardType type) {
    return switch (type) {
      HazardType.spike => 'hazard_spike.png',
      HazardType.glitch => 'hazard_glitch.png',
      HazardType.barrier => 'hazard_barrier.png',
    };
  }
}
