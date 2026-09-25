import 'package:flame/components.dart';

import 'physics.dart';
import 'tile_grid.dart';

/// Thin Flame wrapper around [PlayerPhysics]. Holds a fixed-timestep accumulator
/// so the deterministic 60Hz sim is independent of the render frame rate. Set
/// [intent] each frame from your input handler; read [physics.pose] for sprites.
class PlatformerPlayer extends PositionComponent {
  PlatformerPlayer({required this.physics, required this.grid})
      : super(
          position: Vector2(physics.x, physics.y),
          size: Vector2(physics.width, physics.height),
        );

  final PlayerPhysics physics;
  TileGrid grid;
  PlayerIntent intent = const PlayerIntent();

  static const double _step = 1 / 60;
  double _acc = 0;

  @override
  void update(double dt) {
    _acc += dt;
    if (_acc > 0.25) _acc = 0.25; // avoid spiral of death after a stall
    while (_acc >= _step) {
      physics.step(intent, grid);
      intent = intent.consumePressed(); // edge-trigger jump once per press
      _acc -= _step;
    }
    position.setValues(physics.x, physics.y);
  }
}
