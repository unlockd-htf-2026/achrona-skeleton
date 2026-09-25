// Your team's level: the fourth landmark on Base, "IV · YOUR LEVEL" in the
// globe's LEVEL menu. See CHALLENGES.md -> base-01.

import 'kit.dart';

/// CHALLENGE base-01: your team's concept card id, from `lib/concepts.dart`
/// — the organisers hand you one.
const String kMyConcept = '';

const int _w = 40;
const int _h = 20;

/// CHALLENGE base-01: build your level here. Right now it is a flat floor
/// with nothing to find, so it cannot be won.
List<String> buildMyLevelRows() {
  final g = List.generate(_h, (_) => List.filled(_w, kAir));
  for (var row = 17; row < _h; row++) {
    for (var c = 0; c < _w; c++) {
      g[row][c] = kSolid;
    }
  }
  return [for (final row in g) row.join()];
}

const LevelSpec kMyLevel = LevelSpec(
  title: 'YOUR LEVEL COMPLETE',
  width: _w,
  height: _h,
  rows: buildMyLevelRows,
  objects: [
    ('spawn', 2, 16),
    ('ability', 10, 16),
    ('gate', 36, 16),
  ],
  intro: ('A LAND OF OUR OWN MAKING', 'THREE FRAGMENTS — THEN THE GATE'),
);
