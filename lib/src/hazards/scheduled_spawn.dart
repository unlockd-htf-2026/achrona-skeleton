import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:flutter/foundation.dart' show immutable;

/// Pure-data description of a single scripted hazard spawn at a fixed moment in
/// a run.
///
/// Modeled on [Hazard], but adds a [timeOffset] so a host (the Arcade, the
/// Rung-4 reference game) can drive the engine from an EXPLICIT authored
/// sequence (Path B, D-42) instead of the default random arrangement.
///
/// Like [Hazard], this is declarative data only — it holds no executable code
/// (D-42). The engine reads the ordered list and emits each entry once elapsed
/// run time reaches its [timeOffset].
@immutable
class ScheduledSpawn {
  /// Creates a scripted spawn descriptor.
  const ScheduledSpawn({
    required this.timeOffset,
    required this.lane,
    required this.type,
    this.height = 1,
    this.behavior = Behavior.static,
  });

  /// Seconds from run start at which this hazard appears.
  final double timeOffset;

  /// Lane index: 0 = left, 1 = centre, 2 = right.
  final int lane;

  /// Visual type of the hazard.
  final HazardType type;

  /// Height of the hazard in lane units (1 = standard, 2 = tall).
  final int height;

  /// Movement behaviour of the hazard.
  final Behavior behavior;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledSpawn &&
          runtimeType == other.runtimeType &&
          timeOffset == other.timeOffset &&
          lane == other.lane &&
          type == other.type &&
          height == other.height &&
          behavior == other.behavior;

  @override
  int get hashCode =>
      Object.hash(timeOffset, lane, type, height, behavior);

  @override
  String toString() =>
      'ScheduledSpawn(timeOffset: $timeOffset, lane: $lane, type: $type, '
      'height: $height, behavior: $behavior)';
}
