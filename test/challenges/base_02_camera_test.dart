// CHALLENGE base-02 — the camera side. See CHALLENGES.md.

import 'package:achrona/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  final target = vm.Vector3(5, 2, 0);
  final eye = cameraEye(target);

  test('screen-right is world +X, so right walks right', () {
    // The view's right axis is cross(up, forward); on the wrong side of the
    // play plane it comes out as -X and the whole world renders mirrored.
    final forward = (target - eye).normalized();
    final right = vm.Vector3(0, 1, 0).cross(forward);
    expect(right.x, greaterThan(0.9), reason: 'the world renders mirrored');
  });

  test('it looks slightly down, from the rig distance', () {
    expect(eye.y, greaterThan(target.y));
    expect((eye - target).length, closeTo(kCameraDistance, 1e-4));
  });
}
