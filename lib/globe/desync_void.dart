/// The Desync at the centre of the shattered world: not a sun, a hole.
///
/// A sphere of pure black, a violet corona that breathes around its rim, and
/// the light inside that shows the rock under every shard — pulsing with the
/// corona, so the whole world's underside breathes with the curse. How hard
/// it pulses is the world's corruption: a cursed world throbs, a healed one
/// barely stirs.
///
/// Arcs of the curse crack out of it — jagged, branching, flickering violet
/// bolts, many at once while the world is corrupted; as it is purified they
/// thin to the odd slow cyan filament.
///
/// And it can be closed. [whole] is the old world's crust — the ocean the
/// Desync swallowed — as fragments: whole, they seal the shards into one
/// planet; breaking, they burst outward, tumble and wink out; sealing, they
/// fly back in and lock together. The intro starts whole and [crack]s it
/// open, and a fully purified world seals again.
///
/// The corona is a camera-facing ring mesh (vertex-coloured alpha falloff)
/// whose inner edge sits exactly on the visible body — the void, or the
/// crust when whole. It must never overlap that disc: on web, translucent
/// draws are not held back by depth, and a disc-sized sprite washed the
/// void and the whole planet in glow.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'palette.dart';

/// The healed world's sea: a dark, still slate — not blue, so the purified
/// cyan continents read as bright land on a calm sea, not blue on blue. Knob.
const int kCalmCrust = 0xFF10141C;

/// The cursed world's sea: dark, with the Desync's violet in it. Knob.
const int kCursedCrust = 0xFF22123A;

/// Radius of the void the shattered world hangs around. Knob.
const double kVoidRadius = 0.62;

/// The corona's outer edge, in radii of the body it rings. Knob.
const double _coronaSpan = 2.2;

/// One breath, in seconds. Knob.
const double _breath = 2.8;

/// Bolts per second at full corruption, and at none. Knobs.
const double _boltsCursed = 34;
const double _boltsCalm = 0.4;

/// Most bolts alive at once.
const int _maxBolts = 40;

class DesyncVoid {
  DesyncVoid._(
      this._scene, this._corona, this._coronaTint, this._light, this._crust,
      this._crustSkin);

  final Scene _scene;
  final Node _corona;
  final UnlitMaterial _coronaTint;
  final PointLight _light;
  final List<_Fragment> _crust;
  final UnlitMaterial _crustSkin;
  double _t = 0;

  /// How closed the world is: 1 = one whole planet, 0 = shattered. Eased
  /// toward [wholeTarget] by [tick].
  double get whole => _whole;
  double _whole = 0;
  double wholeTarget = 0;

  /// Bolts are screen-space polylines: inert until they know the camera and
  /// the viewport (same contract as `ArcsLayer`). Without them, none spawn —
  /// which keeps scene snapshots still.
  Camera? camera;
  ui.Size viewport = ui.Size.zero;

  final List<_Bolt> _bolts = [];
  final math.Random _rng = math.Random(3);
  double _spawnDebt = 0;

  static Future<DesyncVoid> create(Scene scene) async {
    // Blend, and wound to face +Z: a translucent material ignores
    // `doubleSided` (flutter_scene culls its back faces regardless).
    final coronaTint = UnlitMaterial()..alphaMode = AlphaMode.blend;
    final corona = Node(mesh: Mesh(_coronaRing(), coronaTint));
    final light = PointLight(
      color: vm.Vector3(0.75, 0.35, 1.0),
      intensity: 6,
      range: 2.2,
    );
    // The crust: the old world's sea, in fragments that can burst apart.
    // Unlit, like the land plates: a lit crust picked up a bright grazing
    // sheen from the default studio light on web, washing the healed sea.
    final skin = UnlitMaterial()
      // A flying fragment shows its underside.
      ..doubleSided = true;
    final crust = _shatter(skin);
    crust.map((f) => f.node).forEach(scene.add);
    scene
      ..add(Node(
        mesh: Mesh(
          IcosphereGeometry(radius: kVoidRadius, subdivisions: 3),
          // Black and unlit: nothing reflects off a hole.
          UnlitMaterial()..baseColorFactor = vm.Vector4(0, 0, 0, 1),
        ),
      ))
      ..add(corona)
      // The light that shows the rock under the shards.
      ..add(Node()..addComponent(PointLightComponent(light)));
    return DesyncVoid._(scene, corona, coronaTint, light, crust, skin)
      ..tick(0, 1);
  }

