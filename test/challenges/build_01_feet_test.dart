// CHALLENGE build-01 — stand on the floor. See CHALLENGES.md.

import 'package:achrona/kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 20-row level; a monster named at cell (3, 18) — the empty cell above
  // the ground row 19, the bottom row, whose top is at world y 1.
  final feet = objectFeet(3, 18, 20);

  test('feet rest on the ground, not in the air', () {
    expect(feet.y, closeTo(1, 1e-9));
  });

  test('feet are in the middle of the cell, where the hitbox is', () {
    // Cell 3 spans x 3..4; the models are centred on their origin.
    expect(feet.x, closeTo(3.5, 1e-9));
  });
}
