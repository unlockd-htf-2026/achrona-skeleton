// CHALLENGE c11-desyncnetrate (Creative) — see CHALLENGES.md.
//
// Inverted-golden contract: asserts AchronaGame.desyncNetRate(x) equals the
// expected value from the OPAQUE fixture test/fixtures/c11-desyncnetrate.golden.
// No inline literal, no formula in this test body.
//
// RED against the carved throwing stub (UnimplementedError). GREEN once you
// implement the signed net-rate model.
import 'dart:io';

import 'package:achrona_engine/achrona_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lines = File('test/fixtures/c11-desyncnetrate.golden')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final header = lines.first.split(',');
  final rows = lines.skip(1).map((l) => l.split(',')).toList();

  int col(String name) => header.indexOf(name);

  test('desyncNetRate matches the sealed reference on every sampled row', () {
    expect(rows, isNotEmpty);
    for (final r in rows) {
      final actual = AchronaGame.desyncNetRate(
        creep: double.parse(r[col('creep')]),
        cleanTime: double.parse(r[col('cleanTime')]),
        slowWave: r[col('slowWave')].trim() == 'true',
      );
      final expected = double.parse(r[col('expected')]);
      expect(
        actual,
        closeTo(expected, 1e-9),
        reason: 'desyncNetRate row ${r.join(",")} expected $expected',
      );
    }
  });
}
