// CHALLENGE base-03 — which way the models face. See CHALLENGES.md.

import 'package:achrona/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Where [forward] points once the game turns the model by [quarters], the
/// way the game does it: a yaw about the up axis.
vm.Vector3 turned(vm.Vector3 forward, int quarters) =>
    vm.Matrix4.rotationY(quarterTurns(quarters)).transform3(forward.clone());

void main() {
  test('the hero walks toward screen-right (+X)', () {
    // The hero pack arrives looking down +Z.
    final f = turned(vm.Vector3(0, 0, 1), kHeroFacing);
    expect(f.x, closeTo(1, 1e-6), reason: 'the hero moonwalks');
  });

  test('the monsters walk toward screen-right (+X)', () {
    // The monster pack arrives looking down -Z: another modeller, another
    // forward.
    final f = turned(vm.Vector3(0, 0, -1), kFoeFacing);
    expect(f.x, closeTo(1, 1e-6), reason: 'the monsters moonwalk');
  });
}
