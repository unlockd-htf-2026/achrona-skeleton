import 'dart:math';

import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:achrona_engine/src/game/player_component.dart';
import 'package:achrona_engine/src/hazards/hazard_component.dart';
import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:achrona_engine/src/hazards/scheduled_spawn.dart';
import 'package:flame/components.dart';

/// Spawns [HazardComponent]s in one of two modes.
///
/// **Random mode (default — student scaffold path, D-41):** when
/// [scriptedSpawns] is null, hazards are picked randomly from [hazards] on a
/// random interval in `[minPeriod, maxPeriod]`. This is the original behavior;
/// the student app is unaffected.
///
/// **Scripted mode (additive — Arcade / Rung-4 host path, D-42):** when
/// [scriptedSpawns] is a non-null ordered list, the spawner emits each
/// [ScheduledSpawn] exactly once, in order, as elapsed run time reaches its
/// `timeOffset`. This renders an EXPLICIT authored sequence (deterministic by
/// construction) with no random pick.
///
/// Lane x-positions are distributed evenly at 20 %, 50 %, and 80 % of the
/// viewport width (D-01). Scroll speed is read from
/// [AchronaGame.currentScrollSpeed] each spawn so newly spawned hazards respect
/// the current difficulty ramp (D-02).
class HazardSpawner extends Component with HasGameReference<AchronaGame> {
  HazardSpawner({
    required this.hazards,
    required this.minPeriod,
    required this.maxPeriod,
    required this.viewportSize,
    required Random rng,
    this.scriptedSpawns,
  }) : _rng = rng;

  final List<Hazard> hazards;
  final double minPeriod;
  final double maxPeriod;
  final Vector2 viewportSize;

  /// Optional explicit authored sequence (D-42). Null => random mode.
  final List<ScheduledSpawn>? scriptedSpawns;

  /// True when this spawner drives an explicit authored sequence.
  bool get isScripted => scriptedSpawns != null;

  final Random _rng;
  double _timer = 0;
  double _nextSpawn = 0;

  /// Elapsed run seconds in scripted mode (drives [takeDueSpawns]).
  double _scriptedElapsed = 0;

  /// Index of the next not-yet-emitted entry in [scriptedSpawns].
  int _scriptedCursor = 0;

  @override
  void onMount() {
    super.onMount();
    if (!isScripted) _scheduleNext();
  }

  void _scheduleNext() {
    _nextSpawn = minPeriod + _rng.nextDouble() * (maxPeriod - minPeriod);
    _timer = 0;
  }

  /// Returns the scripted spawns whose `timeOffset` is `<= elapsed` and have
  /// not yet been emitted, in order, advancing the internal cursor.
  ///
  /// Pure with respect to the sequence (no Flame dependency), so the
  /// scripted-mode selection logic is unit-testable. Returns an empty list in
  /// random mode or when nothing new is due.
  List<ScheduledSpawn> takeDueSpawns(double elapsed) {
    // CHALLENGE c15-takeduespawns (Online-Elite): return the scripted spawns
    // whose `timeOffset <= elapsed` that have not yet been emitted, in order,
    // advancing the internal cursor. Empty in random mode.
    // See CHALLENGES.md → c15-takeduespawns.
    throw UnimplementedError('c15-takeduespawns: implement takeDueSpawns');
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isScripted) {
      _scriptedElapsed += dt;
      takeDueSpawns(_scriptedElapsed).forEach(_spawnScripted);
      return;
    }

    if (hazards.isEmpty) return;
    _timer += dt;
    if (_timer >= _nextSpawn) {
      _spawn();
      _scheduleNext();
    }
  }

  // Shares PlayerComponent.trackCenters so hazards spawn on the SAME vertical
  // tracks the player can dash to; otherwise a hazard would sit off every
  // reachable track and could never be a real obstacle.
  List<double> get _trackYPositions =>
      PlayerComponent.trackCenters(viewportSize.y);

  void _spawn() {
    final hazard = hazards[_rng.nextInt(hazards.length)];
    _addHazard(
      Hazard(
        lane: hazard.lane,
        type: hazard.type,
        height: hazard.height,
        behavior: hazard.behavior,
      ),
    );
  }

  void _spawnScripted(ScheduledSpawn spawn) {
    _addHazard(
      Hazard(
        lane: spawn.lane,
        type: spawn.type,
        height: spawn.height,
        behavior: spawn.behavior,
      ),
    );
  }

  void _addHazard(Hazard hazard) {
    final trackYPositions = _trackYPositions;
    final trackIdx = hazard.lane.clamp(0, trackYPositions.length - 1);
    final trackY = trackYPositions[trackIdx];

    // ignore: discarded_futures — fire-and-forget component add; errors surface via FlameGame's onError
    parent?.add(
      HazardComponent(
        hazard: hazard,
        trackCenterY: trackY,
        viewportSize: viewportSize,
        rng: _rng,
      ),
    );
  }

  /// Resets the spawn timer (random mode) or the scripted cursor (scripted
  /// mode) — called when the game restarts.
  void resetSpawner() {
    if (isScripted) {
      _scriptedElapsed = 0;
      _scriptedCursor = 0;
      return;
    }
    _scheduleNext();
  }
}
