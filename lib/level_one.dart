/// **Achrona, level one.** A designed first level rather than a decorated
/// corridor: a shape with a start, a climb, a hazard, a gated ability, and a
/// sealed gate that opens when the three Desync fragments are carried to it.
///
/// The simulation is still the frozen engine — `PlayerPhysics` stepping at a
/// fixed 60 Hz against a `TileGrid`, exactly as `06-SEAM-SPIKE.md` describes.
/// What changed is the *content*: the map is authored here instead of loaded
/// from the 2D game's Tiled file, because level 1 of the 2D game is a flat
/// corridor and a flat corridor cannot show what the renderer can do.
///
/// Everything static is instanced (`TileBatcher`), the camera is fixed side-on,
/// and every prop is placed against a solidity check so nothing floats.
library;

import 'dart:math' as math;

import 'package:achrona_platformer_engine/achrona_platformer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/scene.dart' as fs show Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'fx/desync.dart';
import 'globe/palette.dart';
import 'globe/run_link.dart';
import 'asset_cache.dart';
import 'hero_model.dart' show loadClips;
import 'kit.dart';

export 'kit.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LevelOne(),
    ));

// ---------------------------------------------------------------------------
// The level itself.
// ---------------------------------------------------------------------------

/// A build for showing people (`--dart-define=SHOWCASE=true`): no tuning
/// buttons, no debug readouts — just hearts and lives.
const bool kShowcase = bool.fromEnvironment('SHOWCASE');

/// `?stats` in the URL shows the fps readout even in a showcase build.
final bool kShowStats = Uri.base.queryParameters.containsKey('stats');

/// Physical pixels per logical pixel for every 3D view (globe, picker,
/// level). 1, not the display's 2: a Retina screen at native density is 4×
/// the pixels through shadows, AO, bloom, fog and the Desync pass. Flutter
/// text on top stays crisp. `?pr=2` compares on real hardware.
final double kScenePixelRatio =
    double.tryParse(Uri.base.queryParameters['pr'] ?? '') ?? 1.0;

const int _oneW = 132;
const int _oneH = 22;

/// The floor the whole level stands on, and the shapes cut into it.
///
/// Written as code rather than as 132×22 characters of ASCII because the
/// interesting part is the *sequence* — ground, pit, climb, chasm, vault — and
/// a wall of glyphs hides it.
List<String> buildLevelOneRows() {
  final g = List.generate(_oneH, (_) => List.filled(_oneW, ' '));

  void solid(int c0, int c1, int r0, int r1) {
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (r >= 0 && r < _oneH && c >= 0 && c < _oneW) g[r][c] = '#';
      }
    }
  }

  void ledge(int c0, int c1, int r) => solid(c0, c1, r, _oneH - 1);
  void platform(int c0, int c1, int r) {
    for (var c = c0; c <= c1; c++) {
      if (c >= 0 && c < _oneW) g[r][c] = '=';
    }
  }

  // 1. Entrance hall — flat, safe, somewhere to learn the controls.
  ledge(0, 17, 18);

  // 2. First pit. Shallow, with a jump-through ledge, so a miss costs a hit
  //    and not a run.
  ledge(18, 21, 20);
  platform(19, 21, 16);
  ledge(22, 33, 18);

  // 3. The climb: three steps up to a ledge carrying the first fragment.
  ledge(34, 38, 17);
  ledge(39, 43, 15);
  ledge(44, 54, 13);

  // 4. A drop back down, with a one-way ledge to break the fall.
  platform(55, 58, 15);
  ledge(55, 70, 18);

  // 5. The spike run: ground either side, hazard between.
  ledge(71, 80, 18);
  ledge(81, 90, 18);

  // 6. The ability vault — a high shelf, reachable with a single jump from a
  //    stack, holding the Desync core that unlocks the double jump.
  ledge(91, 98, 18);
  platform(93, 96, 15);
  ledge(94, 99, 12);

  // 7. The chasm. Eight tiles with nothing under them (100–107) — the double
  //    jump carries 135 px, so 128 is a real jump and not a formality. This is
  //    the gate the double jump exists for, and it is why the vault comes
  //    first.
  ledge(108, 118, 18);

  // 8. The vault of the gate, raised, so the exit reads as an arrival.
  ledge(119, _oneW - 1, 17);

  return [for (final row in g) row.join()];
}

/// Objects, in tile coordinates (`col`, `row` = the tile the thing stands on).
const List<(String, int, int)> _levelOneObjects = [
  ('spawn', 3, 17),
  ('enemy:GhostSkull', 12, 17),
  ('fragment', 20, 15),
  ('enemy:Birb', 27, 17),
  ('enemy:Cactoro', 36, 16),
  ('fragment', 49, 12),
  ('enemy:Mushnub', 50, 12),
  ('enemy:Goleling', 62, 17),
  ('spikes', 76, 17),
  ('spikes', 77, 17),
  ('spikes', 78, 17),
  ('enemy:OrcEnemy', 84, 17),
  ('ability', 96, 11),
  ('enemy:Armabee', 112, 15),
  ('fragment', 114, 17),
  ('enemy:Ghost', 121, 16),
  ('gate', 127, 16),
];

/// One 16px engine tile = one world unit; kit models are a 2-unit grid.
const double _px = kPx;
const double _kit = 0.5;
// The Achrona palette is the globe's (`globe/palette.dart`): one neon, one
// cyan, on both screens.
const int _neon = kNeon;
const int _cyan = kCyan;

/// Ground glow, by kind: what you can stand on reads at a glance, and the
/// colour says what it does. One constant each, to play with.
const int kSolidGlow = kNeon;
const int kOneWayGlow = _cyan;

/// The map's own object names, mapped to the monster pack. The roster split
/// the handoff flagged shows up immediately: none of these share the hero's
/// humanoid rig, so they animate off their own clips.
/// The map's object `y` is a 2D anchor; these models do not share it (their
/// origin is not at the feet, and two of the three are flyers). One offset per
/// model, in world units, tuned by eye.
/// Per-species height above the tile they are placed on: flyers hover, the
/// rest stand. Zero means "origin is at the feet", which is the Quaternius
/// default and true for most of the bundle.
const Map<String, double> _enemyYOffset = {
  'GhostSkull': 1.3,
  'Birb': 0.1,
  'Armabee': 1.5,
  'Ghost': 1.2,
};

/// Axis-aligned overlap in the engine's pixel space (y down). Pulled out of
/// the widget so the contact rule can be tested without a scene.
bool aabbOverlap(
  double ax, double ay, double aw, double ah,
  double bx, double by, double bw, double bh,
) =>
    ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;

// ---------------------------------------------------------------------------
// Level two — "the Desync deepens". Level one climbs; this one descends, and
// the floor it takes from you is the point.
// ---------------------------------------------------------------------------

const int _twoW = 122;
const int _twoH = 26;

List<String> buildLevelTwoRows() {
  final g = List.generate(_twoH, (_) => List.filled(_twoW, ' '));

  void solid(int c0, int c1, int r0, int r1) {
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (r >= 0 && r < _twoH && c >= 0 && c < _twoW) g[r][c] = '#';
      }
    }
  }

  void ledge(int c0, int c1, int r) => solid(c0, c1, r, _twoH - 1);
  void platform(int c0, int c1, int r) {
    for (var c = c0; c <= c1; c++) {
      if (c >= 0 && c < _twoW) g[r][c] = '=';
    }
  }

  // 1. The landing. You arrive at the top and everything from here is down.
  ledge(0, 14, 7);

  // 2. The first step down, with a one-way ledge so the drop is a choice
  //    rather than a fall.
  platform(15, 18, 10);
  ledge(15, 26, 12);

  // 3. The corridor. Long, flat, lit — and two bands of spikes in it, close
  //    enough together that stopping between them is the hard part.
  ledge(27, 48, 15);

  // 4. A three-tile pit with nothing under it. Level one's first mistake cost
  //    a heart; this one costs the run. It was four tiles — 64 px — and a
  //    single jump carries 63, so the level could not be finished: the pit
  //    stood between the hero and the only thing that gives a double jump.
  //    `test/level_reach_test.dart` is what caught it.
  ledge(52, 68, 15);

  // 5. The vault, raised off the corridor: the Desync core, and the double
  //    jump with it. It sits before the chasm for the same reason it did in
  //    level one — the ability has to arrive before its reason to exist.
  platform(60, 63, 12);
  ledge(61, 68, 10);

  // 6. Down to the deep floor, below everything you have walked on so far.
  ledge(69, 87, 18);

  // 7. The chasm: eight tiles of nothing over a drop with no bottom. It was
  //    nine — 144 px — and a double jump carries 135, so the back half of the
  //    level, the last fragment and the gate, could not be reached. Eight is
  //    128 px, the width level one's chasm really is (its comment says nine;
  //    the geometry says eight, which is why it was finishable).
  ledge(96, 108, 18);

  // 8. The climb out. Three one-way ledges to the gate's shelf, so the level
  //    ends where it began — at the top.
  platform(100, 103, 15);
  platform(105, 108, 12);
  ledge(109, _twoW - 1, 10);

  return [for (final row in g) row.join()];
}

const List<(String, int, int)> _levelTwoObjects = [
  ('spawn', 3, 6),
  ('enemy:GhostSkull', 10, 5),
  ('fragment', 24, 11),
  ('enemy:Cactoro', 21, 11),
  ('enemy:OrcEnemy', 33, 14),
  ('spikes', 36, 14),
  ('spikes', 37, 14),
  ('spikes', 38, 14),
  ('spikes', 44, 14),
  ('spikes', 45, 14),
  ('enemy:Mushnub', 57, 14),
  ('fragment', 55, 14),
  ('ability', 64, 9),
  ('enemy:Goleling', 76, 17),
  ('enemy:Armabee', 92, 14),
  ('fragment', 101, 14),
  ('enemy:Ghost', 112, 9),
  ('gate', 116, 9),
];

// ---------------------------------------------------------------------------
// Level three — "the Spire". Level one climbs, level two descends; this one
// goes straight up, to where the Desync core burns.
// ---------------------------------------------------------------------------

const int _threeW = 96;
const int _threeH = 34;

List<String> buildLevelThreeRows() {
  final g = List.generate(_threeH, (_) => List.filled(_threeW, ' '));

  void solid(int c0, int c1, int r0, int r1) {
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (r >= 0 && r < _threeH && c >= 0 && c < _threeW) g[r][c] = '#';
      }
    }
  }

  void ledge(int c0, int c1, int r) => solid(c0, c1, r, _threeH - 1);
  void platform(int c0, int c1, int r) {
    for (var c = c0; c <= c1; c++) {
      if (c >= 0 && c < _threeW) g[r][c] = '=';
    }
  }

  // 1. The foot of the spire. The only flat ground for a while.
  ledge(0, 16, 30);

  // 2. The spike pit under the climb. A fall costs a heart and the climb back
  //    out (the hall is two rows up), not the run.
  ledge(17, 40, 32);

  // 3. The zig-zag: one-way ledges three rows apart and two tiles across —
  //    every step a single jump, none of them a formality over the spikes.
  platform(19, 22, 27);
  platform(25, 28, 24);
  platform(31, 34, 21);

  // 4. The terrace, and on it the pillar that holds the Desync core. The
  //    core comes before the wall it exists for, as in both levels before.
  ledge(37, 44, 18);
  platform(41, 43, 15);
  ledge(45, 48, 12);

  // 5. The far terrace: two spikes guarding the second fragment.
  ledge(49, 60, 18);

  // 6. The wall. Five rows — a single jump climbs three — so this is where
  //    the double jump stops being a bonus.
  ledge(61, 70, 13);

  // 7. The last gap, six tiles over nothing, up onto the crown.
  ledge(77, _threeW - 1, 12);

  return [for (final row in g) row.join()];
}

const List<(String, int, int)> _levelThreeObjects = [
  ('spawn', 3, 29),
  ('enemy:Cactoro', 10, 29),
  ('spikes', 20, 31),
  ('spikes', 22, 31),
  ('spikes', 24, 31),
  ('spikes', 26, 31),
  ('spikes', 28, 31),
  ('spikes', 30, 31),
  ('spikes', 32, 31),
  ('spikes', 34, 31),
  ('spikes', 36, 31),
  ('enemy:Armabee', 28, 20),
  ('fragment', 33, 20),
  ('enemy:OrcEnemy', 39, 17),
  ('ability', 46, 11),
  ('spikes', 52, 17),
  ('spikes', 53, 17),
  ('enemy:Goleling', 55, 17),
  ('fragment', 58, 17),
  ('enemy:GhostSkull', 66, 12),
  ('enemy:Armabee', 74, 9),
  ('fragment', 84, 11),
  ('enemy:Ghost', 89, 11),
  ('gate', 93, 11),
];

const LevelSpec kLevelThree = LevelSpec(
  title: 'LEVEL THREE COMPLETE',
  width: _threeW,
  height: _threeH,
  rows: buildLevelThreeRows,
  objects: _levelThreeObjects,
  intro: (
    'THE DESYNC CORE BURNS AT THE TOP',
    'CLIMB — THREE FRAGMENTS STILL HOLD THE GATE',
  ),
);

