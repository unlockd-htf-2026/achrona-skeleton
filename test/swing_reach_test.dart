// Sword reach — the one combat number level one owns.
//
// Everything else a swing does belongs to the engine (what a hit costs,
// i-frames, knockback) or to the clip (timing). Reach is the knob that gets
// turned during tuning, so it gets a test: not to fix a value, but so that
// turning it can never silently stop the swing from being in front of the
// hero at all. The rule is checked through `aabbOverlap`, the same function
// the sim resolves hits with.

import 'package:achrona/level_one.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A hero 12 wide (PlayerPhysics' default) standing at x=100: front edge 112.
  const px = 100.0, pw = 12.0;

  test('the box sits in front of whichever way he faces', () {
    expect(swingBox(px, pw, facingRight: true), (112.0, kSwingReach));
    expect(
      swingBox(px, pw, facingRight: false),
      (100.0 - kSwingReach, kSwingReach),
    );
  });

  test('an enemy inside reach is hit, one at the very end is not', () {
    final (ax, aw) = swingBox(px, pw, facingRight: true);
    const far = 112.0 + kSwingReach;
    expect(aabbOverlap(ax, 0, aw, 24, far, 0, 22, 24), isFalse);
    expect(aabbOverlap(ax, 0, aw, 24, far - 1, 0, 22, 24), isTrue);
  });

  test('an enemy at your back is missed', () {
    final (ax, aw) = swingBox(px, pw, facingRight: false);
    expect(aabbOverlap(ax, 0, aw, 24, 120, 0, 22, 24), isFalse);
  });

  group('weapons', () {
    test('every kind has clips the library actually ships', () {
      // The four verbs the free Universal Animation Library contains. A typo
      // here is a weapon that silently plays whatever the library falls back
      // to, which looks like an animation bug rather than a missing name.
      const shipped = {
        'Sword_Idle', 'Sword_Attack',
        'Spell_Simple_Idle_Loop', 'Spell_Simple_Shoot', 'Idle_Torch_Loop',
        'Pistol_Idle_Loop', 'Pistol_Shoot',
        'Idle_Loop', 'Punch_Jab',
      };
      for (final w in kWeapons) {
        expect(shipped, contains(w.idle), reason: '${w.label} idle');
        expect(shipped, contains(w.attack), reason: '${w.label} attack');
      }
    });

    test('a melee weapon reaches in front of him, a ranged one does not care',
        () {
      for (final w in kWeapons.where((w) => !w.ranged)) {
        final (ax, _) = swingBox(100, 12, facingRight: true, reach: w.reach);
        expect(ax, 112, reason: '${w.label} swings from his front edge');
      }
      expect(kWeapons.where((w) => w.ranged).isNotEmpty, isTrue);
      // Fists give up reach for nothing else to give up.
      final fists = kWeapons.firstWhere((w) => w.asset == null);
      expect(fists.reach, lessThan(kSwingReach));
    });

    test('the mount matches the models it bridges', () {
      // Quaternius' Medieval Weapons Pack (CC0), measured off the OBJs by
      // profiling each cross-section along its length. Every prop runs along
      // its own +Y, and each declares that, so the mount turns it onto the
      // measured hole through the fist.
      final sword = kWeapons.firstWhere((w) => w.label == 'sword');
      final staff = kWeapons.firstWhere((w) => w.label == 'focus');
      final bow = kWeapons.firstWhere((w) => w.label == 'bow');
      for (final w in [sword, staff, bow]) {
        expect(w.modelAxis, (0.0, 1.0, 0.0), reason: w.label);
      }

      // Sword: pommel at -0.82, grip to ~+0.5, cross-guard +0.54…+0.82, tip
      // at +4.63. Held on the grip under the guard, and about 0.8 long
      // against the hero's 1.87.
      expect(sword.holdPoint.$2, inInclusiveRange(-0.5, 0.45));
      expect(5.45 * sword.scale.$2, closeTo(0.8, 0.1));
      // A swung sword follows the fist.
      expect(sword.upright, isFalse);

      // Spear as the focus staff: butt at -2.16, head from +4.6 to +7.56.
      // Staff length (~1.8), held low on the shaft — the fist's angle is
      // fixed, so shaft behind the hand swings through his hip — and a shaft
      // (half-width 0.15) his hand closes around rather than swallows.
      expect(9.72 * staff.scale.$2, closeTo(1.8, 0.15));
      expect(staff.holdPoint.$2, inInclusiveRange(-1.5, 1.5));
      expect(0.15 * staff.scale.$1, lessThan(0.035));
      expect(staff.upright, isTrue, reason: 'a carried staff stands up');

      // Bow: 5.44 tall, riser at the origin, string on +X — so the arrow
      // flies toward -X, and the mount aims that where he faces.
      expect(bow.pointAxis, (-1.0, 0.0, 0.0));
      expect(bow.upright, isTrue);
      expect(5.44 * bow.scale.$2, inInclusiveRange(0.8, 1.2));

      // No clip in the library draws a bow or carries a staff in the sword
      // hand. `Idle_Torch_Loop` is the one idle that bends an arm around a
      // vertical grip — the LEFT — and `Spell_Simple_Shoot` pushes that arm
      // out. So the bow and the spear ride the left hand, which is also where
      // an archer holds a bow; the sword stays in the right, its swing arm.
      expect(sword.hand, 'hand_r');
      for (final w in [staff, bow]) {
        expect(w.hand, 'hand_l', reason: w.label);
        expect(w.idle, 'Idle_Torch_Loop', reason: w.label);
        expect(w.attack, 'Spell_Simple_Shoot', reason: w.label);
      }

      // The squire's free hand carries a shield: Shield_Heater_2, 2 × 2.56,
      // its face on -Z and its straps on +Z (a render showed the straps to
      // the camera with the axis the other way). Upright, face forward, held
      // by the straps in the left fist.
      final shield = sword.offhand!;
      expect(shield.hand, 'hand_l');
      expect(shield.upright, isTrue);
      expect(shield.pointAxis, (0.0, 0.0, -1.0));
      expect(shield.holdPoint.$3, greaterThan(0));
      expect(2.56 * shield.scale.$2, closeTo(0.64, 0.1));
      expect(staff.offhand, isNull);
      expect(bow.offhand, isNull);

      // The grip is where the fist actually closes, not where the bone starts:
      // a wrist-mounted prop misses the palm by the X of this point. And the
      // hands are MIRRORED — using one hand's numbers for the other puts the
      // prop a palm's width outside the fist.
      final right = kGrips['hand_r']!;
      final left = kGrips['hand_l']!;
      expect(right.point.x, lessThan(-0.03));
      expect(left.point.x, greaterThan(0.03));
      expect(right.point.y, closeTo(0.114, 0.01));
      // The hole is tilted off the hand's Z, which is the error no
      // quarter-turn mount can express.
      for (final grip in [right, left]) {
        expect(grip.axis.z, greaterThan(0.9));
        expect(grip.axis.y, greaterThan(0.2));
      }
    });
  });

  group('bolt reach', () {
    // Hero and enemy on the same floor: the hero's 24-pixel body ends where
    // the enemy's feet are, and a flyer's feet are its hover height above it.
    const heroTop = 100.0, floor = heroTop + 24;
    const hover = {'GhostSkull': 1.3, 'Armabee': 1.5, 'Ghost': 1.2};

    bool reaches(String kind) {
      final (w, h) = Enemy.boxes[kind]!;
      final feet = floor - (hover[kind] ?? 0) * 16;
      return aabbOverlap(
          0, heroTop + kBoltDrop, kBoltSize, kBoltHeight, 0, feet - h, w, h);
    }

    test('crosses every walker, including the 16-px Birb', () {
      for (final kind in Enemy.boxes.keys) {
        if (Enemy.flyingKinds.contains(kind)) continue;
        expect(reaches(kind), isTrue, reason: kind);
      }
    });

    test('reaches the flyers that can reach him', () {
      // A 6x6 bolt passed 1 px under a Ghost that was hurting him.
      expect(reaches('Ghost'), isTrue);
      expect(reaches('GhostSkull'), isTrue);
    });

    test('the Armabee still needs a jump — it cannot touch him either', () {
      expect(reaches('Armabee'), isFalse);
    });
  });
}
