/// Achrona — region territories (GLOBE-01), ported from `globe/src/regions.js`.
///
/// Four continents, one per track (Base, Build, Creative, Online-Elite), each a
/// real Natural Earth coastline relocated into a fantasy layout and hexed by h3.
///
/// **The tessellation is not computed here.** globe.gl's hex layer is h3-based
/// and the hex grid is *static* — only colour and altitude are data-driven. So
/// `tool/gen_hexes.mjs` bakes it offline with the same h3-js version globe.gl
/// ships, and this file renders the result. That keeps the parity comparison
/// about rendering rather than about a re-derived hex grid.
///
/// Each region renders its live game state across three stages:
///   LOCKED   structural intact  — muted, dormant. Build-gated, not playable.
///   UNLOCKED structural cleared — risen and neon. Playable, residual draining.
///   CLEAN    residual drained   — plain healed earth ([kHealedLand]). Calm.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'palette.dart';

const List<int> kRegionIds = [1, 2, 3, 4];

/// Structural fraction above this ⇒ the region is build-LOCKED.
const double kLockThreshold = 0.5;

/// How far a corrupted region drifts off the core, as extra radius. A fully
/// healed region sits at 1; the Desync pushes the world apart. Knob.
const double kDrift = 0.04;

/// The plate's coloured lip: its state colour runs this far down the edge
/// before the rock takes over.
const double _lipRadius = 0.988;

/// Rock under each continent (see [_buildRock]): depth at the coast, extra
/// depth at the centre per radian of the region's half-width, and the step
/// that depths are quantised to — equal neighbours need no wall between them.
const double _rockCoast = 0.02;
const double _rockBelly = 0.4;
const double _rockStep = 0.012;

/// Deepest a belly may hang: offshore islands inflate a region's half-width,
/// and the rock must stay clear of the void (radius 0.62). Knob.
const double _rockBellyMax = 0.18;

/// Live per-region state, aggregated from the node rows.
class RegionState {
  RegionState({this.lock = 1, this.fill = 1});

  /// Structural fraction: 1 = fully locked (build-gated), 0 = cleared.
  double lock;

  /// Residual fraction: 1 = fully dirty, 0 = drained clean.
  double fill;

  bool get isLocked => lock > kLockThreshold;
}

/// The four hexed continents, with per-region colour and altitude.
class Territories {
  Territories._(this._nodes, this.state, this.hexCentres);

  final Map<int, Node> _nodes;

  /// Each region's current radius scale, eased toward its drift by [tick].
  final Map<int, double> _lift = {for (final id in kRegionIds) id: 1};
  final Map<int, RegionState> state;

  /// Unit direction of every hex's centre, per region — the normalised mean
  /// of its boundary loop. Where things can stand on the land.
  final Map<int, List<vm.Vector3>> hexCentres;

  /// Build the territories from the baked tessellation.
  static Future<Territories> load() async {
    final meta = json.decode(
      await rootBundle.loadString('assets/hexes.json'),
    ) as Map<String, dynamic>;
    final buffer = await rootBundle.load('assets/hexes.bin');
    final verts = buffer.buffer.asFloat32List(
      buffer.offsetInBytes,
      buffer.lengthInBytes ~/ 4,
    );

    final nodes = <int, Node>{};
    final state = <int, RegionState>{};
    final centres = <int, List<vm.Vector3>>{};

    for (final raw in meta['regions'] as List<dynamic>) {
      final region = raw as Map<String, dynamic>;
      final id = region['id'] as int;
      final vertOffset = region['vertOffset'] as int;
      final counts = (region['counts'] as List<dynamic>).cast<int>();

      final list = centres[id] = [];
      var v = vertOffset;
      for (final count in counts) {
        var x = 0.0, y = 0.0, z = 0.0;
        for (var k = 0; k < count; k++) {
          final o = (v + k) * 3;
          x += verts[o];
          y += verts[o + 1];
          z += verts[o + 2];
        }
        list.add(vm.Vector3(x, y, z)..normalize());
        v += count;
      }

      final plate = _buildRegion(verts, vertOffset, counts);
      final rock = _buildRock(verts, vertOffset, counts, list, id);
      nodes[id] = Node(
        mesh: Mesh(
          plate,
          // Unlit: these are graphic territory plates read from across a room,
          // not physical surfaces. Lighting them would let the planet's own
          // terminator swallow half the world state.
          UnlitMaterial()..baseColorFactor = srgb(kDormant),
        ),
      )..add(Node(
          mesh: Mesh(
            rock,
            // Lit, unlike the plate: the core's light is what shows the rock.
            PhysicallyBasedMaterial()
              ..baseColorFactor = srgb(kRock)
              ..roughnessFactor = 1
              ..metallicFactor = 0,
          ),
        ));
      state[id] = RegionState();
    }

    return Territories._(nodes, state, centres);
  }