/// The levels. Written bottom-up so each can point at the next.
const LevelSpec kLevelTwo = LevelSpec(
  title: 'LEVEL TWO COMPLETE',
  width: _twoW,
  height: _twoH,
  rows: buildLevelTwoRows,
  objects: _levelTwoObjects,
  intro: (
    'THE DESYNC TOOK THE FLOOR HERE',
    'DOWN IS THE ONLY WAY OUT — FIND THREE MORE',
  ),
  next: kLevelThree,
);

const LevelSpec kLevelOne = LevelSpec(
  title: 'LEVEL ONE COMPLETE',
  width: _oneW,
  height: _oneH,
  rows: buildLevelOneRows,
  objects: _levelOneObjects,
  intro: (
    'THE DESYNC SEALED THIS GATE',
    'THREE FRAGMENTS WILL OPEN IT — FIND THEM',
  ),
  next: kLevelTwo,
);

/// A level's opening, as engine `CutsceneStep`s.
///
/// The engine already owns timed stages, captions and a skip that still fires
/// every remaining `onEnter` — so this is a script, not a second player. Each
/// step tells the view where to look through [look]; passing null hands the
/// camera back to the hero. The last step MUST hand it back, because `skip()`
/// runs the remaining `onEnter`s in order and that is what stops an impatient
/// player from starting the level looking at a door 100 tiles away.
List<CutsceneStep> levelIntro({
  required void Function(double from, double to, double seconds) pan,
  required void Function() cutToHero,
  required double gateWorldX,
  required (String, String) lines,
}) =>
    [
      // A drift across the gate, not a flight to it. The camera starts already
      // looking at the door and moves five tiles in three seconds — the whole
      // travel is the shot, rather than a whip-pan followed by a stare.
      CutsceneStep(
        duration: 3.0,
        caption: lines.$1,
        onEnter: () => pan(gateWorldX - 5, gateWorldX + 1, 3.0),
      ),
      // And a cut back. A hundred tiles is not a move a camera makes; every
      // film would cut, so this cuts.
      CutsceneStep(
        duration: 2.4,
        caption: lines.$2,
        onEnter: cutToHero,
      ),
    ];

const List<WeaponKind> kWeapons = [
  // Quaternius' Medieval Weapons Pack (CC0), measured off the models — see
  // `test/swing_reach_test.dart` for the profile each number comes from.
  WeaponKind(
    label: 'sword',
    asset: 'assets/weapons/sword.glb',
    idle: 'Sword_Idle',
    attack: 'Sword_Attack',
    reach: kSwingReach,
    attackSpeed: 1.6,
    // Blade up its own +Y; the fist on the grip just under the cross-guard
    // (+0.54), not at the pommel.
    holdPoint: (0.0, 0.2, 0.0),
    // 5.45 long in its own units: ×0.15 is a 0.82 blade on a 1.87 hero.
    scale: (0.15, 0.15, 0.15),
    // The free hand carries a shield. `Sword_Attack` is right-handed (the
    // right arm moves three to ten times more), so the left can hold it
    // still, stood up and faced forward — see [kShieldToLens].
    offhand: WeaponKind(
      label: 'shield',
      asset: 'assets/weapons/shield.glb',
      idle: '',
      attack: '',
      reach: 0,
      hand: 'hand_l',
      upright: true,
      // 2 wide × 2.56 tall, its face on −Z: the geometry that stands out on
      // +Z (z 0.3…0.45) is the straps on its back, where the fist goes.
      pointAxis: (0.0, 0.0, -1.0),
      holdPoint: (0.0, -0.2, 0.3),
      scale: (0.25, 0.25, 0.25),
    ),
  ),
  // The two ranged weapons are not a palette swap: the focus throws one slow,
  // heavy charge that takes an enemy out on its own, and the bow looses small
  // fast ones that take two. Both loose from the same left-handed cast; the
  // bow plays it faster.
  WeaponKind(
    label: 'focus',
    asset: 'assets/weapons/spear.glb',
    // In the left hand, because that is the arm the clips move: no clip in
    // the free library bends the right arm around a vertical stick, and
    // `Idle_Torch_Loop` — the only "holding a stick" pose — bends the left
    // (0.64/0.57 left against 0.00 right). In a relaxed right hand the spear
    // read as a walking stick. The cast is left-handed too, so the spear
    // goes out with the spell.
    hand: 'hand_l',
    idle: 'Idle_Torch_Loop',
    attack: 'Spell_Simple_Shoot',
    reach: 18,
    ranged: true,
    boltColour: _neon,
    // Low on the shaft (butt at −2.16, head from +4.6): the fist's angle is
    // fixed, so whatever sits *behind* his hand swings back through his hip.
    holdPoint: (0.0, 0.6, 0.0),
    upright: true,
    // 9.72 long: ×0.185 is a 1.8-unit staff, and its 0.15 shaft comes out
    // 0.028 — thin enough for his hand to close around.
    scale: (0.185, 0.185, 0.185),
    boltSpeed: 3.0,
    boltHits: 2,
    boltRadius: 0.22,
  ),
  WeaponKind(
    label: 'bow',
    asset: 'assets/weapons/bow.glb',
    // No clip in the library draws a bow. The pistol clips held it out like a
    // gun; an archer holds the bow in the LEFT hand, and the left is the arm
    // the torch idle bends around an upright grip and the spell cast pushes
    // straight out — which is the loose.
    hand: 'hand_l',
    idle: 'Idle_Torch_Loop',
    attack: 'Spell_Simple_Shoot',
    // The cast is a long channel; a bow is not.
    attackSpeed: 1.6,
    reach: 18,
    ranged: true,
    boltColour: _cyan,
    // Riser at the model's origin; the string is on +X, so the arrow leaves
    // toward −X.
    holdPoint: (0.03, 0.0, 0.0),
    pointAxis: (-1.0, 0.0, 0.0),
    // 5.44 tall: ×0.18 is a 0.98 short bow.
    scale: (0.18, 0.18, 0.18),
    upright: true,
    boltSpeed: 6.0,
    boltRadius: 0.11,
  ),
  WeaponKind(
    label: 'fists',
    asset: null,
    idle: 'Idle_Loop',
    attack: 'Punch_Jab',
    // Shorter than a blade, and that is the whole trade.
    reach: 14,
  ),
];

/// How far an off-hand shield turns from where he walks toward the lens,
/// 0 (square ahead, edge-on to the camera) to 1 (flat to the camera).
const double kShieldToLens = 0.55;

/// Every kit piece a level is built from (`buildLevelScene`, the gate), for
/// [prefetchLevel]. A piece missing here still loads — just not early.
const List<String> _levelKit = [
  'ruins/Floor_Standard.glb', 'ruins/Floor_Standard_Half.glb', 'ruins/Wall.glb',
  'ruins/Wall_Broken.glb', 'ruins/Wall_Overgrown.glb', 'ruins/Column_Round.glb',
  'dungeon/Torch.glb', 'dungeon/Spikes.glb', 'ruins/Stairs.glb',
  'ruins/Support_Center.glb', 'ruins/Barrel.glb', 'ruins/Crate.glb',
  'ruins/Pot1.glb', 'ruins/Pot2_Broken.glb', 'ruins/Bush_Round.glb',
  'dungeon/Skull.glb', 'dungeon/Banner_wall.glb', 'dungeon/Cobweb.glb',
  'ruins/Window_Bars.glb', 'ruins/Doors_GothicArch_Covered.glb',
  'ruins/Doors_GothicArch.glb',
];

/// Start downloading everything [spec] played as [hero] needs, all at once.
/// The globe calls it on ENTER, so the downloads run while the hero picker
/// is open; the level awaits it before parsing anything.
Future<void> prefetchLevel(LevelSpec spec, HeroKind hero) => prefetch([
      for (final k in _levelKit) 'assets/levels/$k',
      for (final (kind, _, _) in spec.objects)
        if (kind.startsWith('enemy:')) 'assets/enemies/${kind.substring(6)}.glb',
      for (final p in hero.parts) 'assets/models/ranger/$p',
      for (final w in kWeapons) ...[?w.asset, ?w.offhand?.asset],
      'assets/models/UAL1_Standard.glb',
    ]);

/// Where [w]'s prop sits in the hand holding it, as the holder node's local
/// transform under that hand joint. Shared by the level and the hero
/// picker's preview.
///
/// The handle is pointed down the measured hole through the fist
/// ([kGrips]), rolled [roll] quarter turns about it, and its own hold point
/// brought into the palm. An [WeaponKind.upright] weapon is instead posed in
/// the world and the hand undone ([hand], the hand joint's global transform —
/// re-solved each frame, since it fights the animation): it stands up and,
/// with a [WeaponKind.pointAxis], points along [forward].
vm.Matrix4 weaponPose(
  WeaponKind w, {
  int roll = 0,
  vm.Matrix4? hand,
  vm.Vector3? forward,
}) {
  final axis =
      vm.Vector3(w.modelAxis.$1, w.modelAxis.$2, w.modelAxis.$3).normalized();
  final grip = kGrips[w.hand] ?? kGrips['hand_r']!;
  final point = w.pointAxis;
  // Point the handle down the hole through this fist first.
  final onGrip = vm.Quaternion.fromTwoVectors(axis, grip.axis);
  var aim = (vm.Quaternion.axisAngle(grip.axis, roll * math.pi / 2) * onGrip)
      .asRotationMatrix();

  if (w.upright && hand != null) {
    // Pose it in the world and then undo the hand: whatever the animation
    // has done to the joint, the prop comes out standing up — and, if it has
    // a business end, pointing where the hero is going rather than wherever
    // a knuckle happens to face.
    final up = vm.Vector3(0, 1, 0);
    var world = vm.Quaternion.fromTwoVectors(axis, up).asRotationMatrix();
    if (point != null) {
      // Two axes to satisfy at once, so map one basis onto another: the
      // prop's own (third, handle, muzzle) onto the world's (side, up,
      // facing). For orthonormal bases that rotation is T·Sᵀ.
      final facing = forward ?? vm.Vector3(1, 0, 0);
      final muzzle = vm.Vector3(point.$1, point.$2, point.$3).normalized();
      final source = vm.Matrix3.columns(axis.cross(muzzle), axis, muzzle);
      final target = vm.Matrix3.columns(up.cross(facing), up, facing);
      world = target * source.transposed();
    }
    // Undo the hand's whole 3×3, not a quaternion of it: the rig's global
    // matrix carries its scale and the importer's handedness flip, and a
    // reflection has no quaternion — which a staff (one axis to stand up)
    // got away with and a bow (up, and where it shoots) did not. The rig's
    // uniform scale is divided out, so the prop still inherits it.
    final linear = hand.getRotation();
    final s = math.pow(linear.determinant().abs(), 1 / 3).toDouble();
    aim = (linear.scaled(1 / s)..invert()) * world;
  }

  final m = vm.Matrix4.identity()
    ..setTranslation(grip.point)
    ..setRotation(aim);
  // Bring the prop's own hold point to the origin, so it is that point —
  // the grip, a fifth up the shaft — that ends up in the fist, rather than
  // whatever the modeller happened to put at (0,0,0).
  return m
    ..scaleByVector3(vm.Vector3(w.scale.$1, w.scale.$2, w.scale.$3))
    ..translateByVector3(
        -vm.Vector3(w.holdPoint.$1, w.holdPoint.$2, w.holdPoint.$3));
}

/// Take the gloss off a kit model without touching its colours.
///
/// The kit's material imports smooth and metallic, and an unset
/// `scene.environment` still resolves to a default studio IBL — so a
/// polished surface mirrors a studio that is not in this dungeon, which is
/// the white sheen these props arrived with. Rough them out and the palette
/// underneath takes the room's torchlight like everything else. Nothing a
/// hand holds is emissive: a glowing prop reads as a bug, and the Desync
/// light belongs to the bolt.
void matteProp(Node node) {
  for (final primitive in node.mesh?.primitives ?? const []) {
    final material = primitive.material;
    if (material is PhysicallyBasedMaterial) {
      material
        ..roughnessFactor = 1.0
        ..metallicFactor = 0.0
        ..emissiveFactor = vm.Vector4.zero();
    }
  }
  node.children.forEach(matteProp);
}

/// A shot in flight. Small enough to be a record if it were not for the node.
class Bolt {
  Bolt({
    required this.node,
    required this.x,
    required this.y,
    required this.vx,
    required this.hits,
    this.pierces = false,
  });

  final Node node;
  double x;
  final double y;
  final double vx;

  /// How much of an enemy's health this one carries.
  final int hits;

  /// Whether it flies on through what it hits (Piercing Charge).
  final bool pierces;

  /// The foes it has already struck, so a piercing bolt hits each once.
  final Set<Object> struck = {};
  int life = 150;
}

/// Where a handle has to pass through a fist, in that hand's own space.
///
/// Not a guess and not a control: the Universal Animation Library **never
/// animates the fingers** — index/middle/ring/pinky rotations are identical in
/// `Idle_Loop`, `Sword_Idle` and `Sword_Attack` — so a fist is one fixed shape
/// and the hole through it can simply be measured. Composing the finger chains
/// through that fixed pose puts the mid-phalanges around a centroid, and the
/// handle runs through it along index→pinky.
///
/// **Both hands, because they are mirrored.** The right hand's grip sits at
/// x=−0.042 and the left's at x=+0.040: mounting a left-hand prop with the
/// right hand's numbers puts it a whole palm's width outside the fist, which
/// is precisely as odd as it sounds. The X is the part a wrist-mounted prop
/// misses entirely — a hand bone's origin is its *wrist* — and the axis is
/// tilted ~17° off the hand's Z, which is the error no quarter-turn mount can
/// express.
typedef HandGrip = ({vm.Vector3 point, vm.Vector3 axis});