  /// Advance the breath by [dt] seconds at [corruption] (0..1).
  void tick(double dt, double corruption) {
    _t += dt;
    // Closing is slow and settling; breaking is fast.
    final rate = wholeTarget > _whole ? 0.5 : 0.9;
    _whole = (_whole + (wholeTarget - _whole).sign * dt * rate)
        .clamp(math.min(_whole, wholeTarget), math.max(_whole, wholeTarget));
    // Each fragment is on its own clock, staggered, so the crust bursts in a
    // ripple rather than as one shell: 0 in place, 1 gone.
    final gone = 1 - _whole;
    for (final f in _crust) {
      final k = ((gone - f.delay) / (1 - f.delay)).clamp(0.0, 1.0);
      final out = 1 - (1 - k) * (1 - k); // fast start, slowing — a burst
      f.node
        ..visible = k < 0.999
        ..position = f.dir * (0.997 + f.reach * out)
        ..rotation = vm.Quaternion.axisAngle(f.axis, f.spin * out)
        ..scale = vm.Vector3.all(math.max(0.001, 1 - k * k));
    }
    // 0..1, eased so it lingers at the bottom and swells.
    final s = 0.5 - 0.5 * math.cos(_t * 2 * math.pi / _breath);
    final beat = s * s;
    final depth = 0.25 + 0.75 * corruption; // how hard it pulses
    // Everything the void colours goes from the curse's violet to a calm
    // cyan as the world heals — a purified Achrona seals quiet and cool.
    final tint = srgb(lerpSrgb(kCyan, kNeon, corruption));
    // Ring the visible body: the void, or the crust as it closes. In
    // perspective a sphere's outline, in the plane through its centre, is
    // wider than its radius — r·d/√(d²−r²) — and the ring must start there:
    // on web nothing hides the part that would sit under the disc.
    var body = kVoidRadius + (1.0 - kVoidRadius) * _whole;
    final cam = camera?.position;
    if (cam != null) {
      _corona.rotation =
          vm.Quaternion.fromTwoVectors(vm.Vector3(0, 0, 1), cam.normalized());
      final d = cam.length;
      if (d > body * 1.01) body = body * d / math.sqrt(d * d - body * body);
    }
    _corona.scale = vm.Vector3(body, body, body);
    // Cursed it blazes; purified it is a faint, quiet atmosphere.
    _coronaTint.baseColorFactor = vm.Vector4(tint.x, tint.y, tint.z,
        (0.2 + 0.8 * corruption) * (0.7 + 0.3 * beat));
    _light
      ..intensity = 2 + 6 * depth * (0.6 + 0.4 * beat)
      // Hand-picked, not the palette: a light needs bright channels, and
      // linear neon is nearly pure blue.
      ..color = vm.Vector3(0.35, 0.85, 1.0) +
          (vm.Vector3(0.75, 0.35, 1.0) - vm.Vector3(0.35, 0.85, 1.0)) *
              corruption;
    _crustSkin.baseColorFactor =
        srgb(lerpSrgb(kCalmCrust, kCursedCrust, corruption));
    _tickBolts(dt, corruption);
  }

  void _tickBolts(double dt, double c) {
    final cam = camera;
    if (cam == null || viewport.isEmpty) return;

    // Chaos is steep: a half-healed world is already much calmer.
    final chaos = c * c;
    // None while the crust is closed: they would pierce it.
    _spawnDebt += dt *
        (_boltsCalm + (_boltsCursed - _boltsCalm) * chaos) *
        (1 - _whole);
    while (_spawnDebt >= 1) {
      _spawnDebt -= 1;
      if (_bolts.length < _maxBolts) _spawn(null, c);
    }

    for (var i = _bolts.length - 1; i >= 0; i--) {
      final b = _bolts[i]..age += dt;
      if (b.age >= b.life) {
        _scene.remove(b.node);
        _bolts.removeAt(i);
        continue;
      }
      final k = b.age / b.life;
      if (b.crack) {
        // A crack runs across the crust and stays open, then fades as the
        // crust falls away.
        b.geometry
          ..drawEnd = (k / 0.35).clamp(0.0, 1.0)
          ..updateForCamera(cam, viewport);
        b.material.baseColorFactor =
            vm.Vector4(1, 1, 1, ((1 - k) / 0.3).clamp(0.0, 1.0));
        continue;
      }
      // A pulse leaving the void: the head races out, the tail follows.
      b.geometry
        ..drawEnd = (k / 0.3).clamp(0.0, 1.0)
        ..drawStart = ((k - 0.5) / 0.5).clamp(0.0, 1.0)
        ..updateForCamera(cam, viewport);
      // Cursed bolts stutter; calm ones glow steadily.
      final flicker = 1 - b.chaos * _rng.nextDouble() * 0.5;
      b.material.baseColorFactor = vm.Vector4(1, 1, 1, flicker);
    }
  }