  /// Build one region's hexes: a top plate plus a short lip in the state
  /// colour, down to [_lipRadius]. The rock below is [_buildRock].
  static MeshGeometry _buildRegion(
    Float32List verts,
    int vertOffset,
    List<int> counts,
  ) {
    final total = counts.fold(0, (a, c) => a + c);
    final m = _Buf(total * 2, total * 3);
    var v = vertOffset;

    for (final count in counts) {
      // h3 winds its boundary CLOCKWISE as seen from outside the sphere, so
      // every face below is built from the REVERSED order to come out
      // counter-clockwise, which is what flutter_scene treats as front-facing.
      // Vertex 2i is the top of corner i, 2i + 1 its foot on the lip.
      final base = m.n;
      for (var k = count - 1; k >= 0; k--) {
        final o = (v + k) * 3;
        final x = verts[o], y = verts[o + 1], z = verts[o + 2];
        m
          ..vert(x, y, z, x, y, z)
          ..vert(x * _lipRadius, y * _lipRadius, z * _lipRadius, x, y, z);
      }
      int top(int i) => base + 2 * i;

      // Top plate: a fan. Hexagons (and the 12 h3 pentagons) are convex.
      for (var i = 1; i < count - 1; i++) {
        m.tri(top(0), top(i), top(i + 1));
      }

      // Skirt: one outward-facing quad per edge.
      for (var i = 0; i < count; i++) {
        final j = (i + 1) % count;
        m
          ..tri(top(i) + 1, top(j) + 1, top(j))
          ..tri(top(i) + 1, top(j), top(i));
      }

      v += count;
    }

    return m.build();
  }

