// Hand-authored levels fail in one boring way: something is placed a row off.
// A fragment hangs in the air, a monster spawns inside the floor, the gate is
// half a tile into a wall. None of it crashes and all of it is only visible by
// walking there, so it is checked here instead.

import 'package:achrona/concepts.dart';
import 'package:achrona/level_one.dart';
import 'package:achrona/my_level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/example_team_levels.dart';

void main() {
  for (final spec in [kLevelOne, kLevelTwo, kLevelThree, kMyLevel, ...exampleTeamLevels().map((t) => t.spec)]) {
    group(spec.title, () {
      final rows = spec.rows();

      test('the grid is the size the spec claims', () {
        expect(rows.length, spec.height);
        expect(rows.every((r) => r.length == spec.width), isTrue);
      });

      test('it is winnable: a spawn, three fragments, one gate, one ability',
          () {
        int count(String kind) =>
            spec.objects.where((o) => o.$1 == kind).length;
        expect(count('spawn'), 1);
        expect(count('fragment'), 3);
        expect(count('gate'), 1);
        expect(count('ability'), 1);
      });

      test('nothing is buried and nothing but a flyer floats', () {
        for (final (kind, col, row) in spec.objects) {
          final here = rows[row][col];
          expect(here, ' ', reason: '$kind at ($col,$row) is inside terrain');

          if (Enemy.flyingKinds.any((f) => kind.endsWith(f))) continue;
          final below = rows[row + 1][col];
          expect(
            below == '#' || below == '=',
            isTrue,
            reason: '$kind at ($col,$row) has nothing under it',
          );
        }
      });
    });
  }

  // The student level is built around the team's concept card.
  test('${kMyLevel.title}: meets its concept card', () {
    final card = conceptById(kMyConcept);
    expect(card.check(kMyLevel), isNull, reason: '${card.title}: ${card.rule}');
  });

  test('the camera can reach the top of every level', () {
    // The ceiling the view derives (height - highest standable row) has to be
    // above the spawn, or the level opens with the hero off the top of the
    // screen — which is exactly what a number tuned against level one did.
    for (final spec in [kLevelOne, kLevelTwo, kLevelThree, kMyLevel, ...exampleTeamLevels().map((t) => t.spec)]) {
      final rows = spec.rows();
      final top = rows.indexWhere((r) => r.contains('#') || r.contains('='));
      final ceiling = spec.height - top;
      // The hero's feet sit on the tile BELOW the row he is placed in, so
      // that surface's height is what the camera has to be able to reach.
      final spawnRow = spec.objects.firstWhere((o) => o.$1 == 'spawn').$3;
      expect(
        ceiling,
        greaterThanOrEqualTo(spec.height - (spawnRow + 1)),
        reason: '${spec.title}: the camera cannot look at its own spawn',
      );
    }
  });

  test('one leads to two, two to three, and three ends the game', () {
    expect(kLevelOne.next, same(kLevelTwo));
    expect(kLevelTwo.next, same(kLevelThree));
    expect(kLevelThree.next, isNull);
  });
}
