// CHALLENGE build-02 — show the sword arm. See CHALLENGES.md.

import 'package:achrona/kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the hero turns toward the lens, a little', () {
    // Negative turns him toward the camera, positive turns his back. A pure
    // profile (0) hides the swing; past 45 he stops reading as side-on.
    expect(kHeroLean, lessThan(-10));
    expect(kHeroLean, greaterThan(-45));
  });
}