  /// The rock a continent hangs from: every hex a basalt column, shallow at
  /// the coast and deepest at the region's middle, so each continent reads as
  /// a shard broken off a world rather than land on a sea.
  ///
  /// Hex edges are shared exactly between neighbours (h3 emits the same
  /// vertices), so walls are built per edge: a coast edge gets the full
  /// column, an inner edge only the step between two different depths.
  /// Depths are quantised to [_rockStep], so most inner edges need nothing.
  ///
  /// Written on raw floats and typed arrays: ~35k hexes on the web build is
  /// where `GeometryBuilder` and per-vertex `Vector3`s cost whole seconds.
  static MeshGeometry _buildRock(Float32List verts, int vertOffset,
      List<int> counts, List<vm.Vector3> centres, int seed) {
    final mid = centres.fold(vm.Vector3.zero(), (a, c) => a + c)..normalize();
    double angle(vm.Vector3 c) => math.acos(c.dot(mid).clamp(-1.0, 1.0));
    final half = centres.map(angle).reduce(math.max);
    final rng = math.Random(seed);
    final depth = [
      for (final c in centres)
        ((_rockCoast +
                        math.min(_rockBellyMax, _rockBelly * half) *
                            math.pow(1 - angle(c) / half, 0.7) +
                        rng.nextDouble() * 0.02) /
                    _rockStep)
                .round() *
            _rockStep,
    ];

    // Each hex's corners as offsets into [verts], in front-facing (reversed)
    // order, as [_buildRegion] builds them.
    final start = <int>[];
    var v = vertOffset;
    for (final count in counts) {
      start.add(v);
      v += count;
    }
    int corner(int h, int i) => (start[h] + counts[h] - 1 - i) * 3;

    // Shared vertices are bit-identical, so a quantised position names a
    // vertex. Each vertex has at most three owning hexes, so an edge's
    // neighbour is whichever other hex owns both its ends. All typed arrays
    // and an open-addressed table: a `Map` over ~160k big-int keys costs
    // seconds on the web build.
    final total = counts.fold(0, (a, c) => a + c);
    var size = 1;
    while (size < total * 2) {
      size <<= 1;
    }
    final slot = Int32List(size)..fillRange(0, size, -1); // → vertex id
    final qx = Int32List(total), qy = Int32List(total), qz = Int32List(total);
    final owners = Int32List(total * 3)..fillRange(0, total * 3, -1);
    var nextId = 0;
    int idOf(int o) {
      final x = (verts[o] * 1e4).round(),
          y = (verts[o + 1] * 1e4).round(),
          z = (verts[o + 2] * 1e4).round();
      var i = ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & (size - 1);
      while (true) {
        final id = slot[i];
        if (id < 0) {
          qx[nextId] = x;
          qy[nextId] = y;
          qz[nextId] = z;
          return slot[i] = nextId++;
        }
        if (qx[id] == x && qy[id] == y && qz[id] == z) return id;
        i = (i + 1) & (size - 1);
      }
    }

    final vid = <Int32List>[];
    for (var h = 0; h < counts.length; h++) {
      final ring = Int32List(counts[h]);
      for (var i = 0; i < counts[h]; i++) {
        final id = ring[i] = idOf(corner(h, i));
        final s = id * 3;
        owners[owners[s] < 0 ? s : (owners[s + 1] < 0 ? s + 1 : s + 2)] = h;
      }
      vid.add(ring);
    }
    int neighbour(int h, int a, int b) {
      for (var i = 0; i < 3; i++) {
        final o = owners[a * 3 + i];
        if (o < 0 || o == h) continue;
        for (var j = 0; j < 3; j++) {
          if (owners[b * 3 + j] == o) return o;
        }
      }
      return -1;
    }

    final m = _Buf(total * 5, total * 3);
    for (var h = 0; h < counts.length; h++) {
      final count = counts[h];
      final r = 1 - depth[h];
      final c = centres[h];
      // The column's foot, facing the core.
      final foot = m.n;
      for (var i = 0; i < count; i++) {
        final o = corner(h, i);
        m.vert(verts[o] * r, verts[o + 1] * r, verts[o + 2] * r, -c.x, -c.y,
            -c.z);
      }
      for (var i = 1; i < count - 1; i++) {
        m.tri(foot, foot + i + 1, foot + i);
      }
      // Walls, facing out of this hex, where it hangs below its neighbour.
      for (var i = 0; i < count; i++) {
        final j = (i + 1) % count;
        final other = neighbour(h, vid[h][i], vid[h][j]);
        final top = other < 0 ? _lipRadius : 1 - depth[other];
        if (top <= r + 1e-6) continue;
        final p = corner(h, i), q = corner(h, j);
        final px = verts[p], py = verts[p + 1], pz = verts[p + 2];
        final qx = verts[q], qy = verts[q + 1], qz = verts[q + 2];
        // Outward normal: (q − p) × c, for a loop wound CCW about c.
        final ex = qx - px, ey = qy - py, ez = qz - pz;
        var nx = ey * c.z - ez * c.y,
            ny = ez * c.x - ex * c.z,
            nz = ex * c.y - ey * c.x;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        final w = m.n;
        m
          ..vert(px * r, py * r, pz * r, nx, ny, nz)
          ..vert(qx * r, qy * r, qz * r, nx, ny, nz)
          ..vert(qx * top, qy * top, qz * top, nx, ny, nz)
          ..vert(px * top, py * top, pz * top, nx, ny, nz)
          ..tri(w, w + 1, w + 2)
          ..tri(w, w + 2, w + 3);
      }
    }
    return m.build();
  }

  void addTo(Scene scene) {
    for (final node in _nodes.values) {
      scene.add(node);
    }
  }

  /// Aggregate node rows into per-region lock/fill and restyle. Mirrors
  /// `regions.js` `update()`: the mean structural and residual fraction over
  /// every node in the region.
  void update(Iterable<GlobeNode> nodes) {
    final acc = {for (final id in kRegionIds) id: <double>[0, 0, 0]};
    for (final n in nodes) {
      final a = acc[n.regionId];
      if (a == null) continue;
      a[0] += _fraction(n.structuralRemaining, n.structuralMax);
      a[1] += _fraction(n.residualRemaining, n.residualMax);
      a[2] += 1;
    }
    for (final id in kRegionIds) {
      final a = acc[id]!;
      if (a[2] == 0) continue;
      state[id]!
        ..lock = a[0] / a[2]
        ..fill = a[1] / a[2];
    }
    restyle();
  }

  /// Push the current state to colour (material) and altitude (node scale).
  void restyle() {
    for (final id in kRegionIds) {
      final s = state[id]!;
      final node = _nodes[id];
      if (node == null) continue;

      // regions.js colorFor(): a dormant→active lerp driven by the build gate,
      // where "active" itself lerps healed→neon with the residual still to
      // drain. Healed land is just land — warm earth, not cyan: cyan on the
      // healed world's calm sea read as blue on blue.
      final active = lerpSrgb(kHealedLand, kCorruptLand, s.fill);
      final colour = lerpSrgb(kDormant, active, 1 - s.lock);
      (node.mesh!.primitives.first.material as UnlitMaterial).baseColorFactor =
          srgb(colour);

      // Altitude is not state any more — distance is: [tick] drifts the whole
      // shard off the core by its corruption. (The old hairline existed only
      // because a raised plate cleared an ocean sphere's limb; there is no
      // ocean now.)
    }
  }

