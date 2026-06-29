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
// Authoritative c15-takeduespawns test (D-05). Drives the student
// `HazardSpawner.takeDueSpawns` over a GENERATED scripted manifest + a generated
// sequence of elapsed queries, and asserts the emitted index stream equals the
// COMMITTED expected stream (Path B / D-04 / HARNESS-06). The expected per-query
// emitted indices are PRECOMPUTED from the frozen reference selection logic by
// the org-side carve (tool/carve.dart) and COMMITTED here at
// `test/canonical/grids/c15-takeduespawns.csv` — no private reference repo is
// fetched at CI time. The selection logic (cursor-advancing, emit-once,
// in-order) is reconstructed only by the student, never in this body.
//
// LOCKSTEP: the offsets manifest + query sequence below MUST match
// `_writeTakeDueGrid` in tool/carve.dart byte-for-byte (same seed, same draw
// order, same queries). The grid is indexed positionally per query.
import 'dart:io';
import 'dart:math';

// Package under test = the CALLER FORK's lib/.
import 'package:achrona_engine/src/hazards/hazard_spawner.dart';
import 'package:achrona_engine/src/hazards/scheduled_spawn.dart';
import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rng = Random(0xC15);

  // Generated scripted manifest: ascending timeOffsets (the only field the
  // selection logic depends on), wider than the 3-row local fixture.
  final offsets = <double>[];
  var t = 0.0;
  for (var i = 0; i < 12; i++) {
    t += 0.2 + rng.nextDouble() * 0.9;
    offsets.add(double.parse(t.toStringAsFixed(4)));
  }
  final manifest = <ScheduledSpawn>[
    for (var i = 0; i < offsets.length; i++)
      ScheduledSpawn(
        timeOffset: offsets[i],
        lane: i % 3,
        type: HazardType.values[i % HazardType.values.length],
      ),
  ];

  // Generated elapsed query sequence — includes repeats (no double-emit),
  // jumps, and a final overshoot that drains the manifest.
  final queries = <double>[
    0.1,
    offsets[2],
    offsets[2], // repeat — must emit nothing the second time
    offsets[5],
    offsets[8] + 0.5,
    999.0,
  ];

  // COMMITTED expected grid (Path B): exactly one row PER QUERY (positional),
  // each a pipe-separated list of manifest indices the frozen reference emits
  // (an EMPTY line means that query emits nothing). We must NOT drop empty lines
  // here — they are meaningful positional entries — so we only strip the header.
  // `readAsLinesSync` treats a trailing newline as a terminator (no phantom
  // final empty element), so after dropping the header line count == query count.
  final gridLines =
      File('test/canonical/grids/c15-takeduespawns.csv').readAsLinesSync();
  final expectedStream = gridLines
      .skip(1) // skip header only — keep empty (no-emit) rows positionally
      .map((l) => l.trim().isEmpty
          ? <int>[]
          : l.split('|').where((s) => s.isNotEmpty).map(int.parse).toList())
      .toList();

  test('takeDueSpawns matches the committed reference index stream, in order',
      () {
    expect(
      expectedStream.length,
      equals(queries.length),
      reason: 'grid/query length mismatch — carve and test are out of lockstep',
    );

    final spawner = HazardSpawner(
      hazards: const [],
      minPeriod: 1,
      maxPeriod: 3,
      viewportSize: Vector2(900, 360),
      rng: Random(1),
      scriptedSpawns: manifest,
    );

    var asserts = 0;
    for (var q = 0; q < queries.length; q++) {
      final due = spawner.takeDueSpawns(queries[q]);
      final expectedSpawns =
          expectedStream[q].map((i) => manifest[i]).toList();
      expect(
        due,
        equals(expectedSpawns),
        reason: 'takeDueSpawns(${queries[q]}) at step $q',
      );
      asserts++;
    }
    expect(asserts, equals(queries.length));
  });
}