  /// Split the whole world open: [n] glowing cracks race across the crust,
  /// jagged paths along the surface, on the side the camera can see.
  void crack(int n) {
    if (camera == null) return;
    final view = camera!.position.normalized();
    vm.Vector3 jitter() => vm.Vector3(_rng.nextDouble() * 2 - 1,
        _rng.nextDouble() * 2 - 1, _rng.nextDouble() * 2 - 1);
    for (var i = 0; i < n; i++) {
      var p = (view + jitter() * 0.9)..normalize();
      var d = jitter()..normalize();
      const steps = 24;
      final points = <vm.Vector3>[];
      for (var k = 0; k <= steps; k++) {
        points.add(p * 1.004);
        // Walk along the surface: keep the heading tangent, jag it.
        d = (d + jitter() * 0.7)..normalize();
        d = (d - p * d.dot(p))..normalize();
        p = (p + d * (0.05 + 0.03 * _rng.nextDouble()))..normalize();
      }
      final geometry = PolylineGeometry(
        points,
        width: 2.5 + 2.5 * _rng.nextDouble(),
        perVertexColor: [
          for (var k = 0; k <= steps; k++)
            emissive(kNeon, alpha: 1, gain: 4),
        ],
        cap: PolylineCap.round,
      );
      final material = UnlitMaterial()..alphaMode = AlphaMode.blend;
      final node = Node(mesh: Mesh(geometry, material));
      _scene.add(node);
      _bolts.add(_Bolt(node, geometry, material,
          life: 1.6 + 0.6 * _rng.nextDouble(), chaos: 0, crack: true)
        ..age = -0.5 * _rng.nextDouble()); // staggered
    }
  }

  /// One bolt, from the void's surface ([from] null) or off another bolt.
  void _spawn(vm.Vector3? from, double c) {
    final chaos = c * c;
    vm.Vector3 jitter() => vm.Vector3(_rng.nextDouble() * 2 - 1,
        _rng.nextDouble() * 2 - 1, _rng.nextDouble() * 2 - 1);
    // Surface bolts start near the silhouette and leave sideways, like
    // prominences: ones aimed at the camera read as squiggles on the disc,
    // ones on the far side are hidden by it.
    final view = camera!.position.normalized();
    final out = from?.normalized() ??
        (() {
          final o = jitter()..normalize();
          return (o - view * (o.dot(view) * 0.8))..normalize();
        })();
    var p = from ?? out * kVoidRadius;
    var d = out.clone();
    final length = kVoidRadius *
        (from == null ? 0.5 : 0.25) *
        (1 + _rng.nextDouble() * (1.0 + 2.4 * c));
    const steps = 10;
    final points = [p.clone()];
    for (var k = 0; k < steps; k++) {
      d = (d + jitter() * (0.25 + 1.1 * chaos) + out * 0.3)..normalize();
      p = p + d * (length / steps);
      points.add(p.clone());
    }

    // Violet while cursed, cyan as it calms; bright at the root.
    final colour = lerpSrgb(kCyan, kNeon, c);
    final material = UnlitMaterial()..alphaMode = AlphaMode.blend;
    final geometry = PolylineGeometry(
      points,
      width: 2.2 + (1.4 + 4.0 * chaos) * _rng.nextDouble(),
      perVertexColor: [
        for (var k = 0; k <= steps; k++)
          emissive(colour, alpha: 1 - 0.6 * k / steps, gain: 3),
      ],
      cap: PolylineCap.round,
    );
    final node = Node(mesh: Mesh(geometry, material));
    _scene.add(node);
    _bolts.add(_Bolt(
      node,
      geometry,
      material,
      // Cursed bolts snap; calm ones drift out slowly.
      life: (0.35 + 0.5 * _rng.nextDouble()) * (2.2 - 1.6 * c),
      chaos: chaos,
    ));

    // Chaos forks.
    if (from == null && _rng.nextDouble() < 0.45 * chaos) {
      _spawn(points[3 + _rng.nextInt(5)], c);
    }
  }
}

/// One piece of the crust. Its vertices are local to [dir] × radius, so it
/// flies, tumbles and shrinks about its own centre.
class _Fragment {
  _Fragment(this.node, this.dir, this.axis, this.spin, this.reach, this.delay);

