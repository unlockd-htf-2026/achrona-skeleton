// CHALLENGE c1-stepy (Base) — see CHALLENGES.md.
//
// Inverted-golden contract: this test asserts PlayerComponent.stepY(x) equals
// the expected value loaded from the OPAQUE fixture test/fixtures/c1-stepy.golden
// — never an inline literal, never the formula. Reconstructing the move-and-clamp
// rule from these sampled points IS the challenge.
//
// RED against the carved safe-default stub (which returns currentY, so the
// moved-value rows fail). GREEN once you reimplement stepY.
import 'dart:io';

import 'package:achrona_engine/src/game/player_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lines = File('test/fixtures/c1-stepy.golden')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final header = lines.first.split(',');
  final rows = lines.skip(1).map((l) => l.split(',')).toList();

  int col(String name) => header.indexOf(name);

  test('stepY matches the sealed reference on every sampled row', () {
    expect(rows, isNotEmpty);
    for (final r in rows) {
      final actual = PlayerComponent.stepY(
        currentY: double.parse(r[col('currentY')]),
        dir: int.parse(r[col('dir')]),
        speed: double.parse(r[col('speed')]),
        dt: double.parse(r[col('dt')]),
        minY: double.parse(r[col('minY')]),
        maxY: double.parse(r[col('maxY')]),
      );
      final expected = double.parse(r[col('expected')]);
      expect(
        actual,
        closeTo(expected, 1e-9),
        reason: 'stepY row ${r.join(",")} expected $expected',
      );
    }
  });
}
