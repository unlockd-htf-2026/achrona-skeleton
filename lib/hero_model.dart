/// A hero, loaded for show: the outfit, head and hair worn together, all
/// playing one clip (the bind pose lies flat — it is a clip that stands the
/// rig up). Shared by the hero picker's preview and the heroes snapshots.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'asset_cache.dart';
import 'globe/palette.dart';
import 'kit.dart';
import 'level_one.dart' show kWeapons, matteProp, weaponPose;

/// The clip library the heroes are rigged for. Parsed once and shared — the
/// picker and every level only look clips up in it by name.
Future<Node> loadClips() => _clips ??= () async {
      return glb('assets/models/UAL1_Standard.glb');
    }();
Future<Node>? _clips;

/// [hero]'s parts under one node, each playing [clip] on a loop. Still Z-up
/// as imported: wrap it in a parent to stand it (see the heroes snapshot).
Future<Node> loadHero(HeroKind hero, Animation clip) async {
  final root = Node();
  for (final part in hero.parts) {
    final node = await gltf('assets/models/ranger/$part');
    node.createAnimationClip(clip)
      ..loop = true
      ..play();
    root.add(node);
  }
  return root;
}

/// The hero picker's stage: every hero loaded once, holding their own weapon
/// in their weapon's idle, stood on a glowing ring — one shown at a time on
/// a slow turntable. Owns its [scene].
class HeroStage {
  HeroStage._(this.scene, this._heroes, this._turntable, this._props);

  final Scene scene;
  final List<Node> _heroes;
  final Node _turntable;

  /// Per hero: the weapon, the hand joint it hangs off and its holder — or
  /// null for bare fists.
  final List<List<(WeaponKind, Node, Node)>> _props;
  double _angle = 0;
  int _shown = 0;

  /// Eye and target for the stage's camera, framing a standing hero.
  static final vm.Vector3 eye = vm.Vector3(0, 1.25, -3.4),
      target = vm.Vector3(0, 0.95, 0);

  /// The one stage the app keeps: loading it pulls ~30 MB of models, clips
  /// and textures (and decodes every PNG), far too slow to redo each time the
  /// picker opens. The globe starts it in the background after it is up, so
  /// by the end of the opening it is ready; every picker reuses it.
  static Future<HeroStage> shared() => _shared ??= load();
  static Future<HeroStage>? _shared;

  static Future<HeroStage> load() async {
    final scene = Scene();
    dressLevelLighting(scene);
    // A portrait, not the dungeon: no distance fog.
    scene.environmentSettings.fogEnabled = false;
    // Every hero's parts, textures and props downloading at once, rather than
    // part by part as they are parsed.
    await prefetch([
      for (final h in kHeroes)
        for (final p in h.parts) 'assets/models/ranger/$p',
      for (final w in kWeapons) ...[?w.asset, ?w.offhand?.asset],
    ]);
    final clips = await loadClips();
    final turntable = Node();
    final heroes = <Node>[];
    final props = <List<(WeaponKind, Node, Node)>>[];
    for (final h in kHeroes) {
      final w = kWeapons.firstWhere((w) => w.label == h.weapon);
      // Their weapon's own idle: the pistol idle is what poses a gun hand.
      final idle = clips.findAnimationByName(w.idle) ??
          clips.findAnimationByName('Idle_Loop')!;
      final model = await loadHero(h, idle);
      // Stood up (Z-up import) and facing the camera, which sits on −Z.
      final stood = Node()
        ..add(model)
        ..localTransform = (vm.Matrix4.rotationY(math.pi)
          ..rotateX(math.pi / 2));
      heroes.add(stood);
      turntable.add(stood);
      // Held as the level holds it: on the outfit's hand (the outfit is the
      // second part), wrapped — a loaded model's own transform is the
      // importer's flip.
      final held = <(WeaponKind, Node, Node)>[];
      for (final p in [w, ?w.offhand]) {
        final asset = p.asset;
        final hand = model.children[1].getChildByName(p.hand);
        if (asset == null || hand == null) continue;
        final prop = await glb(asset);
        matteProp(prop);
        final holder = Node()..add(prop);
        hand.add(holder);
        held.add((p, hand, holder));
      }
      props.add(held);
    }
    scene
      ..add(turntable)
      // The ring they stand on, cyan and over the bloom threshold: it glows.
      ..add(Node(
        mesh: Mesh(
          RingGeometry(innerRadius: 0.55, outerRadius: 0.62, segments: 64),
          UnlitMaterial()..baseColorFactor = emissive(kCyan, alpha: 1, gain: 2),
        ),
      )..position = vm.Vector3(0, 0.01, 0));
    return HeroStage._(scene, heroes, turntable, props)..show(0);
  }

  /// Show hero [i] only.
  void show(int i) {
    _shown = i;
    for (final (k, h) in _heroes.indexed) {
      h.visible = k == i;
    }
    _pose();
  }

  /// Turn the table by [dt] seconds of a slow spin (one turn in 14 s).
  void turn(double dt) {
    _angle += dt * 2 * math.pi / 14;
    _turntable.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _angle);
    _pose();
  }

  /// Pose the shown hero's weapon. Upright ones are solved against the
  /// hand's current rotation every frame, as in the level, and point where
  /// the hero faces as the table turns.
  void _pose() {
    final forward = _turntable.rotation.rotated(vm.Vector3(0, 0, -1));
    for (final (w, hand, holder) in _props[_shown]) {
      holder.localTransform = weaponPose(
        w,
        hand: w.upright ? hand.globalTransform : null,
        forward: forward,
      );
    }
  }
}
