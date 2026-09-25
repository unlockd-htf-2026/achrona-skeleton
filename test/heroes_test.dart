// Heroes differ in play — their own weapon, hearts and one ability — but not
// in movement: every level is proven finishable (level_reach_test) with one
// jump and one run, so a slower or lower-jumping hero could make a proven
// level unfinishable.

import 'package:achrona/level_one.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

HeroKind hero(String name) => kHeroes.firstWhere((h) => h.name == name);
WeaponKind weaponOf(HeroKind h) =>
    kWeapons.firstWhere((w) => w.label == h.weapon);

Enemy enemy() => Enemy(
      node: Node(),
      model: Node(),
      kind: 'Birb',
      homeX: 0,
      y: 0,
      yOffset: 0,
    );

void main() {
  group('each hero has their own weapon', () {
    test('every hero wields a weapon that exists', () {
      for (final h in kHeroes) {
        expect(kWeapons.map((w) => w.label), contains(h.weapon), reason: h.name);
      }
    });

    test('no two heroes share a weapon', () {
      final weapons = kHeroes.map((h) => h.weapon).toList();
      expect(weapons.toSet().length, weapons.length);
    });

    test('no two heroes share an ability', () {
      final abilities = kHeroes.map((h) => h.ability).toList();
      expect(abilities.toSet().length, abilities.length);
    });
  });

  group('the sword is beefy, the ranger squishy', () {
    test('the Squire carries the sword and the most hearts', () {
      final squire = hero('SQUIRE');
      expect(squire.weapon, 'sword');
      for (final h in kHeroes.where((h) => h != squire)) {
        expect(squire.hearts, greaterThan(h.hearts), reason: h.name);
      }
    });

    test('the Ranger fights at range with the fewest hearts', () {
      final ranger = hero('RANGER');
      expect(weaponOf(ranger).ranged, isTrue);
      for (final h in kHeroes.where((h) => h != ranger)) {
        expect(ranger.hearts, lessThan(h.hearts), reason: h.name);
      }
    });

    test('nobody is one hit from death', () {
      for (final h in kHeroes) {
        expect(h.hearts, greaterThanOrEqualTo(2), reason: h.name);
      }
    });
  });

  group('abilities', () {
    test('Heavy Blade: two damage a swing, and a longer reach', () {
      final squire = hero('SQUIRE');
      expect(squire.damage, 2);
      expect(squire.reach(weaponOf(squire)),
          greaterThan(weaponOf(squire).reach));
    });

    test('Quick Draw: fires faster than the weapon alone', () {
      final ranger = hero('RANGER');
      expect(ranger.attackSpeed(weaponOf(ranger)),
          greaterThan(weaponOf(ranger).attackSpeed));
    });

    test('Piercing Charge: only the Huntress pierces', () {
      expect(kHeroes.where((h) => h.pierces).map((h) => h.name), ['HUNTRESS']);
    });

    test('Void Step: only the Wanderer dashes from the start', () {
      expect(kHeroes.where((h) => h.dashesFromStart).map((h) => h.name),
          ['WANDERER']);
    });

    test('everyone else fights at the weapon as it is', () {
      for (final h in kHeroes.where((h) => h.ability != HeroAbility.heavyBlade &&
          h.ability != HeroAbility.quickDraw)) {
        final w = weaponOf(h);
        expect(h.damage, 1, reason: h.name);
        expect(h.reach(w), w.reach, reason: h.name);
        expect(h.attackSpeed(w), w.attackSpeed, reason: h.name);
      }
    });
  });

  group('damage lands whole', () {
    // A two-damage hit used to be two one-damage hits in a row — and the
    // first one's hit-stun swallowed the second, so the focus staff's "takes
    // an enemy out on its own" charge never did.
    test('a two-damage hit fells a two-hp foe at once', () {
      final e = enemy();
      expect(e.takeHit(damage: 2), isTrue);
      expect(e.alive, isFalse);
    });

    test('a one-damage hit leaves it standing, stunned', () {
      final e = enemy();
      expect(e.takeHit(), isFalse);
      expect(e.alive, isTrue);
      expect(e.takeHit(), isFalse, reason: 'hit-stun swallows a second hit');
    });
  });
}
