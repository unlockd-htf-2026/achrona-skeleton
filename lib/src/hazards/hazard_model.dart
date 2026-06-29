/// Types of hazards that can appear in the world.
enum HazardType {
  /// A spike obstacle on the ground.
  spike,

  /// A glitchy corrupted block.
  glitch,

  /// A tall barrier that blocks the lane.
  barrier,
}

/// Behaviour pattern of a hazard component.
enum Behavior {
  /// Stays in place — the default.
  static,

  /// Drifts leftward faster than the world scroll.
  driftsLeft,

  /// Blinks in and out of existence.
  blinks,

  /// Jumps between lanes unpredictably.
  jumpsLanes,

  /// Speeds up as the run progresses.
  speedsUp,
}

/// Pure-data description of a single hazard.
///
/// Students create instances of this class in `lib/student/hazards.dart`.
/// The engine reads the list and handles all rendering and collision logic.
class Hazard {
  /// Creates a hazard descriptor.
  const Hazard({
    required this.lane,
    required this.type,
    this.height = 1,
    this.behavior = Behavior.static,
  });

  /// Lane index: 0 = left, 1 = centre, 2 = right.
  final int lane;

  /// Visual type of the hazard.
  final HazardType type;

  /// Height of the hazard in lane units (1 = standard, 2 = tall).
  final int height;

  /// Movement behaviour of the hazard.
  final Behavior behavior;
}
