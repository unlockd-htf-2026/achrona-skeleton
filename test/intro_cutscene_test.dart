// The opening is a script on the engine's own CutscenePlayer, so what needs
// pinning is not the timer — the engine owns that — but the one thing a script
// can get wrong: leaving the camera somewhere the player cannot play from.

import 'package:achrona/level_one.dart';
import 'package:achrona_platformer_engine/achrona_platformer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gate = 96.0;

  /// Records the shots a script calls for. A pan is its destination; a cut
  /// back to the hero is null.
  ({CutscenePlayer player, List<double?> looks}) build() {
    final looks = <double?>[];
    return (
      player: CutscenePlayer(
        levelIntro(
          pan: (from, to, seconds) => looks.add(to),
          cutToHero: () => looks.add(null),
          gateWorldX: gate,
          lines: ('first', 'second'),
        ),
      ),
      looks: looks,
    );
  }

  test('it opens on the gate and gives the camera back', () {
    final (:player, :looks) = build();
    player.update(0.1);
    expect(looks, [gate + 1], reason: 'the first shot drifts across the gate');

    player.update(3.2);
    expect(looks.last, isNull, reason: 'the camera must return to the hero');
    expect(player.isDone, isFalse);

    player.update(3.0);
    expect(player.isDone, isTrue);
  });

  test('skipping it still gives the camera back', () {
    final (:player, :looks) = build();
    player.update(0.1);
    player.skip();
    expect(player.isDone, isTrue);
    expect(
      looks.last,
      isNull,
      reason: 'an impatient player must not start looking at the gate',
    );
  });

  test('skipping before it starts does not strand the camera either', () {
    final (:player, :looks) = build();
    player.skip();
    expect(looks.last, isNull);
  });
}