final Map<String, HandGrip> kGrips = {
  'hand_r': (
    point: vm.Vector3(-0.042, 0.114, -0.005),
    axis: vm.Vector3(-0.014, 0.306, 0.952).normalized(),
  ),
  'hand_l': (
    point: vm.Vector3(0.040, 0.121, -0.010),
    axis: vm.Vector3(0.009, 0.277, 0.961).normalized(),
  ),
};

/// A bolt's hitbox, as an offset from the top of the hero's 24-pixel body.
///
/// Taller than the orb that is drawn, on purpose. Flyers hover 19–24 px above
/// their floor, and a 6×6 box at chest height passed **1 px under** a Ghost
/// that was busy hurting him. 6 wide × 14 tall from 2 px down spans 8–22 px
/// above his feet: it reaches the Ghost and the GhostSkull and still crosses
/// the 16-px Birb. The Armabee (24–42) still needs a jump, which is fair for
/// the one enemy that cannot touch him from the ground either.
const double kBoltDrop = 2;
const double kBoltSize = 6;
const double kBoltHeight = 14;

/// How far in front of the hero the sword reaches, in engine pixels. **The**
/// combat knob: everything else a swing does — its timing, its animation, what
/// a hit costs — belongs to the engine or to the clip. Tune it against play,
/// with a human on the keys.
const double kSwingReach = 26;

/// The box a swing occupies, in front of whichever way the hero faces. Pulled
/// out of the widget for the same reason [aabbOverlap] was: reach is the thing
/// that gets tuned, so it has to be checkable without a scene.
(double, double) swingBox(
  double px,
  double pw, {
  required bool facingRight,
  double reach = kSwingReach,
}) =>
    (facingRight ? px + pw : px - reach, reach);

/// One instanced batch per (geometry, material) pair found in a loaded model.
///
/// A kit piece cloned per tile is one node, one render item and one cull test
/// **per tile** — which is what made traversal cost 15–31 fps with the whole
/// level resident. `InstancedMesh` collapses every copy of a piece into a
/// single draw, so a 110-tile level costs about what one tile did.
class TileBatcher {
  final Map<(Geometry, fs.Material), InstancedMesh> _batches = {};

  /// Registers one copy of [model] at [transform].
  ///
  /// The model's own hierarchy (including the importer's handedness flip,
  /// which lives on the loaded root's `localTransform`) is folded into each
  /// instance, so the result sits exactly where a cloned node would.
  void add(Node model, vm.Matrix4 transform) {
    void walk(Node node, vm.Matrix4 parent) {
      final here = parent.multiplied(node.localTransform);
      final mesh = node.mesh;
      if (mesh != null) {
        for (final p in mesh.primitives) {
          _batches
              .putIfAbsent(
                (p.geometry, p.material),
                () => InstancedMesh(
                  geometry: p.geometry,
                  material: p.material,
                  // The level spans 110 tiles; per-instance culling is what
                  // makes the off-screen ones free.
                  cullInstances: true,
                ),
              )
              .addInstance(here);
        }
      }
      for (final child in node.children) {
        walk(child, here);
      }
    }

    walk(model, transform);
  }

  /// Hands every batch to [add] (`scene.add`, or a parent node's) and returns
  /// the nodes, so a whole set can be shown or hidden at once.
  List<Node> attach(void Function(Node) add) {
    final nodes = <Node>[];
    for (final batch in _batches.values) {
      final node = Node()..addComponent(InstancedMeshComponent(batch));
      add(node);
      nodes.add(node);
    }
    return nodes;
  }

  int get instanceCount =>
      _batches.values.fold(0, (sum, b) => sum + b.instanceCount);
}

/// A canned input script, in fixed-step frames from the level's start.
///
/// It exists for two reasons. The obvious one: this harness cannot hold a key,
/// so a scripted run is the only way to *watch* a pickup or a contact happen.
/// The useful one: it is a deterministic input sequence, which is exactly what
/// the seed race needs — the same script must produce the same body state on
/// any machine, at any frame rate, because the sim is fixed-step and never
/// reads the renderer. `test/determinism_test.dart` pins that.
PlayerIntent scriptedIntent(int frame) {
  // Walk right the whole way, hopping regularly so ledges and the one-way
  // platforms get exercised rather than avoided.
  final jump = frame > 30 && frame % 75 == 0;
  return PlayerIntent(moveX: 1, jumpPressed: jump, jumpHeld: jump);
}

/// Frames on which the scripted run swings the sword.
bool scriptedAttack(int frame) => frame > 60 && frame % 50 == 0;

/// A collectible from the map's object layer. `fragment` is the level's
/// objective; `ability` is the metroidvania gate — it flips a flag the
/// **engine** owns, so the new traversal is the engine's behaviour, not a
/// renderer trick.
class Pickup {
  Pickup({
    required this.node,
    required this.light,
    required this.kind,
    required this.x,
    required this.y,
  });

  final Node node;
  final Node light;
  final String kind;

  /// Engine pixel space, y down — the frame contact is resolved in.
  final double x;
  final double y;

  bool taken = false;

  static const double size = 20;

  void take() {
    taken = true;
    node.visible = false;
    light.visible = false;
  }
}

/// A view-side enemy. Patrols, hurts the player on contact, dies to a sword
/// swing. None of this lives in the engine, and none of it writes to the
/// player's state except through `PlayerPhysics.hit`.
class Enemy {
  Enemy({
    required this.node,
    required this.model,
    required this.kind,
    required this.homeX,
    required this.y,
    required this.yOffset,
  });

  final Node node;
  final Node model;
  final String kind;
  final double homeX;
  final double y;
  final double yOffset;

  double x = 0;
  double dir = 1;
  bool alive = true;
  int deathTimer = 0;
  int hitStun = 0;
  int hp = 2;
  int idleTimer = 0;
  AnimationClip? clip;
  String clipName = '';

  /// The bundle's flyers hover; the rest walk. Playing `Walk` on a hovering
  /// bat is most of what made the monsters look wrong.
  static const Set<String> flyingKinds = {'GhostSkull', 'Armabee', 'Ghost'};
  bool get flies => flyingKinds.contains(kind);

  /// Hitboxes per species. One 22×22 box for a duck, a ghost and an orc is
  /// why some of them felt wrong to hit: the box has to match the silhouette
  /// the player is aiming at.
  static const Map<String, (double, double)> boxes = {
    'Birb': (18, 16),
    'Armabee': (20, 18),
    'GhostSkull': (22, 20),
    'Ghost': (22, 26),
    'Cactoro': (22, 24),
    'Mushnub': (24, 22),
    'Goleling': (24, 24),
    'OrcEnemy': (26, 28),
  };

  double get width => boxes[kind]?.$1 ?? 22;
  double get height => boxes[kind]?.$2 ?? 22;
  static const double range = 56;
  static const double speed = 0.45;

  double get centreX => homeX + x + width / 2;

  /// Plays the first of [suffixes] this species actually has — the bundle is
  /// not consistent (`HitRecieve` on some, `HitReact` on others).
  void setClipAny(List<String> suffixes, {bool loop = true}) {
    for (final suffix in suffixes) {
      if (model.parsedAnimations.any((a) => a.name.endsWith(suffix))) {
        setClip(suffix, loop: loop);
        return;
      }
    }
  }

  void setClip(String suffix, {bool loop = true}) {
    if (clipName == suffix) return;
    final animation = model.parsedAnimations.firstWhere(
      (a) => a.name.endsWith(suffix),
      orElse: () => model.parsedAnimations.first,
    );
    final old = clip;
    if (old != null) {
      old.pause();
      model.removeAnimationClip(old);
    }
    clip = model.createAnimationClip(animation)
      ..loop = loop
      ..play();
    clipName = suffix;
  }

  /// One fixed frame. Patrols between +/-[range] of its map position, pausing
  /// at each end so it reads as a creature rather than a metronome.
  void step() {
    if (!alive) {
      if (deathTimer > 0 && --deathTimer == 0) node.visible = false;
      return;
    }
    if (hitStun > 0) {
      hitStun--;
      return;
    }
    if (idleTimer > 0) {
      idleTimer--;
      setClipAny(flies ? ['Flying_Idle', 'Idle'] : ['Idle']);
      return;
    }

    x += dir * speed;
    if (x.abs() > range) {
      x = x.clamp(-range, range);
      dir = -dir;
      idleTimer = 40;
    }
    setClipAny(flies ? ['Fast_Flying', 'Flying_Idle'] : ['Walk']);
  }

  /// Returns true when the hit kills. Two hits, so a swing that connects is
  /// legible before anything disappears.
  /// Land [damage] at once — a two-damage hit is one hit, not two in a row
  /// (the first one's hit-stun would swallow the second). True if it died.
  bool takeHit({int damage = 1}) {
    if (!alive || hitStun > 0) return false;
    hp -= damage;
    hitStun = 26;
    clipName = '';
    if (hp > 0) {
      setClipAny(['HitRecieve', 'HitReact', 'Idle'], loop: false);
      return false;
    }
    die();
    return true;
  }

  void die() {
    if (!alive) return;
    alive = false;
    deathTimer = 90;
    clipName = '';
    setClipAny(['Death'], loop: false);
  }
}

vm.Vector4 _lin(int argb, {double gain = 1}) {
  double c(int sh) {
    final s = ((argb >> sh) & 0xFF) / 255.0;
    return (s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4))
            .toDouble() *
        gain;
  }

  return vm.Vector4(c(16), c(8), c(0), 1);
}

/// How high the camera may look: the top of the highest thing that can be
/// stood on. For level one this lands on 10.0.
double levelCeiling(List<String> rows, int height) {
  final topRow = rows.indexWhere((r) => r.contains('#') || r.contains('='));
  return (height - (topRow < 0 ? height : topRow)).toDouble();
}

/// What [buildLevelScene] leaves behind that the game still drives.
typedef LevelDressing = ({List<Node> torchLights, int batches, int instances});

