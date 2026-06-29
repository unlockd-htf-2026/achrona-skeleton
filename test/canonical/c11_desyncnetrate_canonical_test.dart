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
// Authoritative c11-desyncnetrate test (D-05). Asserts the student
// `AchronaGame.desyncNetRate(inputs[i]) == grid[i]` over a GENERATED input set
// wider than the local fixture (Path B / D-04 / HARNESS-06). The expected
// outputs are PRECOMPUTED from the frozen reference impl by the org-side carve
// (tool/carve.dart) and COMMITTED here at
// `test/canonical/grids/c11-desyncnetrate.csv` — no private reference repo is
// fetched at CI time (a student fork's CI cannot reach it). The fork never sees
// the recover-speed/delay model.
//
// LOCKSTEP: the input generation below MUST match `_writeDesyncGrid` in
// tool/carve.dart byte-for-byte (same seed, same draw order, same boundary
// rows). The grid is indexed positionally.
import 'dart:io';
import 'dart:math';

// Package under test = the CALLER FORK's lib/.
import 'package:achrona_engine/achrona_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rng = Random(0xC11);
  // Generated grid spans: recent stumbles (advance), clean recede, high creep,
  // slowWave halving an advance, slowWave NOT flipping a recede, the exact
  // recover-delay boundary — far beyond the handful of local fixture rows.
  final inputs = <Map<String, Object>>[
    for (var i = 0; i < 200; i++)
      {
        'creep': rng.nextDouble() * 120.0,
        'cleanTime': rng.nextDouble() * 6.0,
        'slowWave': rng.nextBool(),
      },
    // Boundary rows around the recover delay and the net==0 sign edge.
    {'creep': 30.0, 'cleanTime': 2.0, 'slowWave': false}, // net exactly 0 when clean
    {'creep': 30.0, 'cleanTime': 2.0, 'slowWave': true}, // slowWave must NOT flip net==0
    {'creep': 0.0, 'cleanTime': 0.0, 'slowWave': true},
    {'creep': 120.0, 'cleanTime': 1.999, 'slowWave': true}, // just below delay
  ];

  // COMMITTED expected grid (Path B): one `expected` value per input row.
  final gridLines = File('test/canonical/grids/c11-desyncnetrate.csv')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final expectedGrid =
      gridLines.skip(1).map(double.parse).toList(); // skip header

  test('desyncNetRate matches the committed reference grid over a generated grid',
      () {
    expect(
      expectedGrid.length,
      equals(inputs.length),
      reason: 'grid/input length mismatch — carve and test are out of lockstep',
    );
    var asserts = 0;
    for (var i = 0; i < inputs.length; i++) {
      final x = inputs[i];
      final actual = AchronaGame.desyncNetRate(
        creep: (x['creep']! as num).toDouble(),
        cleanTime: (x['cleanTime']! as num).toDouble(),
        slowWave: x['slowWave']! as bool,
      );
      expect(actual, closeTo(expectedGrid[i], 1e-9), reason: 'desyncNetRate($x)');
      asserts++;
    }
    expect(asserts, greaterThan(100));
  });
}
