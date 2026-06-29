// CHALLENGE c15-takeduespawns (Online-Elite) — see CHALLENGES.md.
//
// Inverted-golden contract: builds the authored manifest from the OPAQUE fixture
// test/fixtures/c15-takeduespawns.golden, then asserts that for each elapsed
// query HazardSpawner.takeDueSpawns(elapsed) emits exactly the indices the
// fixture records (in order). No selection logic is reconstructed in this body.
//
// RED against the carved throwing stub (UnimplementedError). GREEN once you
// implement the cursor-advancing due-selection.
import 'dart:io';

import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:achrona_engine/src/hazards/hazard_spawner.dart';
import 'package:achrona_engine/src/hazards/scheduled_spawn.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

void main() {
  final lines = File('test/fixtures/c15-takeduespawns.golden')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();

  final manifestRows = lines.where((l) => l.startsWith('M,')).toList();
  final queryRows = lines.where((l) => l.startsWith('Q,')).toList();

  HazardType parseType(String s) => HazardType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => HazardType.spike,
      );

  final spawns = <ScheduledSpawn>[
    for (final row in manifestRows)
      () {
        final p = row.split(',');
        // p = [M, timeOffset, lane, type]
        return ScheduledSpawn(
          timeOffset: double.parse(p[1]),
          lane: int.parse(p[2]),
          type: parseType(p[3]),
        );
      }(),
  ];

  test('takeDueSpawns emits the sealed reference index stream, in order', () {
    expect(spawns, isNotEmpty);
    final spawner = HazardSpawner(
      hazards: const [],
      minPeriod: 1,
      maxPeriod: 3,
      viewportSize: Vector2(900, 360),
      rng: Random(1),
      scriptedSpawns: spawns,
    );

    for (final row in queryRows) {
      final p = row.split(','); // [Q, elapsed, idx|idx|...]
      final elapsed = double.parse(p[1]);
      final expectedIdx = (p.length > 2 && p[2].isNotEmpty)
          ? p[2].split('|').map(int.parse).toList()
          : <int>[];
      final due = spawner.takeDueSpawns(elapsed);
      final expectedSpawns = expectedIdx.map((i) => spawns[i]).toList();
      expect(
        due,
        equals(expectedSpawns),
        reason: 'takeDueSpawns($elapsed) expected indices $expectedIdx',
      );
    }
  });
}