/// Everything static a level draws — terrain, walls, dressing, torches,
/// spikes — added to [scene]. No hero, no enemies, no game state: the same
/// pieces the game shows, so a scene snapshot of a level is the level. Shared
/// with `snapshots/level_snapshot_test.dart`.
Future<LevelDressing> buildLevelScene(Scene scene, LevelSpec spec) async {
  final rows = spec.rows();
  final g = StringTileGrid(rows);
  final nRows = spec.height, nCols = spec.width;
  final camYMax = levelCeiling(rows, nRows);
  // Cell centres: the kit's models are centred on their origin, and the
  // engine's tile `col` spans x col..col+1.
  double worldX(int col) => tileToWorld(col, 0, nRows).x + 0.5;
  double worldY(int row) => tileToWorld(0, row, nRows).y;
  final torchLights = <Node>[];

  // --- terrain: only surfaces the camera can see ------------------------
  final floor =
      await glb('assets/levels/ruins/Floor_Standard.glb');
  final half = await glb(
      'assets/levels/ruins/Floor_Standard_Half.glb');
  final wall = await glb('assets/levels/ruins/Wall.glb');

  // Dressing variants. Picking them by a *seeded* generator keeps the
  // level identical on every machine — the view must not be another place
  // a run can differ (see determinism_test).
  final dress = math.Random(nCols * 31 + nRows);
  final wallBroken =
      await glb('assets/levels/ruins/Wall_Broken.glb');
  final wallOvergrown =
      await glb('assets/levels/ruins/Wall_Overgrown.glb');
  final column =
      await glb('assets/levels/ruins/Column_Round.glb');
  final torch = await glb('assets/levels/dungeon/Torch.glb');
  final spikes =
      await glb('assets/levels/dungeon/Spikes.glb');
  final stairs = await glb('assets/levels/ruins/Stairs.glb');
  final support =
      await glb('assets/levels/ruins/Support_Center.glb');
  final props = [
    for (final n in const [
      'ruins/Barrel.glb',
      'ruins/Crate.glb',
      'ruins/Pot1.glb',
      'ruins/Pot2_Broken.glb',
      'ruins/Bush_Round.glb',
      'dungeon/Skull.glb',
    ])
      await glb('assets/levels/$n'),
  ];

  // Static level pieces are batched, not cloned: see `TileBatcher`.
  //
  // One batch set. The camera is fixed on the near side of the play plane,
  // so the dressing only ever needs to exist behind it — the mirrored copy
  // that a free orbit required is pure cost here and is gone.
  // Ground reads by light, not by a bar on top of it. Kit stone against kit
  // stone is one mass at this camera, so what you can stand on is marked by a
  // glow — coloured by what that ground does: violet for solid ground (a
  // hairline set into its front face, just under the walking surface), cyan
  // for one-way ledges you can also jump up through (lit from beneath, below).
  // Over the bloom threshold on purpose: the bloom *is* the glow; the geometry
  // is only thin enough to feed it.
  final solidEdge = Node(
    mesh: Mesh(
      // One tile wide, exactly — the old 2.0 overhung every run of ledge.
      CuboidGeometry(vm.Vector3(1.0, 0.025, 0.02)),
      PhysicallyBasedMaterial()
        ..baseColorFactor = _lin(kSolidGlow)
        ..emissiveFactor = _lin(kSolidGlow, gain: 1.6)
        ..roughnessFactor = 1.0,
    ),
  );

  // Neon under every one-way ledge: the one kind of ground you can jump up
  // through, lit from beneath so it reads as different stone at a glance.
  // Over the bloom threshold, like the edges —
  // this one is meant to glow.
  final underglow = Node(
    mesh: Mesh(
      CuboidGeometry(vm.Vector3(1.0, 0.03, 0.9)),
      PhysicallyBasedMaterial()
        ..baseColorFactor = _lin(kOneWayGlow)
        ..emissiveFactor = _lin(kOneWayGlow, gain: 2.6)
        ..roughnessFactor = 1.0,
    ),
  );

  final batcher = TileBatcher();
  void place(Node src, double x, double y, double z,
      {double scale = _kit, double rotY = 0}) {
    // Authored z is "distance behind the play plane"; the camera looks
    // from -Z, so behind is +Z.
    final t = vm.Matrix4.translationValues(x, y, -z)
        .scaledByDouble(scale, scale, scale, 1);
    if (rotY != 0) t.rotateY(rotY);
    batcher.add(src, t);
  }


  for (var row = 0; row < nRows; row++) {
    for (var col = 0; col < nCols; col++) {
      final here = g.solidityAt(col, row);
      if (here == TileSolidity.empty) continue;
      final capped = g.solidityAt(col, row - 1) == TileSolidity.solid;
      if (here == TileSolidity.solid && capped) {
        // The body of the ground, under its surface: the same faces the
        // foundation uses below the map. Skipping these drew every terrace as
        // a thin slab over a void — invisible in levels whose ground sits on
        // the bottom row, glaring in a tall one like the Spire.
        final yb = worldY(row) - 1.0;
        place(wall, worldX(col), yb, -0.4);
        place(wall, worldX(col), yb, -1.6);
        continue;
      }

      final x = worldX(col);
      final y = worldY(row);
      place(here == TileSolidity.oneWayPlatform ? half : floor, x, y, 0);
      // Solid ground you can stand on: its glow on the front face, a hair
      // below the walking surface. `place` takes z as distance *behind* the
      // play plane, so the camera-side face is +0.5 here, not −0.5 — the
      // first try put this on the back face, where nobody could see it.
      if (here == TileSolidity.solid &&
          g.solidityAt(col, row - 1) == TileSolidity.empty) {
        place(solidEdge, x, y - 0.1, 0.51, scale: 1);
      }
      if (here == TileSolidity.oneWayPlatform) {
        // Flush with the stone's camera-side face (authored z +0.05 puts the
        // 0.9-deep strip at −0.5..+0.4), or the slab's own edge hides it.
        place(underglow, x, y - 0.09, 0.05, scale: 1);
        // A bracket under each end, so a ledge reads as built into the
        // wall rather than as a plank hanging in the dark.
        if (g.solidityAt(col - 1, row) != TileSolidity.oneWayPlatform ||
            g.solidityAt(col + 1, row) != TileSolidity.oneWayPlatform) {
          place(support, x, y - 1.0, -0.5, scale: _kit);
        }
      }
      // One-way ledges get the backdrop too. Dressing keyed off solid ground
      // only, so a climb of ledges over a pit — the whole Spire — stood in
      // front of bare, black wall.

      // Backdrop: two courses at different depths. Real parallax comes for
      // free from perspective — nothing has to fake it.
      final variant = dress.nextInt(6);
      place(
          variant == 0
              ? wallBroken
              : (variant == 1 ? wallOvergrown : wall),
          x,
          y,
          -1.3);
      place(wall, x, y + 1.0, -1.3);
      for (var course = 0; course < 2; course++) {
        place(wall, x, y + course, -2.8);
      }

      // Columns frame the corridor; torches are the only warm light in it.
      if (col % 7 == 3) place(column, x, y, -1.0, scale: _kit * 0.9);
      if (col % 10 == 1) {
        place(torch, x, y + 1.3, -1.05, scale: _kit * 1.1);
        final lamp = Node()
          ..position = vm.Vector3(x, y + 1.45, -0.9)
          ..addComponent(PointLightComponent(PointLight(
            color: vm.Vector3(1.0, 0.58, 0.26),
            // Enough to pool on the stone, not enough to light the room —
            // the Desync has to stay the brightest thing in Achrona.
            intensity: 5,
            range: 5,
          )));
        scene.add(lamp);
        torchLights.add(lamp);
      }

      // Clutter, but only where something can actually stand: on a solid
      // tile whose neighbour above is open. The old rule dressed every
      // exposed tile, which is how pots ended up hanging off ledges and
      // floating in doorways.
      final standable = here == TileSolidity.solid &&
          g.solidityAt(col, row - 1) == TileSolidity.empty;
      if (standable && dress.nextInt(5) == 0) {
        place(props[dress.nextInt(props.length)], x + 0.3, y, -0.55,
            scale: _kit * 0.9);
      }

      // Structure where the level changes height: a step down to the left
      // gets stairs, an overhang gets a support under its lip. This is the
      // difference between tiles that happen to be adjacent and a room
      // somebody built.
      if (standable) {
        final leftOpen = g.solidityAt(col - 1, row) == TileSolidity.empty;
        final rightOpen = g.solidityAt(col + 1, row) == TileSolidity.empty;
        final leftLower =
            leftOpen && g.solidityAt(col - 1, row + 1) == TileSolidity.solid;
        final rightLower = rightOpen &&
            g.solidityAt(col + 1, row + 1) == TileSolidity.solid;
        if (leftLower) {
          place(stairs, x - 1.0, y - 1.0, -0.2,
              scale: _kit * 0.9, rotY: math.pi);
        } else if (rightLower) {
          place(stairs, x + 1.0, y - 1.0, -0.2, scale: _kit * 0.9);
        }
        // A ledge with nothing under it gets a bracket, so it reads as
        // built rather than as floating stone.
        if ((leftOpen || rightOpen) &&
            g.solidityAt(col, row + 1) == TileSolidity.empty) {
          place(support, x, y - 1.0, -0.5, scale: _kit);
        }
      }
      // (No foreground silhouette layer: the floor tile is one unit deep,
      // so anything past z = 0.5 hangs in mid-air. It would need its own
      // ledge geometry to be worth having.)
    }
  }

  // ---------------------------------------------------------------
  // Enclose the room. A side-on camera in an open tile map looks into
  // black on three sides; a metroidvania room is a *room*. Everything
  // below is instanced, so a full enclosure costs a handful of batches
  // rather than a thousand nodes.
  // ---------------------------------------------------------------
  final banner =
      await glb('assets/levels/dungeon/Banner_wall.glb');
  final cobweb =
      await glb('assets/levels/dungeon/Cobweb.glb');
  final ceilingSlab =
      await glb('assets/levels/ruins/Floor_Standard.glb');
  final windowBars =
      await glb('assets/levels/ruins/Window_Bars.glb');

  // The camera sits 11 units back and covers roughly ±5 units vertically
  // around its target, which tracks the hero between y 4 and y 7. A
  // ceiling at 12 and a foundation down to -5 put the enclosure outside
  // the frame at every point the hero can reach.
  // Two above the highest thing that can be stood on, which for level one
  // is the 12.0 this used to be hardcoded to. Level two starts nineteen
  // units up: a fixed ceiling left its whole opening outside the room,
  // and the hero walked around in a black void.
  // Five above: the camera frames ~4.6 units above its target, and its target
  // can sit at camYMax. Two (the old value) left the void above the ceiling
  // in frame whenever the hero stood on the highest ledge.
  final ceilingY = camYMax + 5.0;
  const floorOfFrame = -5.0;

  // Overrun: the camera is allowed right up to the map's ends, so the
  // room has to continue past them or the enclosure runs out on screen.
  const overrun = 8;
  for (var col = -overrun; col < nCols + overrun; col++) {
    final x = worldX(col);
    final inMap = col >= 0 && col < nCols;

    // Deep backdrop: full height, so no gap in the map ever shows sky.
    for (var y = floorOfFrame; y <= ceilingY; y += 1.0) {
      place(wall, x, y, -3.2);
    }

    // Ceiling. It has to span the *whole* depth of the room, not just the
    // play plane: at a grazing angle down the corridor you look straight
    // through any gap in it, and a two-slab ceiling left two of them.
    place(ceilingSlab, x, ceilingY, 0);
    for (final z in const [-1.3, -2.6, -3.9]) {
      place(ceilingSlab, x, ceilingY, z);
    }
    if (col % 2 == 0) place(wall, x, ceilingY - 1, -1.3);
    if (col % 9 == 4) {
      place(cobweb, x, ceilingY - 1.1, -0.9, scale: _kit * 1.2);
    }
    if (col % 13 == 6) {
      place(banner, x, ceilingY - 2.4, -1.2, scale: _kit * 1.3);
    }

    // The upper wall is most of the frame, so it gets structure rather
    // than being left as a field of bricks: piers running floor to
    // ceiling, and barred windows to break the run between them.
    // A pier stands on the ground in its column — the highest solid tile —
    // not at a fixed height: `y = 5` was right for level one's floor and
    // floated over every pit and every lower floor after it. No ground, no
    // pier. Stacked at the column's own height (3.99 × 0.425 ≈ 1.7), so the
    // segments meet instead of leaving a gap every 2 units.
    if (col % 9 == 0 && inMap) {
      final top = rows.indexWhere((r) => r[col] == kSolid);
      if (top >= 0) {
        for (var y = worldY(top); y < ceilingY; y += 1.7) {
          place(column, x, y, -1.15, scale: _kit * 0.85);
        }
      }
    }
    if (col % 11 == 5) {
      place(windowBars, x, ceilingY - 4.0, -1.25, scale: _kit * 1.1);
      place(windowBars, x, ceilingY - 6.5, -1.25, scale: _kit * 1.1);
    }
    if (col % 17 == 9) {
      place(cobweb, x, ceilingY - 3.5, -1.0, scale: _kit * 0.9);
    }

    // Foundation: fill from the frame's floor up to whatever this column
    // stands on, so a ledge reads as carved rock rather than as a slab
    // floating over nothing. Columns that are pure pit keep their chasm —
    // the backdrop behind them is what stops it being black.
    var lowest = inMap ? -1 : nRows - 1;
    if (inMap) {
      for (var row = nRows - 1; row >= 0; row--) {
        if (g.solidityAt(col, row) == TileSolidity.solid) {
          lowest = row;
          break;
        }
      }
    }
    if (lowest >= 0) {
      for (var y = worldY(lowest) - 1; y >= floorOfFrame; y -= 1.0) {
        place(wall, x, y, -0.4);
        place(wall, x, y, -1.6);
      }
    }
  }

  // End caps. With the rig able to yaw ±17°, the far end of the corridor
  // comes into view at an angle; without these it is a hole in the room.
  for (final capCol in [-overrun, nCols + overrun - 1]) {
    final capX = worldX(capCol);
    for (var y = floorOfFrame; y <= ceilingY; y += 1.0) {
      for (var z = -3.2; z <= 2.0; z += 1.0) {
        place(wall, capX, y, z, rotY: math.pi / 2);
      }
    }
  }

  // Spikes are drawn here, before the batches attach. They used to be
  // placed from the game's object loop *after* `attach`, into a batch
  // nobody ever added to the scene — a hazard that hurt and was never seen.
  for (final (kind, col, row) in spec.objects) {
    if (kind == 'spikes') {
      final feet = objectFeet(col, row, nRows);
      place(spikes, feet.x, feet.y, 0, scale: _kit * 1.1);
    }
  }

  // Nothing in the level moves: cache its shadow instead of re-drawing it.
  final batchNodes = batcher.attach(scene.add);
  for (final n in batchNodes) {
    n.shadowStatic = true;
  }
  final batches = batchNodes.length;
  return (
    torchLights: torchLights,
    batches: batches,
    instances: batcher.instanceCount,
  );
}

/// One playable level. The class outlived its name: it plays whatever
/// [LevelSpec] it is handed, and the file keeps the name every build command
/// and doc already points at.
class LevelOne extends StatefulWidget {
  const LevelOne({
    super.key,
    this.spec = kLevelOne,
    this.hero = kRanger,
    this.onCleared,
    this.onNext,
  });

  /// Told when [spec]'s gate is reached — the globe marks its landmark.
  final ValueChanged<LevelSpec>? onCleared;

  /// Asked to go on to the next level. Without it (the standalone build) the
  /// level replaces its own route.
  final ValueChanged<LevelSpec>? onNext;

  final LevelSpec spec;

  /// Who plays it. Carried on to the next level.
  final HeroKind hero;

  @override
  State<LevelOne> createState() => _LevelOneState();
}

class _LevelOneState extends State<LevelOne> with SingleTickerProviderStateMixin {
  // --- engine-owned ---------------------------------------------------------
  StringTileGrid? grid;
  PlayerPhysics? body;
  int _moveX = 0;
  bool _jumpHeld = false;
  double _accumulator = 0;
  final List<Enemy> _enemies = [];
  final List<Pickup> _pickups = [];
  Pickup? _door;
  Node? _gateSealed;
  Node? _gateOpen;
  Node? _gateLight;

