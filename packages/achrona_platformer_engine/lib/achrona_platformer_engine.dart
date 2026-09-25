/// Metroid-style platformer engine for Achrona.
///
/// Movement is ported from the Metroid: Zero Mission decomp (feel/numbers only,
/// no code) and runs as a deterministic pure-Dart fixed-step sim, wrapped for
/// Flame. See `src/physics.dart` for the GBA → px/frame derivation.
library;

export 'src/cutscene_player.dart';
export 'src/physics.dart';
export 'src/player_component.dart';
export 'src/tile_grid.dart';
export 'src/tiled_tile_grid.dart';
