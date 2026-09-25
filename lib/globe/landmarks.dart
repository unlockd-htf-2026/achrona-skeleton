/// Achrona on the land: ruins scattered over every continent, and a landmark
/// for each level on the Base continent, built from that level's own kit.
///
/// The territories are real coastlines, so on their own they read as Earth.
/// What makes them Achrona is what stands on them — the same dungeon kit the
/// levels are built from, so the globe and the game are visibly one world.
///
/// Everything static is instanced through the level's [TileBatcher]; only the
/// glow rings are their own nodes, because selection recolours them.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../asset_cache.dart';
import '../level_one.dart' show TileBatcher;
import 'palette.dart';
import 'territories.dart';

/// Where pieces stand, in their region's frame: the plate's top. They ride
/// the region's node, so they drift with its shard.
const double _ground = 1.0;

/// Kit units → globe units. A kit wall is 2 units, so a ruin is ~2 hexes.
const double _ruinScale = 0.007;
const double _landmarkScale = 0.016;

/// One ruin per this many hexes.
const int _ruinEvery = 22;

/// Kit pieces placed in a landmark's own frame: (file, x, y, z, yaw).
typedef _Piece = (String, double, double, double, double);

/// A level's landmark: where it stands (lat, lng on the Base continent) and
/// what it is built from — the pieces its level is made of.
const List<(double, double, List<_Piece>)> _landmarks = [
  // I · The Sealed Gate: a gothic door between two columns.
  (26, -141, [
    ('ruins/Arch_Gothic.glb', 0, 0, 0, 0),
    ('ruins/Column_Round.glb', -2.2, 0, 0, 0),
    ('ruins/Column_Round.glb', 2.2, 0, 0, 0),
  ]),
  // II · The Descent: stairs up to a broken, overgrown arch.
  (15, -135, [
    ('ruins/Wall_ArchRound_Overgrown_Broken.glb', 0, 0, -0.3, 0),
    ('ruins/Stairs.glb', 0, 0, 0.9, 0),
    ('ruins/Column_Round_Short.glb', -2.4, 0, 0, 0),
    ('ruins/Column_Round_Short.glb', 2.4, 0, 0, 0),
  ]),
  // III · The Spire: stacked columns, a torch at the crown.
  (4, -126, [
    ('ruins/Column_Square.glb', 0, 0, 0, 0),
    ('ruins/Column_Square.glb', 0, 4, 0, 0.4),
    ('ruins/Column_Square.glb', 0, 8, 0, 0.8),
    ('dungeon/Torch.glb', 0, 12.3, 0, 0),
    ('ruins/Column_Round_Short.glb', -1.1, 0, 0.4, 0),
    ('ruins/Column_Round_Short.glb', 1.0, 0, -0.5, 0),
  ]),
  // IV · Your level: a round arch between two torches — the team's own gate.
  (19, -124, [
    ('ruins/Arch_Round.glb', 0, 0, 0, 0),
    ('dungeon/Torch.glb', -2.0, 0, 0, 0),
    ('dungeon/Torch.glb', 2.0, 0, 0, 0),
  ]),
];

/// A team level's landmark, one design for all twelve: a round arch between
/// two banners. Theirs to own, not ours to pick per team.
const List<_Piece> _teamPieces = [
  ('ruins/Arch_Round_RoundColumn.glb', 0, 0, 0, 0),
  ('dungeon/Banner.glb', -2.1, 0, 0, 0),
  ('dungeon/Banner.glb', 2.1, 0, 0, 0),
];

/// Team-level slots per continent: twelve teams, four continents.
const int kTeamSlotsPerRegion = 3;