  /// Hazards, as (x, y) of their top-left in engine pixel space.
  final List<(double, double)> _hazards = [];
  int _fragments = 0;
  int _fragmentTotal = 0;
  bool _won = false;
  bool _gateLive = false;
  int _lives = 3;
  bool _gameOver = false;
  int _runFrames = 0;
  double _spawnX = 32;
  double _spawnY = 200;
  int _attackFrames = 0;
  int _deadFrames = 0;
  int _kills = 0;
  int _interactFrames = 0;

  /// The run→world link. Null when the build carries no Worker config, which
  /// is the normal offline case and must never cost anyone their ending.
  final RunLink? _runLink = RunLink.fromEnvironment();

  /// What the shared world did with this run, for the end screen. One push per
  /// run: `_pushed` is the guard, since a run ends exactly once.
  bool _pushed = false;
  String? _healLine;

  /// Which enemy `warp` visits next.
  int _warpIndex = 0;

  /// What he is holding, and the prop nodes hanging off his right hand — one
  /// per weapon, all mounted once and shown one at a time. Swapping visibility
  /// beats re-parenting into a joint every time the weapon changes.
  /// Starts as the hero's own weapon (the debug button still cycles).
  late int _weaponIndex =
      kWeapons.indexWhere((w) => w.label == widget.hero.weapon);
  final Map<int, Node> _props = {};

  /// The joint each weapon hangs off, kept so an upright one can be
  /// counter-rotated against whatever the animation is doing to it.
  final Map<int, Node> _hands = {};

  /// Each weapon's off-hand prop (the squire's shield) and the hand it is in.
  final Map<int, (Node, Node)> _offProps = {};
  WeaponKind get _weapon => kWeapons[_weaponIndex];

  /// Which way the prop sits in the fist, per weapon. Whose axes these are is
  /// a property of two models that have never met, so it is a control, not a
  /// constant — the same lesson as `face` and `foe`, and for the same reason
  /// it needs **two** axes: one quarter-turn control can only ever reach a
  /// quarter of the orientations.
  /// The one degree of freedom the measurement leaves: how the prop is rolled
  /// about the handle — whether the blade's flat faces the camera or its edge
  /// does. Per weapon, in quarter turns.
  final List<int> _roll = List.filled(kWeapons.length, 0);

  /// Shots in flight.
  final List<Bolt> _bolts = [];

  /// How far the hero is turned toward the camera, in degrees. A pure profile
  /// hides his sword arm — it is the far one, and the swing is right-handed
  /// (measured: `Sword_Attack` moves the right arm three to ten times more
  /// than the left), so the fix is the three-quarter view every side-scroller
  /// with a 3D character uses. Which sign turns him toward the lens depends on
  /// how two models and a camera agree, so it is a control.
  /// −26° is the one: +26 turns his back to the lens. Settled by clicking,
  /// which is the only way two models and a camera ever agree.
  static const List<double> kLeans = [kHeroLean, 26, -40, 40, 0];
  int _leanIndex = 0;
  double get _lean => kLeans[_leanIndex] * math.pi / 180;

  /// The opening. While it runs the sim is frozen and the camera looks where
  /// the script says; null once it has been played.
  CutscenePlayer? _cutscene;

  /// The shot the opening is currently on: where the camera started, where it
  /// is going, and how long it has to get there. Null means "on the hero",
  /// which is also the normal state of the game.
  double? _shotFrom;
  double _shotTo = 0;
  double _shotSeconds = 1;
  double _shotElapsed = 0;
  int _attackActive = 0;
  int _hitFlash = 0;

  /// The Desync glitch over the whole frame (`shaders/desync.frag` as a
  /// `PostEffect`). Null when the shader bundle did not load: the game plays
  /// on without it rather than failing.
  PostEffect? _desyncFx;

  /// Glitch intensity, 0–1. Same rule as the 2D game: events spike it, it
  /// decays at 1.4/s toward a faint baseline while you play.
  double _desync = 0;
  int _lastIFrames = 0;
  bool _wasDead = false;

  /// Spike the glitch (never lowers it — the decay handles the falloff).
  void _pulseDesync(double to) =>
      _desync = math.max(_desync, to.clamp(0.0, 1.0));
  Node? _swingLight;
  /// Yaw, in quarter turns, that points the model along screen-right.
  /// Cycled live by the `face` button: four options, so the right one is at
  /// most three clicks away instead of a rebuild and another guess.
  int _faceQuarter = kHeroFacing;
  double get _faceYaw => quarterTurns(_faceQuarter);

  /// The same, for the monsters. They are a different pack with their own
  /// authored forward, so one constant cannot serve both — which is why they
  /// walked backwards even after the hero was fixed.
  int _foeQuarter = kFoeFacing;
  double get _foeYaw => quarterTurns(_foeQuarter);
  int _fell = 0;
  int _profileFrame = 0;
  int _streamFrame = 0;
  double _camX = 0;
  double _camY = 6;
  int _cols = 0;

  double _minFps = 999;
  double _minFpsX = 0;
  final List<String> _profile = [];
  bool _demo = false;
  int _demoFrame = 0;

  /// Perf bisect handles. fps drops from 60+ to ~20 by mid-level; these let
  /// the cause be isolated live, at the spot it happens, instead of guessed.

  final List<Node> _torchLights = [];
  final List<Node> _pickupLights = [];
  bool _torchOn = true;
  bool _pickupLightOn = true;
  bool _postOn = true;

  // --- view -----------------------------------------------------------------
  final Scene scene = Scene();
  final FocusNode _focus = FocusNode();
  Node? camera;
  Node? heroPivot;
  Node? _heroNode;
  Node? clipLib;
  /// The clips playing now: one per hero part, started together.
  List<AnimationClip> _clips = [];

  /// The hero's head and hair — the parts that are not the outfit.
  final List<Node> _heroExtras = [];
  String _clipName = '';
  Node? _cam;

  /// The rig is **fixed**: side-on, on the near side of the play plane, at a
  /// constant angle and distance. It follows the hero's position and does
  /// nothing else — no orbit, no dolly, no input. A side-scroller's camera is
  /// framing, not a thing the player operates, and holding it still is what
  /// lets the room be a one-sided set. The rig itself is [cameraEye] in the
  /// kit; this only follows the hero.
  void _placeCamera(double dt) {
    final cam = _cam;
    if (cam == null) return;
    final target = vm.Vector3(_camX, _camY, 0);
    final eye = cameraEye(target);
    cam.lookAtFrom(eye, target);
  }
  int _rows = 0;