  /// The Desync's drift for a region: fully corrupted drifts [kDrift] off the
  /// core, fully healed sits home at 1.
  double _driftOf(RegionState s) => 1 + kDrift * math.max(s.lock, s.fill);

  /// Each region's outward speed: drift is a spring, so a [burst] overshoots
  /// and settles, and a heal pulls a shard home with a little give.
  final Map<int, double> _vel = {for (final id in kRegionIds) id: 0};

  /// Stiffness and damping of that spring. Under-damped a touch. Knobs.
  static const double _k = 16, _damp = 5;

  /// Fling every shard outward — the world breaking open. They spring back
  /// to their drift.
  void burst({double speed = 1.4}) {
    for (final (i, id) in kRegionIds.indexed) {
      _vel[id] = speed * (0.8 + 0.12 * i);
    }
  }

  /// Spring every region toward its drift. [whole] (0..1, the world sealed —
  /// see `DesyncVoid.whole`) holds the shards home regardless of corruption.
  /// Call per frame.
  void tick(double dt, {double whole = 0}) {
    // Clamped: a stalled frame must not blow the spring up.
    final h = math.min(dt, 1 / 30);
    for (final id in kRegionIds) {
      final target = 1 + (_driftOf(state[id]!) - 1) * (1 - whole);
      final v = _vel[id]! + ((target - _lift[id]!) * _k - _vel[id]! * _damp) * h;
      _vel[id] = v;
      final now = _lift[id]! + v * h;
      _lift[id] = now;
      _nodes[id]?.scale = vm.Vector3.all(now);
    }
  }

  /// A region's current radius scale.
  double liftOf(int regionId) => _lift[regionId]!;

  /// The region's node, for things that ride its drift (landmarks).
  Node nodeOf(int regionId) => _nodes[regionId]!;

  /// A region's centroid on its surface as it drifts, for aiming flares.
  vm.Vector3 centroidOf(int regionId) =>
      kRegionCentroids[regionId]! * _lift[regionId]!;
}

double _fraction(double remaining, double max) {
  if (max <= 0) return 0;
  return (remaining / max).clamp(0.0, 1.0);
}

/// Region centroids, matching `regions.js` CONTINENTS. Spread ~90° apart with
/// alternating N/S latitudes so land shows from every angle.
final Map<int, vm.Vector3> kRegionCentroids = {
  1: latLngToDirection(16, -135),
  2: latLngToDirection(-16, -45),
  3: latLngToDirection(16, 45),
  4: latLngToDirection(-16, 135),
};

/// Same convention as `tool/gen_hexes.mjs` (three-globe's polar2Cartesian).
vm.Vector3 latLngToDirection(double lat, double lng) {
  final phi = (90 - lat) * math.pi / 180;
  final theta = (90 - lng) * math.pi / 180;
  return vm.Vector3(
    math.sin(phi) * math.cos(theta),
    math.cos(phi),
    math.sin(phi) * math.sin(theta),
  );
}


/// A node row from `public.nodes`, normalized. Mirrors `world.js normalizeNode`.
class GlobeNode {
  const GlobeNode({
    required this.challengeId,
    required this.regionId,
    required this.structuralRemaining,
    required this.residualRemaining,
    required this.structuralMax,
    required this.residualMax,
  });

  final String challengeId;
  final int regionId;
  final double structuralRemaining;
  final double residualRemaining;
  final double structuralMax;
  final double residualMax;
}

/// Typed-array mesh accumulator, sized up front to an upper bound.
class _Buf {
  _Buf(int verts, int tris)
      : _pos = Float32List(verts * 3),
        _nrm = Float32List(verts * 3),
        _idx = Uint32List(tris * 3);

  final Float32List _pos, _nrm;
  final Uint32List _idx;

  /// Vertices written so far; the next [vert] gets this index.
  int n = 0;
  int _t = 0;

  void vert(double x, double y, double z, double nx, double ny, double nz) {
    final o = n++ * 3;
    _pos[o] = x;
    _pos[o + 1] = y;
    _pos[o + 2] = z;
    _nrm[o] = nx;
    _nrm[o + 1] = ny;
    _nrm[o + 2] = nz;
  }

  void tri(int a, int b, int c) {
    _idx[_t++] = a;
    _idx[_t++] = b;
    _idx[_t++] = c;
  }

  MeshGeometry build() => MeshGeometry.fromArrays(
        positions: Float32List.sublistView(_pos, 0, n * 3),
        normals: Float32List.sublistView(_nrm, 0, n * 3),
        indices: Uint32List.sublistView(_idx, 0, _t),
      );
}