/// [n] sites spread over a continent's [hexes], standing on hexes, kept off
/// its coast and as far as possible from each other and from [avoid].
///
/// Farthest-point sampling over the inner 70% of the hexes (by distance from
/// the continent's middle), so a site never lands on a sliver of coastline.
List<vm.Vector3> spreadSites(List<vm.Vector3> hexes, int n,
    {List<vm.Vector3> avoid = const []}) {
  final middle = hexes.fold(vm.Vector3.zero(), (a, b) => a + b).normalized();
  final inner = [...hexes]
    ..sort((a, b) => b.dot(middle).compareTo(a.dot(middle)));
  final pool = inner.take((inner.length * 0.7).ceil()).toList();
  final sites = <vm.Vector3>[];
  for (var k = 0; k < n; k++) {
    final taken = [...avoid, ...sites];
    vm.Vector3 best = pool.first;
    var bestD = -1.0;
    for (final h in pool) {
      // With nothing placed yet, start at the middle.
      final d = taken.isEmpty
          ? h.dot(middle)
          : taken.map(h.angleTo).reduce(math.min);
      if (d > bestD) (best, bestD) = (h, d);
    }
    sites.add(best);
  }
  return sites;
}

/// Ruin fragments, the levels' dressing.
const List<String> _ruinPieces = [
  'ruins/Wall_Broken.glb',
  'ruins/Wall_Double_Broken.glb',
  'ruins/Column_Round.glb',
  'ruins/Column_Round_Short.glb',
  'ruins/Arch_Gothic.glb',
  'ruins/Bricks.glb',
  // No trees: their foliage blows out white under the studio IBL.
];

/// The level landmarks and the ruins around them.
class Landmarks {
  Landmarks._(this.sites, this.regions, this._rings, this._nodes,
      this._batchers, this._terr);

  /// Unit direction of each level's landmark, by level index: the built-in
  /// levels first, then one per team level.
  final List<vm.Vector3> sites;

  /// The continent each landmark stands on (it rides that shard).
  final List<int> regions;
  final List<UnlitMaterial> _rings;
  final List<(int, Node)> _nodes;
  final Map<int, TileBatcher> _batchers;
  final Territories _terr;

  /// The built-in levels' landmarks on Base, then one team-level landmark
  /// per slot in [teamSlots] (each 0 to 4 × [kTeamSlotsPerRegion] − 1), in
  /// that order. Slot `i` stands on continent `i % 4`, its `i ~/ 4`-th spot,
  /// so a level keeps its place whoever else publishes; a missing slot leaves
  /// its spot empty.
  static Future<Landmarks> load(Territories terr,
      {List<int> teamSlots = const []}) async {
    final models = <String, Node>{};
    Future<Node> model(String f) async =>
        models[f] ??= _stone(await glb('assets/levels/$f'));

    // One batch set per region, so each rides its own shard.
    final batchers = {for (final id in kRegionIds) id: TileBatcher()};
    final nodes = <(int, Node)>[];
    final sites = <vm.Vector3>[];
    final regions = <int>[];
    final rings = <UnlitMaterial>[];

    Future<void> stand(int region, vm.Vector3 at, List<_Piece> pieces) async {
      sites.add(at);
      regions.add(region);
      for (final (f, x, y, z, yaw) in pieces) {
        batchers[region]!.add(
          await model(f),
          standOn(at, _landmarkScale, yaw: yaw)
            ..translateByDouble(x, y, z, 1),
        );
      }
      // The glow at its foot — the level's neon, cyan when chosen.
      final ring = UnlitMaterial();
      rings.add(ring);
      nodes.add((
        region,
        Node(
          mesh: Mesh(RingGeometry(innerRadius: 2.4, outerRadius: 2.8), ring),
        )..localTransform = standOn(at, _landmarkScale, lift: 0.0005),
      ));
    }

    // The built-in levels first: each snaps to the Base hex nearest its site.
    final base = terr.hexCentres[1]!;
    for (final (lat, lng, pieces) in _landmarks) {
      final want = latLngToDirection(lat, lng);
      await stand(
          1, base.reduce((a, b) => a.dot(want) >= b.dot(want) ? a : b), pieces);
    }

    // Then the team slots: three per continent, clear of what stands there.
    final slots = {
      for (final id in kRegionIds)
        id: spreadSites(terr.hexCentres[id]!, kTeamSlotsPerRegion,
            avoid: [...sites]),
    };
    for (final i in teamSlots) {
      final region = kRegionIds[i % kRegionIds.length];
      await stand(region, slots[region]![i ~/ kRegionIds.length], _teamPieces);
    }

    // Ruins: a seeded scatter, so every screen shows the same world. Kept
    // off the landmarks so each one stands alone.
    final rng = math.Random(1);
    for (final id in kRegionIds) {
      for (final at in terr.hexCentres[id]!) {
        if (rng.nextInt(_ruinEvery) != 0) continue;
        if (sites.any((s) => s.dot(at) > 0.9995)) continue;
        final f = _ruinPieces[rng.nextInt(_ruinPieces.length)];
        batchers[id]!.add(
          await model(f),
          standOn(at, _ruinScale * (0.7 + rng.nextDouble() * 0.6),
              yaw: rng.nextDouble() * 2 * math.pi),
        );
      }
    }

    return Landmarks._(sites, regions, rings, nodes, batchers, terr)
      ..select(0);
  }