  /// The camera's vertical ceiling, derived from the level (see `_build`).
  double _camYMax = 10;

  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _fps = 0;
  Object? error;
  String _stats = '';

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    try {
      // Every download at once (most already running since ENTER); the
      // parsing below then never waits on the network.
      await Future.wait(
          [Scene.initializeStaticResources(), prefetchLevel(widget.spec, widget.hero)]);

      // The engine owns collision, as always — `StringTileGrid` is its class,
      // and `solidityAt` is the only question the renderer asks about it.
      final spec = widget.spec;
      final rows = spec.rows();
      final g = StringTileGrid(rows);
      grid = g;
      _rows = spec.height;
      _cols = spec.width;
      _camYMax = levelCeiling(rows, _rows);

      final dressing = await buildLevelScene(scene, spec);
      _torchLights.addAll(dressing.torchLights);
      final batches = dressing.batches;
      final instances = dressing.instances;

      // --- objects ----------------------------------------------------------
      // Authored in tile coordinates: `col, row` is the empty cell the object
      // occupies, and it stands on that cell's floor — `objectFeet` in the kit,
      // `(row + 1) * 16` in the engine's pixel space. This used to take the
      // cell's *top*, which put every object a tile in the air.
      double objX(int col) => (col * 16).toDouble();
      double objFeetY(int row) => ((row + 1) * 16).toDouble();
      double feetY(int row) => objectFeet(0, row, _rows).y;

      var enemies = 0;
      for (final (kind, col, row) in spec.objects) {
        final ox = objX(col);
        final oy = objFeetY(row);

        if (kind == 'spawn') {
          _spawnX = ox;
          _spawnY = oy - 24;
          continue;
        }

        if (kind == 'fragment' || kind == 'ability') {
          // Pickups as Desync light, the same language as the globe's heal.
          final cyan = kind == 'ability';
          final worldY = feetY(row) + 0.7;
          final orb = Node(
            mesh: Mesh(
              SphereGeometry(
                  radius: cyan ? 0.30 : 0.18, segments: 16, rings: 12),
              PhysicallyBasedMaterial()
                ..baseColorFactor = _lin(cyan ? _cyan : _neon)
                ..emissiveFactor = _lin(cyan ? _cyan : _neon, gain: 8.0),
            ),
          )..position = vm.Vector3((ox + 8) * _px, worldY, -0.2);
          final glow = Node()
            ..position = vm.Vector3((ox + 8) * _px, worldY, -0.2)
            ..addComponent(PointLightComponent(PointLight(
              color: cyan
                  ? vm.Vector3(0.17, 0.89, 1.0)
                  : vm.Vector3(0.69, 0.30, 1.0),
              intensity: cyan ? 9 : 6,
              range: cyan ? 9 : 6,
            )));
          scene
            ..add(orb)
            ..add(glow);
          _pickupLights.add(glow);
          _pickups.add(Pickup(
            node: orb,
            light: glow,
            kind: kind,
            x: ox + 8 - Pickup.size / 2,
            y: oy - Pickup.size,
          ));
          if (kind == 'fragment') _fragmentTotal++;
          continue;
        }

        if (kind == 'spikes') {
          // A hazard is just a static box that calls the engine's `hit`; its
          // model is level dressing, drawn by `buildLevelScene`.
          _hazards.add((ox, oy - 14));
          continue;
        }

        if (kind == 'gate') {
          // Two doors in the same hole: sealed until the fragments are in,
          // then the open one takes over. The swap *is* the reward.
          final sealedDoor = await glb(
              'assets/levels/ruins/Doors_GothicArch_Covered.glb');
          final openDoor = await glb(
              'assets/levels/ruins/Doors_GothicArch.glb');
          vm.Matrix4 doorAt() =>
              vm.Matrix4.translationValues(_worldX(col), feetY(row), 0.5)
                  .scaledByDouble(_kit, _kit, _kit, 1);
          _gateSealed = Node()
            ..localTransform = doorAt()
            ..add(sealedDoor);
          _gateOpen = Node()
            ..localTransform = doorAt()
            ..add(openDoor)
            ..visible = false;
          scene
            ..add(_gateSealed!)
            ..add(_gateOpen!);
          // The gate glows once it is live, so "go there" needs no arrow.
          _gateLight = Node()
            ..position = vm.Vector3(_worldX(col), feetY(row) + 1.4, -0.4)
            ..addComponent(PointLightComponent(PointLight(
              color: vm.Vector3(0.17, 0.89, 1.0),
              intensity: 14,
              range: 11,
            )))
            ..visible = false;
          scene.add(_gateLight!);
          _door = Pickup(
            node: _gateOpen!,
            light: _gateOpen!,
            kind: 'gate',
            x: ox + 8 - 20,
            y: oy - 48,
          );
          continue;
        }

        if (kind.startsWith('enemy:')) {
          final species = kind.substring(6);
          final model =
              await glb('assets/enemies/$species.glb');
          // The monsters carry their own clips (`CharacterArmature|Idle`),
          // not the humanoid library's — two animation systems, as expected.
          final holder = Node()..add(model);
          scene.add(holder);
          _enemies.add(Enemy(
            node: holder,
            model: model,
            kind: species,
            homeX: ox,
            y: feetY(row) + (_enemyYOffset[species] ?? 0),
            yOffset: 0,
          )..setClip('Idle'));
          enemies++;
        }
      }

      // --- hero -------------------------------------------------------------
      // Locked at the start. The map's `ability` object is what unlocks the
      // traversal, and it does so by setting the engine's own flags.
      body = PlayerPhysics(x: _spawnX, y: _spawnY, maxHp: widget.hero.hearts)
        // Void Step: the dash is hers before the core grants it.
        ..hasDash = widget.hero.dashesFromStart;

      // A hero is an outfit worn over a base head (and hair), each its own
      // glTF on the same rig. The outfit is the primary model — the weapons
      // mount on its hand bones — and every part plays every clip together.
      Future<Node> part(String file) => gltf('assets/models/ranger/$file');

      final hero = await part(widget.hero.outfit);
      _heroExtras
        ..add(await part(widget.hero.body))
        ..addAll([if (widget.hero.hair != null) await part(widget.hero.hair!)]);
      // No arc mesh. The first attempt drew a glowing sweep on every swing,
      // which read as a blue flash rather than as a blade — swinging at air
      // should look like swinging at air. What a player needs to see is the
      // *connect*, so only that is drawn now: a short flare at the point of
      // contact, on top of the enemy's own hit reaction.
      _swingLight = Node()
        ..addComponent(PointLightComponent(PointLight(
          color: vm.Vector3(0.17, 0.89, 1.0),
          intensity: 6,
          range: 4,
        )))
        ..visible = false;
      scene.add(_swingLight!);

      final pivot = Node()..add(hero);
      _heroExtras.forEach(pivot.add);
      scene.add(pivot);
      heroPivot = pivot;
      _heroNode = hero;

      // Weapons, into the fist the rig already has. `hand_r` is a joint, and a
      // joint is an ordinary Node in this renderer — so a prop parented to it
      // inherits the animation for free, with no bone-following code at all.
      for (final (index, weapon) in kWeapons.indexed) {
        final asset = weapon.asset;
        final hand = hero.getChildByName(weapon.hand);
        if (asset != null && hand != null) {
          _hands[index] = hand;
          final prop = await glb(asset);
          // These kits paint every part from one palette atlas, so the blade,
          // the grip and the pommel are already different colours — as long as
          // the atlas is *in* the file (see tool/embed_texture.py; a .glb
          // cannot resolve the external `Textures/colormap.png` these ship
          // with, which is why they imported white). Keep all of it and fix
          // only the shading.
          matteProp(prop);
          // A loaded model's own transform IS the importer's handedness flip
          // (06-SEAM-SPIKE). Never set position on it — wrap it.
          final holder = Node()..add(prop);
          hand.add(holder);
          _props[index] = holder;
        }
        // The other hand's prop, mounted the same way.
        final off = weapon.offhand;
        final offHand = off == null ? null : hero.getChildByName(off.hand);
        if (off?.asset != null && offHand != null) {
          final prop = await glb(off!.asset!);
          matteProp(prop);
          final holder = Node()..add(prop);
          offHand.add(holder);
          _offProps[index] = (holder, offHand);
        }
      }
      _applyWeapon();

      clipLib = await loadClips();
      _setClip('Idle_Loop');

      dressLevelLighting(scene);
      _desyncFx = await addDesyncEffect(scene);

      _camX = _spawnX * _px;
      // The hero's feet, not his spawn box: the same conversion the tick uses.
      _camY = (_rows * 16 - (_spawnY + 24)) * _px + 1.8;
      final cam = Node()
        ..addComponent(CameraComponent(
          activateOnMount: true,
          projection: PerspectiveProjection(near: 0.5, far: 120),
        ));
      scene.add(cam);
      _cam = cam;
      _placeCamera(0);

      _stats = '$instances instances in $batches batches · $enemies enemies';

      // The opening, only if there is a gate to open on. A map without one is
      // still playable, so it starts rather than crashing on a null.
      // Put the hero on the ground before the opening freezes the sim, or he
      // spends it hanging in the air where he was placed. The physics decides
      // where "the ground" is — a hand-computed spawn height would be a second
      // opinion about the thing the engine owns.
      // Step until he stops moving, not until the pose says midair: a body
      // that has not been stepped yet still reports `standing` while hanging
      // in the air, so that test exits on the first iteration and settles
      // nothing. The spec test guarantees solid ground under every spawn, so
      // this always lands.
      for (var i = 0, lastY = double.nan; i < 240; i++) {
        // Settled means both: he has stopped moving AND the engine has stopped
        // calling him airborne. Testing only the pose exits on the first
        // iteration (an unstepped body reports `standing` in mid-air), and
        // testing only the height leaves the freeze holding a `Jump_Loop`.
        if (body!.y == lastY && body!.pose != PlayerPose.midair) break;
        lastY = body!.y;
        body!.step(const PlayerIntent(), g);
      }

      final gate = _door;
      if (gate != null) {
        _cutscene = CutscenePlayer(levelIntro(
          pan: (from, to, seconds) {
            _shotFrom = from;
            _shotTo = to;
            _shotSeconds = seconds;
            _shotElapsed = 0;
          },
          cutToHero: () => _shotFrom = null,
          gateWorldX: gate.x * _px,
          lines: spec.intro,
        ));
      }

      // Compile every pipeline the level will draw now, behind the loading
      // spinner, not the first time each piece scrolls into view: on the
      // web a first draw of a material compiles its shader on the spot, and
      // that was a hitch every time a running hero reached something new.
      // Every torch on for it, so the lit variants are among them; light
      // streaming turns the far ones off again within a few frames.
      for (final lamp in _torchLights) {
        lamp.visible = true;
      }
      await scene.warmUp(
        [RenderView(camera: cam.getComponent<CameraComponent>()!.toCamera())],
        includeOffscreen: true,
      );

      if (mounted) setState(() => camera = cam);
      _ticker = createTicker(_tick)..start();
    } catch (e, st) {
      debugPrint('level1 spike failed: $e\n$st');
      if (mounted) setState(() => error = e);
    }
  }

  double _worldX(int col) => objectFeet(col, 0, _rows).x;

  void _setClip(String name, {bool loop = true}) {
    final hero = _heroNode;
    final animation = clipLib?.findAnimationByName(name);
    if (hero == null || animation == null || name == _clipName) return;
    final parts = [hero, ..._heroExtras];
    for (final (i, c) in _clips.indexed) {
      c.pause();
      parts[i].removeAnimationClip(c);
    }
    _clips = [
      for (final p in parts)
        p.createAnimationClip(animation)
          ..loop = loop
          ..playbackTimeScale =
              name == _weapon.attack ? widget.hero.attackSpeed(_weapon) : 1
          ..play(),
    ];
    _clipName = name;
  }

  /// On to the next level, if this one has one and you have finished it.
  ///
  /// A whole new widget rather than a rebuilt scene: every node, batch, light
  /// and clip this level loaded belongs to this `State`, so the cheapest
  /// correct teardown is to let Flutter drop it and build the next one from
  /// nothing. A level load is a few seconds — the same few seconds the first
  /// one costs — and that is honest about what is happening.
  void _nextLevel() {
    final next = widget.spec.next;
    if (!_won || next == null) return;
    final onNext = widget.onNext;
    if (onNext != null) return onNext(next);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
          builder: (_) => LevelOne(spec: next, hero: widget.hero)),
    );
  }

  /// Back to the start of the level, with everything reset. Cheap because
  /// nothing in the scene is destroyed — only the run's state is.
  void _restart() {
    final b = body;
    if (b == null) return;
    setState(() {
      b.respawn(_spawnX, _spawnY);
      _lives = 3;
      for (final bolt in _bolts) {
        scene.remove(bolt.node);
      }
      _bolts.clear();
      _gameOver = false;
      _won = false;
      _pushed = false;
      _healLine = null;
      _gateLive = false;
      _fragments = 0;
      _kills = 0;
      _fell = 0;
      _runFrames = 0;
      _deadFrames = 0;
      _gateSealed?.visible = true;
      _gateOpen?.visible = false;
      _gateLight?.visible = false;
      for (final p in _pickups) {
        p.taken = false;
        p.node.visible = true;
        p.light.visible = true;
      }
      for (final e in _enemies) {
        e.alive = true;
        e.hp = 2;
        e.hitStun = 0;
        e.deathTimer = 0;
        e.node.visible = true;
        e.clipName = '';
      }
    });
  }

  /// Starts a swing that lasts exactly as long as the clip does.
  ///
  /// The old fixed 24 frames cut `Sword_Attack` off mid-swing and dropped
  /// straight back to idle from whatever pose it happened to be in. The
  /// library knows its own length — `Animation.endTime` — so ask it.
  void _attack() {
    if (_attackFrames > 0) return;
    final swing = clipLib?.findAnimationByName(_weapon.attack);
    _attackFrames = swing == null
        ? 24
        : (swing.endTime * 60 / widget.hero.attackSpeed(_weapon)).round();
    // The blade connects in the middle of the swing, not on the wind-up.
    _attackActive = (_attackFrames * 0.75).round();
  }

  /// Engine state → animation. The Universal Animation Library ships 43 clips
  /// in the free tier and the first pass used eight of them; this is the map
  /// from what `PlayerPhysics` actually reports to what the hero does.
  ///
  /// Locomotion picks by *speed*, not by a boolean: the engine reports `vx` in
  /// px/frame, so walk, jog and sprint fall out of the same run state and the
  /// hero stops looking like he has one gear.
  (String, bool) _clipFor(PlayerPhysics b) {
    if (b.isDead) return ('Death01', false);
    if (b.invincibilityFrames > 40) return ('Hit_Chest', false);
    if (_attackFrames > 0) return (_weapon.attack, false);
    if (b.isDashing) return ('Roll', false);
    if (_interactFrames > 0) return ('Interact', false);

    final speed = b.vx.abs();
    switch (b.pose) {
      case PlayerPose.running:
        if (speed > 2.4) return ('Sprint_Loop', true);
        if (speed > 1.2) return ('Jog_Fwd_Loop', true);
        return ('Walk_Loop', true);
      case PlayerPose.jumping:
        return ('Jump_Start', false);
      case PlayerPose.midair:
        return ('Jump_Loop', true);
      case PlayerPose.landing:
        return ('Jump_Land', false);
      case PlayerPose.crouching:
        return speed > 0.3
            ? ('Crouch_Fwd_Loop', true)
            : ('Crouch_Idle_Loop', true);
      case PlayerPose.skidding:
        return ('Walk_Formal_Loop', true);
      case PlayerPose.hurt:
        return ('Hit_Chest', false);
      case PlayerPose.standing:
        // The torch idle when the room is dark enough to want one, otherwise
        // the plain one. Free variety from a library that already has it.
        // The weapon's own idle once there is one — a man holding a staff
        // should not stand like a man holding nothing.
        return (_gateLive ? 'Idle_Talking_Loop' : _weapon.idle, true);
    }
  }

  /// The opening's current line, or null when it is not playing.
  String? get _caption {
    final intro = _cutscene;
    return intro == null || intro.isDone ? null : intro.caption;
  }

  /// Show the current weapon's prop and hide the rest, posed by
  /// [weaponPose] in the grip the `grip` control is currently on.
  void _applyWeapon() {
    for (final entry in _props.entries) {
      final holder = entry.value;
      holder.visible = entry.key == _weaponIndex;
      if (!holder.visible) continue;
      final hand = _hands[_weaponIndex];
      holder.localTransform = weaponPose(
        _weapon,
        roll: _roll[_weaponIndex],
        hand: _weapon.upright ? hand?.globalTransform : null,
        forward: vm.Vector3(body!.facingRight ? 1.0 : -1.0, 0, 0),
      );
    }
    for (final MapEntry(key: i, value: (holder, hand)) in _offProps.entries) {
      holder.visible = i == _weaponIndex;
      if (!holder.visible) continue;
      final side = body!.facingRight ? 1.0 : -1.0;
      holder.localTransform = weaponPose(
        _weapon.offhand!,
        hand: hand.globalTransform,
        // Faced forward and turned toward the lens, like his lean: square to
        // where he walks, a shield is a plank seen edge-on.
        forward: vm.Vector3(side * (1 - kShieldToLens), 0, -kShieldToLens)
            .normalized(),
      );
    }
  }

  /// Fire the current weapon's shot from the hand, forward.
  void _fireBolt(PlayerPhysics b) {
    final colour = _weapon.boltColour ?? _cyan;
    final node = Node(
      mesh: Mesh(
        SphereGeometry(radius: _weapon.boltRadius, segments: 10, rings: 8),
        PhysicallyBasedMaterial()
          ..baseColorFactor = _lin(colour)
          ..emissiveFactor = _lin(colour, gain: 9.0),
      ),
    );
    scene.add(node);
    final bolt = Bolt(
      node: node,
      x: b.facingRight ? b.x + b.width + _weapon.reach : b.x - _weapon.reach,
      y: b.y + kBoltDrop,
      vx: b.facingRight ? _weapon.boltSpeed : -_weapon.boltSpeed,
      hits: _weapon.boltHits,
      pierces: widget.hero.pierces,
    );
    _placeBolt(bolt);
    _bolts.add(bolt);
  }

  /// Put a bolt's orb at the centre of its hitbox. The first version never
  /// did this at all: collision ran in engine space while every orb sat at the
  /// world origin, so a shot could land without anyone having seen it fly.
  void _placeBolt(Bolt bolt) {
    bolt.node.localTransform = vm.Matrix4.translationValues(
      (bolt.x + kBoltSize / 2) * _px,
      (_rows * 16 - (bolt.y + kBoltHeight / 2)) * _px,
      -0.25,
    );
  }

  /// One frame of every shot in flight: move, hit, or expire.
  void _stepBolts() {
    for (final bolt in [..._bolts]) {
      bolt.x += bolt.vx;
      _placeBolt(bolt);
      if (--bolt.life <= 0) {
        scene.remove(bolt.node);
        _bolts.remove(bolt);
        continue;
      }
      for (final e in _enemies) {
        if (!e.alive) continue;
        final ex = e.homeX + e.x;
        final eTop = _rows * 16 - (e.y * 16 + e.height);
        if (!aabbOverlap(bolt.x, bolt.y, kBoltSize, kBoltHeight, ex, eTop,
            e.width, e.height)) {
          continue;
        }
        // Piercing Charge: it carries on, but strikes each foe only once.
        if (!bolt.struck.add(e)) continue;
        if (e.takeHit(damage: bolt.hits)) _kills++;
        _hitFlash = 10;
        if (bolt.pierces) continue;
        scene.remove(bolt.node);
        _bolts.remove(bolt);
        break;
      }
    }
  }

  /// Why the last swing did or did not land, in one line.
  ///
  /// The repo's own lesson from the model-orientation rounds: do not reason
  /// about geometry from screenshots — put the numbers on screen and let the
  /// person holding the keys read them. A swing needs three things at once,
  /// so all three are shown: the active window, the way the hero is actually
  /// facing (which is engine state, not the direction the model is drawn), and
  /// the signed gap from the swing box to the nearest living enemy.
  String _swingReadout(PlayerPhysics b) {
    final (ax, aw) = swingBox(b.x, b.width, facingRight: b.facingRight);
    final swinging = _attackFrames > 0 && _attackFrames < _attackActive;
    final living = _enemies.where((e) => e.alive);
    if (living.isEmpty) return 'swing ${swinging ? 'LIVE' : '-'} · no enemies';

    var gap = double.infinity;
    Enemy? near;
    for (final e in living) {
      final ex = e.homeX + e.x;
      // Signed: negative once the box is inside the enemy.
      final d = ex > ax ? ex - (ax + aw) : ax - (ex + e.width);
      if (d < gap) {
        gap = d;
        near = e;
      }
    }
    final eTop = _rows * 16 - (near!.y * 16 + near.height);
    final vertical = b.y < eTop + near.height && b.y + b.height > eTop;
    return 'swing ${swinging ? 'LIVE' : _attackFrames > 0 ? 'windup' : '-'} '
        '($_attackFrames/$_attackActive) · facing ${b.facingRight ? 'R' : 'L'} '
        '· nearest ${near.kind} gap ${gap.toStringAsFixed(0)}px '
        '· heights ${vertical ? 'overlap' : 'MISS'}';
  }

  /// Push the finished run into the shared world.
  ///
  /// Fire-and-report: the run is over either way, so nothing here is awaited
  /// on the game's path and every failure lands as a line on the end screen
  /// rather than as an exception in the middle of somebody's victory.
  void _pushRun({required bool completed}) {
    if (_pushed) return;
    _pushed = true;
    final link = _runLink;
    if (link == null) {
      _healLine = 'offline — this run stayed here';
      return;
    }
    _healLine = 'telling Achrona…';
    link
        .submit(
      fragments: _fragments,
      kills: _kills,
      seconds: _runFrames / 60,
      completed: completed,
    )
        .then((heal) {
      if (!mounted) return;
      final total = heal.healed.fold<double>(0, (a, n) => a + n.drained);
      final rank = heal.rank == null ? '' : ' · #${heal.rank} today';
      setState(() => _healLine = switch (heal) {
            // Four different nothings, and saying the wrong one is worse than
            // saying nothing: a run that did not beat today's best (no energy,
            // by design), a team with nowhere to spend it (the D-04 cold
            // start), a run that earned nothing, and a real heal.
            (improved: false, score: _, rank: _, unlocked: _, healed: _) =>
              'not your best today — Achrona keeps that one$rank',
            (unlocked: 0, score: _, rank: _, improved: _, healed: _) =>
              'Achrona heard you, but this team has unlocked no nodes yet$rank',
            (healed: [], score: _, rank: _, improved: _, unlocked: _) =>
              'that run bought Achrona nothing$rank',
            _ => 'ACHRONA HEALS · ${heal.healed.length} node'
                '${heal.healed.length == 1 ? '' : 's'} cleansed by '
                '${total.toStringAsFixed(1)}$rank',
          });
    }).catchError((Object e) {
      if (mounted) setState(() => _healLine = 'the world did not answer: $e');
    });
  }

  /// One fixed simulation frame of everything the engine does not own.
  /// Runs inside the same 60 Hz loop as `PlayerPhysics.step`, so contact is
  /// frame-accurate rather than frame-rate dependent.
  void _simFrame(PlayerPhysics b) {
    // The Desync glitch: a hit is the corruption surging, death is a full
    // burst. Read off the engine's own state, so every source of damage
    // counts without each one having to remember to call it.
    if (b.invincibilityFrames > _lastIFrames) _pulseDesync(0.85);
    _lastIFrames = b.invincibilityFrames;
    if (b.isDead && !_wasDead) _pulseDesync(1);
    _wasDead = b.isDead;
    final playing = !_won && !_gameOver;
    _desync = math.max(playing ? 0.07 : 0.0, _desync - 1.4 / 60);
    setDesync(_desyncFx, _desync);

    if (_attackFrames > 0) _attackFrames--;
    if (_interactFrames > 0) _interactFrames--;
    if (_hitFlash > 0) _hitFlash--;

    if (b.isDead) {
      if (++_deadFrames > 70 && !_gameOver) {
        if (--_lives <= 0) {
          _gameOver = true;
          _pushRun(completed: false);
        } else {
          b.respawn(_spawnX, _spawnY);
        }
        _deadFrames = 0;
      }
      return;
    }
    if (!_won) _runFrames++;

    // `TileGrid` deliberately treats below-floor as empty (you can fall out of
    // a room, but not through its walls), so a pit falls forever unless
    // something owns a kill plane. That is game rules, not engine physics.
    if (b.y > _rows * 16 + 96) {
      b.hit(fromRight: false, damage: 1);
      b.respawn(_spawnX, _spawnY);
      _fell++;
    }

    final px = b.x, py = b.y, pw = b.width, ph = b.height;
    // The weapon's reach, in front of whichever way the hero faces.
    final (ax, aw) =
        swingBox(px, pw,
            facingRight: b.facingRight, reach: widget.hero.reach(_weapon));
    _stepBolts();

    // A ranged weapon does not reach anything — it lets go of something, once,
    // on the frame the animation would have connected. Once per cast, not once
    // per enemy: this used to sit inside the enemy loop and stacked a bolt for
    // every living monster on the same pixel.
    if (_weapon.ranged && _attackFrames == _attackActive - 1) _fireBolt(b);

    for (final p in _pickups) {
      if (p.taken) continue;
      if (!aabbOverlap(px, py, pw, ph, p.x, p.y, Pickup.size, Pickup.size)) {
        continue;
      }
      p.take();
      _interactFrames = 26;
      // A fragment ripples the corruption; the Desync core tears through it.
      _pulseDesync(p.kind == 'fragment' ? 0.5 : 0.85);
      if (p.kind == 'fragment') {
        _fragments++;
      } else {
        // The gate is the engine's flag, so the new traversal is the engine's
        // behaviour — the renderer only stopped drawing an orb.
        b.hasDoubleJump = true;
        b.hasDash = true;
      }
    }

    // Hazards. The engine already knows what a hit means; spikes just call it.
    for (final (hx, hy) in _hazards) {
      if (aabbOverlap(px, py, pw, ph, hx, hy, 16, 12)) {
        b.hit(fromRight: hx + 8 > px + pw / 2, damage: 1);
      }
    }

    // The gate. Sealed until every fragment is carried in, then it opens and
    // lights, which is the whole objective made visible without a UI arrow.
    if (!_gateLive && _fragments >= _fragmentTotal) {
      _gateLive = true;
      _gateSealed?.visible = false;
      _gateOpen?.visible = true;
      _gateLight?.visible = true;
    }

    final door = _door;
    if (door != null &&
        !_won &&
        _gateLive &&
        aabbOverlap(px, py, pw, ph, door.x, door.y, 40, 56)) {
      _won = true;
      _pushRun(completed: true);
      widget.onCleared?.call(widget.spec);
    }

    for (final e in _enemies) {
      e.step();
      if (!e.alive) continue;
      final ex = e.homeX + e.x;
      final ey = e.y * 16; // world units back to the engine's pixel space

      // Enemy y is in world units (y-up); the player's is pixels (y-down).
      // Compare in pixels, converting the enemy once.
      final eTop = _rows * 16 - (ey + e.height);

      // The swing only lands during its active window, not for the whole
      // animation — otherwise a swing that visibly misses still kills.
      final swinging = _attackFrames > 0 && _attackFrames < _attackActive;
      if (!_weapon.ranged &&
          swinging &&
          aabbOverlap(ax, py, aw, ph, ex, eTop, e.width, e.height)) {
        if (e.takeHit(damage: widget.hero.damage)) _kills++;
        _hitFlash = 10;
        continue;
      }

      if (aabbOverlap(px, py, pw, ph, ex, eTop, e.width, e.height)) {
        // The engine decides what a hit means: knockback, i-frames, hurt pose.
        b.hit(fromRight: e.centreX > px + pw / 2);
      }
    }
  }

  void _tick(Duration now) {
    final b = body;
    final g = grid;
    if (b == null || g == null) return;
    final dt =
        _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _fps = _fps == 0 ? 1 / dt : _fps * 0.9 + (1 / dt) * 0.1;

    // The opening owns the frame while it runs: no input, no physics, no
    // patrols, no run timer. The camera keeps updating below, which is what
    // makes it a cutscene rather than a still.
    final intro = _cutscene;
    final frozen = intro != null && !intro.isDone;
    if (frozen) intro.update(dt);

    _accumulator += dt.clamp(0.0, 0.25);
    const step = 1 / 60;
    while (_accumulator >= step) {
      if (frozen) {
        // The hero holds still, but a room where nothing else moves is a
        // photograph. The patrols keep walking through the opening — one call,
        // and it is the difference between a shot and a still.
        for (final enemy in _enemies) {
          enemy.step();
        }
        _accumulator -= step;
        continue;
      }
      if (_gameOver || _won) {
        _accumulator = 0;
        break;
      }
      if (_demo) {
        if (scriptedAttack(_demoFrame)) _attack();
        b.step(scriptedIntent(_demoFrame), g);
        _demoFrame++;
      } else {
        b.step(PlayerIntent(moveX: _moveX, jumpHeld: _jumpHeld), g);
      }
      _simFrame(b);
      _accumulator -= step;
    }

    final x = (b.x + b.width / 2) * _px;
    final y = (_rows * 16 - (b.y + b.height)) * _px;
    heroPivot?.localTransform = vm.Matrix4.translationValues(x, y, -0.25)
      // `_faceYaw` is the yaw that makes the model face **screen right**;
      // facing left is that plus 180°. Which value is correct is a property of
      // how the model was authored, so it is a control, not a constant.
      ..rotateY(_faceYaw + (b.facingRight ? 0 : math.pi) +
          (b.facingRight ? _lean : -_lean))
      ..rotateX(math.pi / 2);
    // Camera. A hard-locked target reads as the world sliding past a fixed
    // hero; a real side-scroller leads the run, lags a little, and does not
    // follow every hop. Three pieces:
    //
    //   look-ahead  — push the frame the way the hero faces, so the level
    //                 arrives on screen before the hero reaches it
    //   damping     — chase the goal, do not snap to it
    //   deadzone    — ignore vertical movement inside a band, so jumps do not
    //                 pump the whole frame up and down
    //   clamp       — never past the ends of the map, so the enclosure holds
    {
      // Horizontal: lead by *velocity*, not by a pose flag. Keying the lead
      // off `pose == running` made it snap from 0.9 to 2.6 units the instant
      // the hero started moving, which is the lurch on every start — and it
      // settled only because standing still put it back. `vx` is continuous,
      // so the lead grows with the run instead of stepping into place.
      final lead = (b.vx / 3.0).clamp(-1.0, 1.0) * 2.6;
      final goalX = (x + lead).clamp(-2.0, _cols + 2.0);
      final shotFrom = _shotFrom;
      if (frozen && shotFrom != null) {
        // The opening drives the camera outright. Handing it a goal and
        // letting the game's damping chase it is what produced a whip-pan:
        // that damping exists to catch a running hero, and a hundred tiles is
        // nothing to it. A shot moves at the speed the shot says.
        _shotElapsed += dt;
        final t = (_shotElapsed / _shotSeconds).clamp(0.0, 1.0);
        // Ease in and out, so the drift starts and stops instead of sliding.
        final e = t * t * (3 - 2 * t);
        _camX = shotFrom + (_shotTo - shotFrom) * e;
      } else if (frozen) {
        // A cut: the camera is simply already on the hero.
        _camX = goalX;
      } else {
        _camX += (goalX - _camX) * (1 - math.pow(0.002, dt).toDouble());
      }

      // Vertical: a deadzone the hero moves inside freely, and the camera
      // only picks him up once he leaves it. One rule, not a deadzone and a
      // chase fighting each other — the first version lost him down a pit
      // because a clamp stopped the chase while the deadzone kept giving.
      const dead = 1.7;
      final goalY = y + 1.6;
      var wantY = _camY;
      if (goalY > _camY + dead) wantY = goalY - dead;
      if (goalY < _camY - dead) wantY = goalY + dead;
      _camY += (wantY - _camY) * (1 - math.pow(0.05, dt).toDouble());

      // The ceiling is the level's own highest standable row, not a number
      // tuned against level one — level two starts at the top of a 26-row map
      // and a hardcoded 10 left the hero off the top of the screen.
      _camY = _camY.clamp(2.5, _camYMax);

      // The rig follows the hero's position and nothing else. Yaw, pitch and
      // distance are whatever the user last set them to.
      _placeCamera(dt);

    }

    // Stream the level around the hero. Level 1 is 110 tiles wide and the
    // camera sees roughly 20 of them, but every node was being submitted every
    // frame: the profile showed 15–31 fps while traversing and 64–75 the
    // moment the hero stopped at the level's end, which is draw submission
    // scaling with what is in view, not a bad patch of level.
    //
    // A window of ±16 units (the camera covers ~±10 at this framing) is enough
    // that nothing pops in at the edges. Lights get a tighter one: they are
    // the more expensive half, and a torch 14 units away contributes nothing.
    if (_streamFrame++ % 6 == 0) {
      // Geometry is instanced and culled per instance now; only the lights
      // still need a window, because every live point light costs every
      // fragment it touches.
      for (final lamp in _torchLights) {
        if (!_torchOn) continue;
        // Against the camera, not the hero: during the opening the view is
        // 100 tiles from him, and a pan into an unlit room is not a shot.
        lamp.visible = (lamp.position.x - _camX).abs() < 9;
      }
    }

    // A profile, not an anecdote: fps against position, once a second, so a
    // drop can be tied to a place in the level rather than to a feeling.
    // `debugPrint` does not reach the console in a release web build, so the
    // profile lives on screen: worst frame seen, and where in the level it
    // happened, plus a running sample so a drop can be tied to a place.
    if (++_profileFrame % 45 == 0) {
      if (_fps < _minFps && _profileFrame > 180) {
        _minFps = _fps;
        _minFpsX = b.x;
      }
      _profile.add('${b.x ~/ 16}:${_fps.toStringAsFixed(0)}');
      if (_profile.length > 14) _profile.removeAt(0);
    }

    // The classic i-frame blink, driven straight off the engine's counter.
    heroPivot?.visible =
        !b.isInvincible || (b.invincibilityFrames ~/ 4).isEven;

    final (clipName, clipLoops) = _clipFor(b);
    _setClip(clipName, loop: clipLoops);

    // Contact flare only.
    _swingLight
      ?..visible = _hitFlash > 0
      ..position = vm.Vector3(
          x + (b.facingRight ? 1.1 : -1.1), y + 0.9, -0.3);

    // An upright weapon is fighting the animation, so it has to be re-solved
    // once the hand has moved — which is now.
    if (_weapon.upright || _weapon.offhand != null) _applyWeapon();

    for (final e in _enemies) {
      // Same facing rule as the hero — the monsters were walking backwards
      // for exactly the reason he was.
      e.node.localTransform = vm.Matrix4.translationValues(
              e.centreX * _px, e.y, -0.1)
          .scaledByDouble(0.55, 0.55, 0.55, 1)
        ..rotateY(_foeYaw + (e.dir > 0 ? 0 : math.pi));
    }

    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final b = body;
    final down = e is KeyDownEvent;
    if (!down && e is! KeyUpEvent) return KeyEventResult.ignored;

    // Any key skips the opening, and skipping runs the rest of the script's
    // `onEnter`s — so the camera is handed back to the hero rather than left
    // pointed at the gate.
    final intro = _cutscene;
    if (down && intro != null && !intro.isDone) {
      setState(intro.skip);
      return KeyEventResult.handled;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyA:
        _moveX = down ? -1 : (_moveX == -1 ? 0 : _moveX);
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyD:
        _moveX = down ? 1 : (_moveX == 1 ? 0 : _moveX);
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyW:
      case LogicalKeyboardKey.arrowUp:
        _jumpHeld = down;
        if (down) b?.requestJump();
      case LogicalKeyboardKey.shiftLeft:
        if (down) b?.requestDash();
      case LogicalKeyboardKey.keyJ:
        if (down) _attack();
      case LogicalKeyboardKey.keyR:
        if (down) _restart();
      case LogicalKeyboardKey.keyN:
        if (down) _nextLevel();
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.keyG:
        // Back to the globe, when there is one underneath (the standalone
        // build has none).
        if (down) Navigator.of(context).maybePop();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0E1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Text('$error', style: const TextStyle(color: Color(0xFFFF6B8A))),
          ),
        ),
      );
    }
    final cam = camera;
    final b = body;
    if (cam == null || b == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0E1A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF07060C),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
                child: SceneView(scene, pixelRatio: kScenePixelRatio)),
            // The objective, in one line, always on screen.
            Positioned(
              left: 0,
              right: 0,
              top: 14,
              child: Text(
                _won || _caption != null
                    ? ''
                    : _gateLive
                        ? 'THE GATE IS OPEN — reach it'
                        : 'FIND $_fragmentTotal DESYNC FRAGMENTS '
                            '· $_fragments found',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _gateLive
                      ? const Color(0xFF2BE2FF)
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  letterSpacing: 2,
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              child: Text(
                kShowcase && !kShowStats
                    ? '${'♥' * b.hp}${'·' * (b.maxHp - b.hp)}  ·  lives $_lives'
                    : '${_fps.toStringAsFixed(0)} fps · $_stats · '
                '${'♥' * b.hp}${'·' * (b.maxHp - b.hp)} · '
                'lives $_lives · '
                '${b.isDead ? 'DEAD' : b.pose.name}'
                '${b.isInvincible ? ' (i-frames)' : ''} · '
                'fragments $_fragments/$_fragmentTotal · '
                '${b.hasDoubleJump ? 'DOUBLE JUMP' : 'locked'} · '
                'killed $_kills/${_enemies.length} · '

                'fell $_fell\n'
                // The combat readout. Tuning reach, i-frames or contact by
                // watching a monster fail to die is guesswork; this says which
                // of the three conditions a swing actually missed on.
                '${_swingReadout(b)}\n'
                'worst ${_minFps == 999 ? '-' : _minFps.toStringAsFixed(0)} fps '
                '@ tile ${(_minFpsX / 16).toStringAsFixed(0)} · '
                '${_profile.join(' ')}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
              ),
            ),
            // Letterbox. The cheapest possible signal that this is a shot and
            // not the game, and it does the work a fade would: the frame
            // changes shape, so the player stops reaching for the keys.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              top: 0,
              height: _caption != null ? 64 : 0,
              child: const ColoredBox(color: Colors.black),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: _caption != null ? 104 : 0,
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  // Keyed on the text, so one line dissolves into the next
                  // rather than being swapped out under the reader.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    child: Text(
                      _caption ?? '',
                      key: ValueKey(_caption),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF2BE2FF),
                        fontSize: 21,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_caption != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Text(
                  'any key to skip',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 11,
                      letterSpacing: 2),
                ),
              ),
            if (_won || _gameOver)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _won ? widget.spec.title : 'THE DESYNC TAKES YOU',
                        style: TextStyle(
                          color: _won
                              ? const Color(0xFF2BE2FF)
                              : const Color(0xFFFF6B8A),
                          fontSize: 34,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _won
                            ? '$_fragmentTotal fragments · $_kills of '
                                '${_enemies.length} cleared · '
                                '${(_runFrames / 60).toStringAsFixed(1)}s'
                            : 'out of lives · '
                                '$_fragments of $_fragmentTotal fragments',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14),
                      ),
                      if (_healLine != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          _healLine!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF2BE2FF),
                            fontSize: 15,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      Text(
                        _won
                            ? widget.spec.next == null
                                ? 'ACHRONA HOLDS — for now\nR to run it again'
                                : 'N — THE DESYNC DEEPENS\nR to run this one again'
                            : 'R to try again',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            height: 1.6),
                      ),
                      if (Navigator.of(context).canPop())
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'G — SEE WHAT IT DID TO ACHRONA',
                            style: TextStyle(
                                color: const Color(0xFF2BE2FF)
                                    .withValues(alpha: 0.8),
                                fontSize: 13,
                                letterSpacing: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 16,
              bottom: 44,
              child: Row(children: [
                _hold('◀', (d) => _moveX = d ? -1 : (_moveX == -1 ? 0 : _moveX)),
                const SizedBox(width: 10),
                _hold('▶', (d) => _moveX = d ? 1 : (_moveX == 1 ? 0 : _moveX)),
              ]),
            ),
            Positioned(
              right: 16,
              bottom: 44,
              child: Row(children: [
                // Tuning and debug controls; a showcase build has none.
                if (!kShowcase) ...[
                // Debug convenience: level 1 is 110 tiles wide and the first
                // enemy is 28 tiles in. Jumps to the next living one so combat
                // can be exercised without a 30-second walk.
                _hold(_torchOn ? 'lamps•' : 'lamps', (d) {
                  if (!d) return;
                  setState(() {
                    _torchOn = !_torchOn;
                    for (final n in _torchLights) {
                      n.visible = _torchOn;
                    }
                  });
                }),
                const SizedBox(width: 8),
                _hold(_pickupLightOn ? 'orbs•' : 'orbs', (d) {
                  if (!d) return;
                  setState(() {
                    _pickupLightOn = !_pickupLightOn;
                    for (final n in _pickupLights) {
                      n.visible = _pickupLightOn;
                    }
                  });
                }),
                const SizedBox(width: 8),
                _hold(_postOn ? 'post•' : 'post', (d) {
                  if (!d) return;
                  setState(() {
                    _postOn = !_postOn;
                    scene.environmentSettings = _postOn
                        ? EnvironmentSettings(
                            toneMapping: ToneMappingMode.aces,
                            exposure: 0.85,
                            colorGradingEnabled: true,
                            saturation: 1.12,
                            contrast: 1.16,
                            temperature: -0.1,
                            bloomEnabled: true,
                            bloomThreshold: 0.45,
                            bloomIntensity: 0.55,
                            bloomScatter: 0.85,
                            vignetteEnabled: true,
                            vignetteIntensity: 0.45,
                          )
                        : EnvironmentSettings(
                            toneMapping: ToneMappingMode.aces,
                            exposure: 0.85,
                          );
                  });
                }),
                const SizedBox(width: 8),
                _hold(_demo ? 'demo•' : 'demo', (d) {
                  if (!d) return;
                  setState(() {
                    _demo = !_demo;
                    _demoFrame = 0;
                  });
                }),
                const SizedBox(width: 10),
                _hold('warp', (d) {
                  if (!d) return;
                  final living = _enemies.where((e) => e.alive).toList();
                  if (living.isEmpty) return;
                  // Walkers first, and a different one each press. Always
                  // warping to enemy zero landed you under a hovering bat,
                  // which drops you to the floor out of everyone's reach —
                  // the probe looked like broken combat.
                  final walkers = living.where((e) => !e.flies).toList();
                  final pool = walkers.isEmpty ? living : walkers;
                  final e = pool[_warpIndex++ % pool.length];
                  // Its LIVE x, not its map position: a patrol wanders ±56px
                  // from home, so warping to `homeX` drops you anywhere from
                  // on top of it to two sword-lengths short — which is what
                  // made combat look broken when it was only out of reach.
                  // Land just inside reach, facing it, so one swing decides.
                  b.placeAt(e.homeX + e.x - kSwingReach,
                      _rows * 16 - e.y * 16 - 24);
                }),
                const SizedBox(width: 10),
                // Same reason `warp` is here: the ending — and the push into
                // the shared world that goes with it — is otherwise several
                // minutes of play away. Skips to the gate, so what it submits
                // is a real completion score for however long the run took,
                // with however little was collected on the way.
                _hold('gate', (d) {
                  if (!d || _won || _gameOver) return;
                  setState(() {
                    _won = true;
                    _pushRun(completed: true);
                  });
                  widget.onCleared?.call(widget.spec);
                }),
                const SizedBox(width: 10),
                // A full Desync burst on demand — the glitch is otherwise only
                // seen for a second after a hit, which is no way to judge it.
                _hold('desync', (d) {
                  if (d) _pulseDesync(1);
                }),
                const SizedBox(width: 10),
                _hold(_weapon.label, (d) {
                  if (!d) return;
                  setState(() {
                    _weaponIndex = (_weaponIndex + 1) % kWeapons.length;
                    _applyWeapon();
                    _clipName = ''; // force the idle to re-read
                  });
                }),
                const SizedBox(width: 10),
                _hold('roll ${_roll[_weaponIndex] * 90}°', (d) {
                  if (!d) return;
                  setState(() {
                    _roll[_weaponIndex] = (_roll[_weaponIndex] + 1) % 4;
                    _applyWeapon();
                  });
                }),
                const SizedBox(width: 10),
                _hold('lean ${kLeans[_leanIndex].toStringAsFixed(0)}°', (d) {
                  if (!d) return;
                  setState(() => _leanIndex = (_leanIndex + 1) % kLeans.length);
                }),
                const SizedBox(width: 10),
                _hold('face ${_faceQuarter * 90}°', (d) {
                  if (d) {
                    setState(() => _faceQuarter = (_faceQuarter + 1) % 4);
                  }
                }),
                const SizedBox(width: 10),
                _hold('foe ${_foeQuarter * 90}°', (d) {
                  if (d) {
                    setState(() => _foeQuarter = (_foeQuarter + 1) % 4);
                  }
                }),
                const SizedBox(width: 10),
                ],
                _hold('atk', (d) {
                  if (d) _attack();
                }),
                const SizedBox(width: 10),
                _hold('dash', (d) {
                  if (d) b.requestDash();
                }),
                const SizedBox(width: 10),
                _hold('jump', (d) {
                  _jumpHeld = d;
                  if (d) b.requestJump();
                }),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hold(String label, void Function(bool down) set) => Listener(
        onPointerDown: (_) => set(true),
        onPointerUp: (_) => set(false),
        onPointerCancel: (_) => set(false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: const TextStyle(color: Color(0xFF2BE2FF), fontSize: 16)),
        ),
      );
}
