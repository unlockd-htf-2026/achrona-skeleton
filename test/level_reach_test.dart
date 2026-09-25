// Can the levels actually be finished? Asked of the engine, not of a person.
//
// Nobody has played level two end to end, and a hand-authored level fails
// quietly: a step one pixel too tall, a chasm one tile too wide, and the run
// is impossible without anything crashing. So this measures the hero's real
// jump — the frozen `PlayerPhysics`, stepped the way the game steps it — and
// then searches every standable tile of every level for a route.
//
// Approximations, stated: movement is tile-to-tile (a jump needs the gap
// between two tiles, not pixel-exact footing), and nothing in these levels has
// a ceiling low enough to cut an arc, so ceilings are not modelled.

import 'dart:collection';

import 'package:achrona/level_one.dart';
import 'package:achrona/my_level.dart';
import 'package:achrona_platformer_engine/achrona_platformer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/example_team_levels.dart';

/// One jump, sampled frame by frame as (horizontal px, rise px). Taken off a
/// three-tile ledge over a bottomless drop, holding right and jump the whole
/// way, so the arc keeps going down past the take-off height.
List<(double, double)> jumpArc({required bool doubleJump}) {
  final rows = [
    for (var r = 0; r < 60; r++) r == 20 ? '###${' ' * 77}' : ' ' * 80,
  ];
  final grid = StringTileGrid(rows);
  final b = PlayerPhysics(x: 0, y: 20 * 16 - 24, hasDoubleJump: doubleJump);
  // Settle onto the ledge, then step to its edge.
  for (var i = 0; i < 30; i++) {
    b.step(const PlayerIntent(), grid);
  }
  b.x = 3 * 16 - b.width;
  final x0 = b.x + b.width, feet0 = b.y + b.height;

  final samples = <(double, double)>[];
  b.requestJump();
  var lastY = b.y;
  var second = false;
  for (var f = 0; f < 300; f++) {
    b.step(const PlayerIntent(moveX: 1, jumpHeld: true), grid);
    // The second jump at the apex, which is where it buys the most.
    if (doubleJump && !second && b.y > lastY) {
      b.requestJump();
      second = true;
    }
    lastY = b.y;
    samples.add((b.x - x0, feet0 - (b.y + b.height)));
  }
  return samples;
}

/// The farthest the hero can travel horizontally while still being at least
/// [rise] px above where he left. He can always stop drifting in the air, so
/// anything short of that is reachable too.
double reachAt(List<(double, double)> arc, double rise) {
  var best = double.negativeInfinity;
  for (final (dx, h) in arc) {
    if (h >= rise && dx > best) best = dx;
  }
  return best;
}

/// Every tile the hero can stand in: air, with something to stand on below.
Set<(int, int)> standable(List<String> rows) => {
      for (var r = 0; r + 1 < rows.length; r++)
        for (var c = 0; c < rows[r].length; c++)
          if (rows[r][c] == ' ' && '#='.contains(rows[r + 1][c])) (c, r),
    };

/// Everything reachable from [start] with the given jump.
Set<(int, int)> reachable(
  List<String> rows,
  Set<(int, int)> starts,
  List<(double, double)> arc,
) {
  final cells = standable(rows);
  final seen = {...starts};
  final queue = Queue.of(starts);
  while (queue.isNotEmpty) {
    final (c, r) = queue.removeFirst();
    for (final (c2, r2) in cells) {
      if (seen.contains((c2, r2))) continue;
      final dc = (c2 - c).abs();
      if (dc > 14) continue;
      // The gap between the edge he leaves from and the near edge of the
      // tile he lands on; rise is positive going up.
      final gap = (dc - 1).clamp(0, 99) * 16.0;
      final rise = (r - r2) * 16.0;
      if (reachAt(arc, rise) >= gap) {
        seen.add((c2, r2));
        queue.add((c2, r2));
      }
    }
  }
  return seen;
}

void main() {
  final single = jumpArc(doubleJump: false);
  final double = jumpArc(doubleJump: true);

  test('the design rule: a single jump clears three tiles, not four', () {
    // Measured off the frozen engine: 63 px of carry at take-off height and
    // 60.6 px of rise (3.79 tiles). Four tiles is 64 px, one more than a
    // single jump has — which is exactly the pit level two first shipped with.
    expect(reachAt(single, 0), greaterThanOrEqualTo(3 * 16));
    expect(reachAt(single, 0), lessThan(4 * 16));
    // A double jump carries 135 px: eight tiles, not nine — the chasm level
    // two first shipped with.
    expect(reachAt(double, 0), greaterThanOrEqualTo(8 * 16));
    expect(reachAt(double, 0), lessThan(9 * 16));
    // And a three-row step is a safe climb; a four-row one is not.
    expect(reachAt(single, 3 * 16), greaterThanOrEqualTo(0));
    expect(reachAt(single, 4 * 16), lessThan(0));
  });

  test('the double jump is actually more jump', () {
    // If this fails the arcs are not measuring what they claim to.
    final h1 = single.map((s) => s.$2).reduce((a, b) => a > b ? a : b);
    final h2 = double.map((s) => s.$2).reduce((a, b) => a > b ? a : b);
    expect(h2, greaterThan(h1));
  });

  for (final spec in [kLevelOne, kLevelTwo, kLevelThree, kMyLevel, ...exampleTeamLevels().map((t) => t.spec)]) {
    test('${spec.title}: the route exists', () {
      final rows = spec.rows();
      (int, int) at(String kind) {
        final o = spec.objects.firstWhere((o) => o.$1 == kind);
        return (o.$2, o.$3);
      }

      // Before the Desync core: single jumps only.
      final early = reachable(rows, {at('spawn')}, single);
      expect(early, contains(at('ability')),
          reason: 'the ability cannot be reached on single jumps');
      // And the core has to matter: without it, the gate stays out of reach.
      expect(early, isNot(contains(at('gate'))),
          reason: 'the gate is reachable without the Desync core — the '
              'ability gates nothing');

      // After it: double jumps, from anywhere already reachable.
      final late = reachable(rows, early, double);
      for (final o in spec.objects.where((o) => o.$1 == 'fragment')) {
        expect(late, contains((o.$2, o.$3)),
            reason: 'fragment at (${o.$2},${o.$3}) is unreachable');
      }
      expect(late, contains(at('gate')), reason: 'the gate is unreachable');
    });
  }
}
