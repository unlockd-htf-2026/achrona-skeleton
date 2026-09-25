// Can the levels actually be finished? Asked of the engine, not of a person.
//
// Nobody has played level two end to end, and a hand-authored level fails
// quietly: a step one pixel too tall, a chasm one tile too wide, and the run
// is impossible without anything crashing. So this measures the hero's real
// jump — the frozen `PlayerPhysics`, stepped the way the game steps it — and
// then searches every standable tile of every level for a route.
//
// Approximations, stated: a jump starts from the edge of its tile and is the
// measured arc, drifting at full speed from take-off or up to ~0.6 s later,
// then straight down onto the landing tile once over it; the hero's 12x24 px
// body must not touch solid ground anywhere on the way (one-way ledges let
// him through from below). Stepping off an edge is its own path (no jump, so
// no bumped ceiling). Spiked tiles are no place to stand.

import 'dart:collection';

import 'package:achrona/level_one.dart';
import 'package:achrona/my_level.dart';
import 'package:achrona_platformer_engine/achrona_platformer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/example_team_levels.dart';

/// One jump, sampled frame by frame as (horizontal px, rise px). Taken off a
/// three-tile ledge over a bottomless drop, holding right and jump the whole
/// way, so the arc keeps going down past the take-off height.
List<(double, double)> jumpArc({required bool doubleJump, bool jump = true}) {
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
  if (jump) b.requestJump();
  var lastY = b.y;
  var second = false;
  for (var f = 0; f < 300; f++) {
    b.step(const PlayerIntent(moveX: 1, jumpHeld: true), grid);
    // The second jump at the apex, which is where it buys the most.
    if (jump && doubleJump && !second && b.y > lastY) {
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

/// Every tile the hero can stand in: air, with something to stand on below,
/// and no spike in it.
Set<(int, int)> standable(List<String> rows,
        {Set<(int, int)> hazards = const {}}) =>
    {
      for (var r = 0; r + 1 < rows.length; r++)
        for (var c = 0; c < rows[r].length; c++)
          if (rows[r][c] == ' ' &&
              '#='.contains(rows[r + 1][c]) &&
              !hazards.contains((c, r)))
            (c, r),
    };

/// Stepping off an edge: the same measurement with no jump.
final _walkOff = jumpArc(doubleJump: false, jump: false);

/// How much later than take-off the hero may start drifting, in frames.
const _delays = [0, 4, 8, 12, 16, 20, 24, 30, 36];

/// Everything reachable from [start] with the given jump.
Set<(int, int)> reachable(
  List<String> rows,
  Set<(int, int)> starts,
  List<(double, double)> arc, {
  Set<(int, int)> hazards = const {},
}) {
  final cells = standable(rows, hazards: hazards);
  final seen = {...starts};
  final queue = Queue.of(starts);
  while (queue.isNotEmpty) {
    final (c, r) = queue.removeFirst();
    for (final (c2, r2) in cells) {
      if (seen.contains((c2, r2))) continue;
      final dc = (c2 - c).abs();
      if (dc > 14) continue;
      // The gap between the edge he leaves from and the near edge of the
      // tile he lands on; rise is positive going up. Far enough is necessary
      // (and cheap); a clear path through the tiles is what decides.
      final gap = (dc - 1).clamp(0, 99) * 16.0;
      final rise = (r - r2) * 16.0;
      if (reachAt(arc, rise) < gap) continue;
      if (_clearPath(rows, (c, r), (c2, r2), arc)) {
        seen.add((c2, r2));
        queue.add((c2, r2));
      }
    }
  }
  return seen;
}

/// Can the hero get from standing in (c, r) to standing in (c2, r2) along
/// [arc] (any drift delay) or by stepping off, without touching solid ground?
bool _clearPath(List<String> rows, (int, int) from, (int, int) to,
    List<(double, double)> arc) {
  final (c, r) = from;
  final (c2, r2) = to;
  final w = rows.first.length;
  // The level's sides are walls; above and below it is open.
  bool solid(int col, int row, {bool oneWay = false}) {
    if (col < 0 || col >= w) return true;
    if (row < 0 || row >= rows.length) return false;
    final t = rows[row][col];
    return t == '#' || (oneWay && t == '=');
  }

  bool free(double l, double t, double rt, double b, {bool oneWay = false}) {
    for (var col = (l / 16).floor(); col <= ((rt - 0.01) / 16).floor(); col++) {
      for (var row = (t / 16).floor(); row <= ((b - 0.01) / 16).floor(); row++) {
        if (solid(col, row, oneWay: oneWay)) return false;
      }
    }
    return true;
  }

  const hw = 12.0, hh = 24.0;
  final feet0 = (r + 1) * 16.0, landFeet = (r2 + 1) * 16.0;
  final rise = feet0 - landFeet;

  // Straight up or down in the same column.
  if (c2 == c) {
    final top = arc.map((s) => s.$2).reduce((a, b) => a > b ? a : b);
    if (rise > top) return false;
    return free(c * 16.0 + 2, (rise > 0 ? landFeet : feet0) - hh, c * 16.0 + 2 + hw,
        rise > 0 ? feet0 : landFeet);
  }

  final dir = c2 > c ? 1 : -1;
  final edge = dir > 0 ? (c + 1) * 16.0 : c * 16.0;
  final gap = ((c2 - c).abs() - 1) * 16.0;

  bool along(List<(double, double)> path, int delay) {
    for (var k = 0; k < path.length; k++) {
      final h = path[k].$2;
      final dx = k < delay ? -hw : path[k - delay].$1;
      final lead = edge + dir * dx; // the edge that faces the way he goes
      final (l, rt) = dir > 0 ? (lead, lead + hw) : (lead - hw, lead);
      final feet = feet0 - h;
      if (!free(l, feet - hh, rt, feet)) return false;
      if (dx >= gap && h >= rise) {
        // Over the landing tile: stop drifting and come straight down onto it.
        return feet >= landFeet ||
            free(l, feet - hh, rt, landFeet, oneWay: true);
      }
    }
    return false;
  }

  if (_delays.any((d) => along(arc, d))) return true;
  return rise <= 0 && along(_walkOff, 0);
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

  // The search follows the real arc through the real tiles: walls and
  // ceilings block it, spikes are no place to stand. Each case below is a
  // hole the old rise-only search had.
  group('walls, ceilings and spikes', () {
    test('a pillar a single jump cannot clear blocks the gate behind it', () {
      // Old: the gate one tile past a 4-row pillar counted as reachable on
      // single jumps ("the core gates nothing") — a false fail.
      final rows = [
        '            ',
        '            ',
        '     #      ',
        '     #      ',
        '     #      ',
        '     #      ',
        '############',
      ];
      expect(reachable(rows, {(1, 5)}, single), isNot(contains((6, 5))));
      expect(reachable(rows, {(1, 5)}, double), contains((6, 5)));
    });

    test('a sealed room cannot be walked into', () {
      // Old: the gate inside counted as reachable through the wall — a false
      // pass.
      final rows = [
        '              ',
        '     #####    ',
        '     #   #    ',
        '     #   #    ',
        '     #   #    ',
        '     #   #    ',
        '##############',
      ];
      expect(reachable(rows, {(1, 5)}, double), isNot(contains((7, 5))));
    });

    test('spikes are no place to stand', () {
      // Five spiked tiles: one hop cannot clear them, so on single jumps the
      // far side is out of reach unless you land on a spike.
      final rows = ['            ', '            ', '############'];
      final spikes = {for (var c = 3; c <= 7; c++) (c, 1)};
      expect(standable(rows, hazards: spikes), isNot(contains((5, 1))));
      expect(reachable(rows, {(1, 1)}, single, hazards: spikes),
          isNot(contains((9, 1))));
      expect(reachable(rows, {(1, 1)}, double, hazards: spikes),
          contains((9, 1)));
    });

    test('walking off an edge under a low ceiling still drops you down', () {
      // A jump would bump the ceiling; stepping off does not need one.
      final rows = [
        '#########   ',
        '            ',
        '            ',
        '#####       ',
        '#####       ',
        '#####       ',
        '#####       ',
        '############',
      ];
      expect(reachable(rows, {(2, 2)}, single), contains((6, 6)));
    });

    test('a jump onto a ledge needs no run-up through its side', () {
      // A 3-row step right beside you: full speed would clip the ledge's
      // side, drifting later clears it — both are the same button presses
      // for a player.
      final rows = [
        '          ',
        '          ',
        '          ',
        '     #####',
        '     #####',
        '     #####',
        '##########',
      ];
      expect(reachable(rows, {(4, 5)}, single), contains((6, 2)));
    });
  });

  for (final spec in [kLevelOne, kLevelTwo, kLevelThree, kMyLevel, ...exampleTeamLevels().map((t) => t.spec)]) {
    test('${spec.title}: the route exists', () {
      final rows = spec.rows();
      (int, int) at(String kind) {
        final o = spec.objects.firstWhere((o) => o.$1 == kind);
        return (o.$2, o.$3);
      }

      // Spikes are no place to stand.
      final spikes = {
        for (final o in spec.objects)
          if (o.$1 == 'spikes') (o.$2, o.$3),
      };

      // Before the Desync core: single jumps only.
      final early = reachable(rows, {at('spawn')}, single, hazards: spikes);
      expect(early, contains(at('ability')),
          reason: 'the ability cannot be reached on single jumps');
      // And the core has to matter: without it, the gate stays out of reach.
      expect(early, isNot(contains(at('gate'))),
          reason: 'the gate is reachable without the Desync core — the '
              'ability gates nothing');

      // After it: double jumps, from anywhere already reachable.
      final late = reachable(rows, early, double, hazards: spikes);
      for (final o in spec.objects.where((o) => o.$1 == 'fragment')) {
        expect(late, contains((o.$2, o.$3)),
            reason: 'fragment at (${o.$2},${o.$3}) is unreachable');
      }
      expect(late, contains(at('gate')), reason: 'the gate is unreachable');
    });
  }
}