  /// Hang everything off its region's node (see `Territories.nodeOf`).
  void attach() {
    for (final MapEntry(key: id, value: b) in _batchers.entries) {
      b.attach(_terr.nodeOf(id).add);
    }
    for (final (region, node) in _nodes) {
      _terr.nodeOf(region).add(node);
    }
  }

  /// Light the chosen level's ring cyan, cleared ones the healed land's
  /// warm colour, the rest the Desync's violet.
  void select(int level, {Set<int> cleared = const {}}) {
    _cleared = cleared;
    for (final (i, m) in _rings.indexed) {
      m.baseColorFactor = i == level
          ? emissive(kCyan, alpha: 1, gain: 3)
          : cleared.contains(i)
              ? emissive(kHealedLand, alpha: 1, gain: 2)
              : emissive(kNeon, alpha: 1, gain: 1.6);
    }
  }

  Set<int> _cleared = const {};

  /// Levels marked cleared by the last [select].
  Set<int> get cleared => _cleared;

  /// The landmark under [tap], if one is on the near side and within reach.
  int? hit(Camera camera, ui.Size view, ui.Offset tap, vm.Vector3 eye) {
    int? best;
    var bestD = 40.0; // px
    for (final (i, s) in sites.indexed) {
      final lift = _terr.liftOf(regions[i]);
      // Beyond the horizon: a point P is hidden when P·E ≤ R² (tangent plane).
      if (s.dot(eye) <= lift) continue;
      final p = camera.worldToScreen(s * lift, view);
      if (p == null) continue;
      final d = (p - tap).distance;
      if (d < bestD) (best, bestD) = (i, d);
    }
    return best;
  }
}

/// Kit stone for a globe with no key light: the default studio IBL blows a
/// kit material out to white here, so take the gloss off and the value down.
/// Knob: [_stoneValue].
Node _stone(Node model) {
  void walk(Node n) {
    for (final p in n.mesh?.primitives ?? const <MeshPrimitive>[]) {
      final m = p.material;
      if (m is PhysicallyBasedMaterial) {
        m
          ..roughnessFactor = 1
          ..metallicFactor = 0
          ..baseColorFactor = (m.baseColorFactor.clone()..scale(_stoneValue))
            ..baseColorFactor.w = 1;
      }
    }
    n.children.forEach(walk);
  }

  walk(model);
  return model;
}

const double _stoneValue = 0.75;

/// A frame standing on the globe at unit direction [at]: Y along the surface
/// normal, X east, Z north-ish, scaled to [scale] and turned [yaw] about up.
vm.Matrix4 standOn(vm.Vector3 at, double scale,
    {double yaw = 0, double lift = 0}) {
  final up = at.normalized();
  final ref = up.y.abs() > 0.99 ? vm.Vector3(1, 0, 0) : vm.Vector3(0, 1, 0);
  final x = ref.cross(up)..normalize();
  final z = x.cross(up)..normalize();
  final p = up * (_ground + lift);
  return vm.Matrix4(
    x.x, x.y, x.z, 0, //
    up.x, up.y, up.z, 0, //
    z.x, z.y, z.z, 0, //
    p.x, p.y, p.z, 1, //
  )
    ..rotateY(yaw)
    ..scaleByDouble(scale, scale, scale, 1);
}