  final Node node;
  final vm.Vector3 dir, axis;
  final double spin, reach, delay;
}

/// Break a sphere into [pieces] fragments: a lat/long grid, each cell given to
/// the nearest of evenly spread (Fibonacci) seeds, so pieces come out
/// similar-sized with ragged, stepped edges.
List<_Fragment> _shatter(Material material,
    {int pieces = 56, int lon = 72, int lat = 36}) {
  const radius = 0.997;
  final rng = math.Random(11);
  final seeds = [
    for (var i = 0; i < pieces; i++)
      () {
        final y = 1 - 2 * (i + 0.5) / pieces;
        final r = math.sqrt(1 - y * y);
        final a = i * math.pi * (3 - math.sqrt(5));
        return vm.Vector3(r * math.cos(a) + (rng.nextDouble() - 0.5) * 0.15, y,
            r * math.sin(a) + (rng.nextDouble() - 0.5) * 0.15)
          ..normalize();
      }(),
  ];
  vm.Vector3 at(int i, int j) {
    final phi = math.pi * i / lat, theta = 2 * math.pi * j / lon;
    return vm.Vector3(math.sin(phi) * math.cos(theta), math.cos(phi),
        math.sin(phi) * math.sin(theta));
  }

  final builders = [for (final _ in seeds) GeometryBuilder(deduplicate: false)];
  for (var i = 0; i < lat; i++) {
    for (var j = 0; j < lon; j++) {
      final q = [at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1)];
      final mid = (q[0] + q[1] + q[2] + q[3])..normalize();
      var best = 0;
      for (var k = 1; k < seeds.length; k++) {
        if (seeds[k].dot(mid) > seeds[best].dot(mid)) best = k;
      }
      final b = builders[best], c = seeds[best] * radius;
      for (final (x, y, z) in [(0, 1, 2), (0, 2, 3)]) {
        var t = [q[x], q[y], q[z]];
        // Front faces outward (counter-clockwise seen from outside).
        if ((t[1] - t[0]).cross(t[2] - t[0]).dot(mid) < 0) {
          t = [t[0], t[2], t[1]];
        }
        final ids = [
          for (final v in t) (b..normal(v)).addVertex(v * radius - c),
        ];
        b.addTriangle(ids[0], ids[1], ids[2]);
      }
    }
  }
  return [
    for (final (k, seed) in seeds.indexed)
      _Fragment(
        Node(mesh: Mesh(builders[k].build(), material)),
        seed,
        (vm.Vector3(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5,
            rng.nextDouble() - 0.5))
          ..normalize(),
        (rng.nextDouble() - 0.5) * 5,
        0.5 + rng.nextDouble() * 0.9,
        rng.nextDouble() * 0.35,
      ),
  ];
}

class _Bolt {
  _Bolt(this.node, this.geometry, this.material,
      {required this.life, required this.chaos, this.crack = false});

  final Node node;
  final PolylineGeometry geometry;
  final UnlitMaterial material;
  final double life, chaos;

  /// A crack in the crust (the intro), not a bolt from the void.
  final bool crack;
  double age = 0;
}

/// The corona: an annulus in the XY plane (facing +Z) from radius 1 (the
/// body's edge) out to [_coronaSpan], white with an alpha falloff, so
/// [DesyncVoid.tick] can tint it, scale it to the body and turn it to the
/// camera. Soft on purpose: a thin bright ring aliases into dots.
MeshGeometry _coronaRing({int segments = 96}) {
  // (radius, alpha) stops, from the body's edge outward.
  const stops = [(1.0, 0.9), (1.35, 0.35), (1.9, 0.08), (_coronaSpan, 0.0)];
  final b = GeometryBuilder(deduplicate: false);
  final rows = <List<int>>[];
  for (final (r, a) in stops) {
    b
      ..normal(vm.Vector3(0, 0, 1))
      ..color(vm.Vector4(1, 1, 1, a));
    rows.add([
      for (var i = 0; i < segments; i++)
        b.addVertex(vm.Vector3(r * math.cos(2 * math.pi * i / segments),
            r * math.sin(2 * math.pi * i / segments), 0)),
    ]);
  }
  for (var k = 0; k + 1 < rows.length; k++) {
    for (var i = 0; i < segments; i++) {
      final j = (i + 1) % segments;
      b
        ..addTriangle(rows[k][i], rows[k + 1][j], rows[k][j])
        ..addTriangle(rows[k][i], rows[k + 1][i], rows[k + 1][j]);
    }
  }
  return b.build();
}
