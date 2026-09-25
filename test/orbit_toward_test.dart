import 'dart:math' as math;

import 'package:achrona/globe/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('an eye already over the point needs no turn', () {
    final t = orbitToward(vm.Vector3(0, 0, -3), vm.Vector3(0, 0, -1));
    expect(t.azimuth, closeTo(0, 1e-6));
    expect(t.polar, closeTo(0, 1e-6));
  });

  test('turns the short way round, and up to a northern point', () {
    // Eye at azimuth 0 (-Z); point just past the far side at azimuth ~ -170°.
    final a = -170 * math.pi / 180;
    final p = vm.Vector3(-math.sin(a), 1, -math.cos(a));
    final t = orbitToward(vm.Vector3(0, 0, -3), p);
    expect(t.azimuth, closeTo(a, 1e-6));
    expect(t.polar, closeTo(math.pi / 4, 1e-6));
  });
}
