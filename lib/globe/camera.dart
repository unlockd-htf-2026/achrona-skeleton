/// Achrona — camera helpers.
///
/// No ambient auto-rotation (camera.js had one): every camera move here is
/// deliberate — the opening, the level dive, a heal swing — and a spin only
/// carried the camera off them.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// The `orbitBy` deltas that swing an orbit eye at [eye] round to look
/// straight down at [point] on the globe. `OrbitCameraController` exposes no
/// azimuth/polar getters, so the current angles are read back off the eye —
/// its `_eyeFor` puts it at `(-sin a, sin p, -cos a)`.
({double azimuth, double polar}) orbitToward(vm.Vector3 eye, vm.Vector3 point) {
  double az(vm.Vector3 v) => math.atan2(-v.x, -v.z);
  double pol(vm.Vector3 v) => math.asin((v.y / v.length).clamp(-1.0, 1.0));
  var d = az(point) - az(eye);
  // The short way round.
  d = (d + math.pi) % (2 * math.pi) - math.pi;
  return (azimuth: d, polar: pol(point) - pol(eye));
}
