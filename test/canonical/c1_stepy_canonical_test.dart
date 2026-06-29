// 📖 READABLE COPY (non-authoritative, D-05). This mirrors the ORG canonical
// test so you can SEE how your work is judged. Editing this file does NOT change
// the CI verdict — the verifier overwrites test/canonical/ with the org copy
// before running, and asserts against the COMMITTED expected-grids
// (test/canonical/grids/) that live ONLY in the org harness repo, never here.
// Iterate locally with `./challenge <id>` (test/challenges/) instead; this file
// will not run locally (the test/canonical/grids/ CSVs it loads are org-side and
// are not shipped to your fork).

// ⛔ ORG-CONTROLLED CANONICAL TEST — unlockd-htf-2026/achrona-harness/test/canonical/
//
// This is the AUTHORITATIVE c1-stepy test (D-05). The fork ships a readable
// COPY for local iteration, but the verdict that counts comes from THIS file,
// fetched from the harness repo by verify.yml (it is NOT taken from the fork).
// Editing the fork's readable copy cannot change this.
//
// Committed-grid contract (Path B / D-04 / HARNESS-06): the expected outputs are
// PRECOMPUTED from the frozen reference implementation by the org-side carve
// (tool/carve.dart) and COMMITTED here as an opaque grid at
// `test/canonical/grids/c1-stepy.csv`. We regenerate the SAME seeded input set
// below and assert the student `PlayerComponent.stepY(inputs[i])` equals
// `grid[i]`. No private reference repo is fetched at CI time — a student fork's
// CI has no access to it. Inputs are GENERATED over a wide grid (broader than
// the shipped local fixture), so a fork that hardcoded the fixture sample points
// still fails here.
//
// LOCKSTEP: the input generation below MUST match `_writeStepYGrid` in
// tool/carve.dart byte-for-byte (same seed, same draw order, same boundary
// rows). The grid is indexed positionally, so any divergence misaligns rows.
import 'dart:io';
import 'dart:math';

// Package under test = the CALLER FORK's lib/ (the student's stepY).
import 'package:achrona_engine/src/game/player_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Generated input grid — deliberately wider and finer than the local fixture
  // so reconstructing the move-and-clamp from sampled points is the challenge,
  // and a fixture-hardcoded fork fails. Deterministic (seeded), no flakiness.
  final rng = Random(0xC1);
  const minY = 20.0;
  const maxY = 280.0;
  final inputs = <Map<String, num>>[
    for (var i = 0; i < 200; i++)
      {
        'currentY': minY + rng.nextDouble() * (maxY - minY),
        'dir': rng.nextInt(3) - 1, // -1, 0, 1
        'speed': 50.0 + rng.nextDouble() * 600.0,
        'dt': 1 / (30 + rng.nextInt(120)),
        'minY': minY,
        'maxY': maxY,
      },
    // Boundary rows: clamp-top, clamp-bottom, dir-0 hold, large dt.
    {'currentY': minY, 'dir': -1, 'speed': 900, 'dt': 1.0, 'minY': minY, 'maxY': maxY},
    {'currentY': maxY, 'dir': 1, 'speed': 900, 'dt': 1.0, 'minY': minY, 'maxY': maxY},
    {'currentY': 150, 'dir': 0, 'speed': 900, 'dt': 1.0, 'minY': minY, 'maxY': maxY},
  ];

  // COMMITTED expected grid (Path B): one `expected` value per input row, in
  // order. Produced by the org carve from the frozen reference impl.
  final gridLines = File('test/canonical/grids/c1-stepy.csv')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final expectedGrid =
      gridLines.skip(1).map(double.parse).toList(); // skip header

  test('stepY matches the committed reference grid over a generated grid', () {
    expect(
      expectedGrid.length,
      equals(inputs.length),
      reason: 'grid/input length mismatch — carve and test are out of lockstep',
    );
    var asserts = 0;
    for (var i = 0; i < inputs.length; i++) {
      final x = inputs[i];
      final actual = PlayerComponent.stepY(
        currentY: x['currentY']!.toDouble(),
        dir: x['dir']!.toInt(),
        speed: x['speed']!.toDouble(),
        dt: x['dt']!.toDouble(),
        minY: x['minY']!.toDouble(),
        maxY: x['maxY']!.toDouble(),
      );
      expect(actual, closeTo(expectedGrid[i], 1e-9), reason: 'stepY($x)');
      asserts++;
    }
    expect(asserts, greaterThan(100));
  });
}
