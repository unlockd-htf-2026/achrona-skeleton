/// Achrona — the binding seals on build-locked regions.
///
/// A locked region is not an icon floating over land: it is land bound by a
/// seal — a violet rune circle inscribed flat on the continent, slowly
/// turning. It rides its shard's drift (it is a child of the region's node),
/// fades out as it turns to the far side, and when the region unlocks it
/// flares, lifts and dissolves.
///
/// Seals do not exist before the Desync breaks the world: the opening
/// [reveal]s them one by one after the burst, then [release]s — from then
/// on an unlocked region's seal breaks.
///
/// Translucent draws are not held back by depth on web, so a seal round the
/// back would paint over the void; the facing fade is what hides it, not the
/// depth test.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart'
    show BlurStyle, Canvas, Color, MaskFilter, Offset, Paint, PaintingStyle,
        Path, StrokeCap;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'palette.dart';
import 'territories.dart';

/// How long an unlocking seal takes to break, in seconds.
const double _breakTime = 1.4;

/// One turn of a seal, in seconds. Knob.
const double _turn = 60;

/// How much of its continent a seal covers, as a fraction of the land's mean
/// angular spread. Knob.
const double _cover = 0.62;

/// Arrival: each seal takes this long to settle, the next starting
/// [_arriveStagger] after. Seconds.
const double _arrive = 1.2, _arriveStagger = 0.3;

class Seals extends Component {
  Seals._(this._terr, this._seals, this._spark);

  final Territories _terr;
  final Map<int, _Seal> _seals;

  /// The soft dot every break spark is drawn with.
  final Texture2D _spark;

  /// Live spark bursts: the node, its region, and its age in seconds.
  final List<(Node, int, double)> _bursts = [];

  /// The camera, for the facing fade. Without it every seal shows.
  Camera? camera;

  double _t = 0;

  /// Seconds since [reveal]; null until then — no seals at all.
  double? _revealed;

  /// While held, seals stay up whatever the region state (the opening shows
  /// every zone bound before the first one opens).
  bool _held = true;

  /// Bind the world: every seal arrives, staggered. [instant] skips the
  /// arrival and shows only the regions that really are locked.
  void reveal({bool instant = false}) {
    _revealed = instant ? 1e3 : 0;
    for (final MapEntry(key: id, value: seal) in _seals.entries) {
      seal.shown = !instant || _terr.state[id]!.isLocked;
    }
  }

  /// Let region state rule: from now on an unlocked region's seal breaks.
  void release() => _held = false;

  static Future<Seals> create(Territories terr) async {
    final texture = await Texture2D.fromImage(
      await _sigil(),
      sampling: const TextureSampling(
        mipmaps: false,
        addressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    final seals = <int, _Seal>{};
    for (final id in kRegionIds) {
      final at = kRegionCentroids[id]!;
      // Sized to the continent: its hexes' mean angular distance from the
      // centre, so the seal binds most of the land without spilling off it.
      final hexes = terr.hexCentres[id]!;
      final spread = hexes
              .map((h) => math.acos(h.dot(at).clamp(-1.0, 1.0)))
              .reduce((a, b) => a + b) /
          hexes.length;
      final material = UnlitMaterial(colorTexture: texture)
        ..alphaMode = AlphaMode.blend;
      final node =
          Node(mesh: Mesh(_cap(at, math.tan(spread * _cover)), material));
      terr.nodeOf(id).add(node);
      seals[id] = _Seal(node, material, at);
    }
    final spark = await Texture2D.fromImage(
      await _dot(),
      sampling: const TextureSampling(
        mipmaps: false,
        addressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    return Seals._(terr, seals, spark);
  }

  @override
  void update(double deltaSeconds) {
    _t += deltaSeconds;
    final since = _revealed;
    if (since == null) {
      for (final seal in _seals.values) {
        seal.node.visible = false;
      }
      return;
    }
    final now = _revealed = since + deltaSeconds;
    // Retire spark bursts once their last spark has died (lifetime ≤ 1.6 s).
    for (var i = _bursts.length - 1; i >= 0; i--) {
      final (node, id, age) = _bursts[i];
      if (age + deltaSeconds > 2.2) {
        _terr.nodeOf(id).remove(node);
        _bursts.removeAt(i);
      } else {
        _bursts[i] = (node, id, age + deltaSeconds);
      }
    }
    final eye = camera?.position.normalized();
    // Down close (a dive to a team landmark on sealed land), a seal is not a
    // mark on the world any more but a translucent sheet across the view,
    // and web draws translucency over everything: it washed the land white.
    // Full from orbit, gone within ~0.6 of the surface.
    final near = camera == null
        ? 1.0
        : ((camera!.position.length - 1.6) / 0.6).clamp(0.0, 1.0);
    for (final (i, MapEntry(key: id, value: seal)) in _seals.entries.indexed) {
      if (!_held) {
        if (_terr.state[id]!.isLocked) {
          seal
            ..breaking = null
            ..shown = true;
        } else if (seal.shown && seal.breaking == null) {
          seal.breaking = 0; // just unlocked: break it
          _sparks(id, seal);
        }
      }
      // Arriving: it descends onto the land, whirling, and settles.
      final a = ((now - i * _arriveStagger) / _arrive).clamp(0.0, 1.0);
      final settle = 1 - (1 - a) * (1 - a);
      var alpha = seal.shown ? settle : 0.0;
      var lift = 1 + 0.06 * (1 - settle);
      var whirl = 4 * (1 - settle) * (1 - settle);
      var flash = 1.0;
      final b = seal.breaking;
      if (b != null) {
        final k = (b / _breakTime).clamp(0.0, 1.0);
        lift = 1 + 0.08 * k; // it lifts off the land as it dissolves
        flash = 1 + 2.5 * (1 - k) * (1 - k); // a flare, then gone
        alpha = 1 - k;
        whirl = 0;
        seal.breaking = b + deltaSeconds;
        if (k >= 1) {
          seal
            ..shown = false
            ..breaking = null;
        }
      }
      // Fade out as it turns away: gone well before the limb.
      if (eye != null) {
        alpha *= ((seal.at.dot(eye) - 0.15) / 0.35).clamp(0.0, 1.0) * near;
      }
      seal.node.visible = alpha > 0.01;
      if (!seal.node.visible) continue;
      // A cap turns about its own centre axis, which runs through the core,
      // so turning keeps it on the sphere.
      seal.node
        ..rotation = vm.Quaternion.axisAngle(seal.at,
            (_t * 2 * math.pi / _turn + whirl) * (id.isEven ? 1 : -1))
        ..scale = vm.Vector3.all(lift);
      final c = emissive(kNeon, alpha: alpha, gain: 1.8 * flash);
      seal.material.baseColorFactor = c;
    }
  }
}

extension on Seals {
  /// A one-shot burst of neon sparks thrown up off the land from the seal's
  /// centre as it breaks. Simulated in the node's local space, so the node is
  /// turned to the surface normal (the emitter's hemisphere is +Y) and rides
  /// the shard; [update] retires it once the last spark has died.
  void _sparks(int id, _Seal seal) {
    final neon = srgb(kNeon);
    final system = ParticleSystem(
      maxParticles: 180,
      shape: const SphereEmitterShape(radius: 0.02, hemisphere: true),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0, count: 160)]),
      lifetime: const UniformFloat(0.7, 1.6),
      startSpeed: const UniformFloat(0.06, 0.32),
      startSize: const UniformFloat(0.008, 0.02),
      looping: false,
      duration: 0.1,
      seed: id,
      modules: [
        LinearDragModule(1.6),
        ColorOverLifeModule(GradientColor(ColorGradient([
          ColorStop(0, vm.Vector4(1, 1, 1, 1)),
          ColorStop(0.25, vm.Vector4(neon.x * 3, neon.y * 3, neon.z * 3, 1)),
          ColorStop(1, vm.Vector4(neon.x, neon.y, neon.z, 0)),
        ]))),
      ],
    );
    final up = seal.at.normalized();
    final node = Node()
      ..position = up * 1.01
      ..rotation = vm.Quaternion.fromTwoVectors(vm.Vector3(0, 1, 0), up)
      ..addComponent(ParticleEmitterComponent(
        system: system,
        material: SpriteMaterial(colorTexture: _spark),
      ));
    _terr.nodeOf(id).add(node);
    _bursts.add((node, id, 0));
  }
}

class _Seal {
  _Seal(this.node, this.material, this.at);

  final Node node;
  final UnlitMaterial material;
  final vm.Vector3 at;
  bool shown = false;

  /// Seconds into breaking, while it breaks.
  double? breaking;
}

/// The seal's surface: a square patch of the sphere around [at], half-width
/// [extent] on the tangent plane, projected down onto radius 1.004 — so it
/// lies on the curved land instead of floating off it at the rim like a flat
/// disc. UV 0..1 across the patch. Wound to face outward: translucent
/// materials ignore `doubleSided`, so a patch wound inward silently vanishes.
MeshGeometry _cap(vm.Vector3 at, double extent, {int n = 24}) {
  final up = at.normalized();
  final ref = up.y.abs() > 0.99 ? vm.Vector3(1, 0, 0) : vm.Vector3(0, 1, 0);
  final e1 = ref.cross(up)..normalize();
  final e2 = up.cross(e1)..normalize();
  final b = GeometryBuilder(deduplicate: false);
  final ids = <int>[];
  for (var j = 0; j <= n; j++) {
    for (var i = 0; i <= n; i++) {
      final u = i / n, v = j / n;
      final p = (up + e1 * ((u * 2 - 1) * extent) + e2 * ((v * 2 - 1) * extent))
        ..normalize();
      ids.add((b
            ..normal(p)
            ..texCoord(vm.Vector2(u, v)))
          .addVertex(p * 1.004));
    }
  }
  int cell(int i, int j) => ids[j * (n + 1) + i];
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      // e1 × e2 = up, so (i,j) → (i+1,j) → (i+1,j+1) winds outward.
      final a = cell(i, j), c = cell(i + 1, j + 1);
      b
        ..addTriangle(a, cell(i + 1, j), c)
        ..addTriangle(a, c, cell(i, j + 1));
    }
  }
  return b.build();
}

/// The sigil, in white (tinted per frame): a double outer ring, a band of
/// runes, a star of two interlocked triangles, and a keyhole at the heart.
/// Drawn twice — blurred for the glow, then crisp on top.
Future<ui.Image> _sigil({int size = 1024}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final c = Offset(size / 2, size / 2);
  final r = size / 2 * 0.94;
  final rng = math.Random(5);

  // Runes: each a few strokes on a small grid, fixed by the seed.
  final runes = [
    for (var i = 0; i < 28; i++)
      [
        for (var s = 0; s < 2 + rng.nextInt(2); s++)
          (
            Offset(rng.nextInt(3) - 1.0, rng.nextInt(3) - 1.0),
            Offset(rng.nextInt(3) - 1.0, rng.nextInt(3) - 1.0),
          ),
      ],
  ];

  void draw(Paint base) {
    Paint stroke(double w) => Paint()
      ..color = base.color
      ..maskFilter = base.maskFilter
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;

    canvas
      ..drawCircle(c, r, stroke(10))
      ..drawCircle(c, r * 0.93, stroke(3))
      ..drawCircle(c, r * 0.72, stroke(5));

    // The rune band between the outer rings and the inner one.
    final rr = r * 0.825, cell = r * 0.055;
    for (final (i, rune) in runes.indexed) {
      final a = i / runes.length * 2 * math.pi;
      canvas
        ..save()
        ..translate(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a))
        ..rotate(a + math.pi / 2);
      for (final (p, q) in rune) {
        if (p == q) continue;
        canvas.drawLine(p * cell, q * cell, stroke(4));
      }
      canvas.restore();
    }

    // Two interlocked triangles, inscribed in the inner ring.
    for (final turn in [0.0, math.pi]) {
      final path = Path();
      for (var k = 0; k < 3; k++) {
        final a = turn - math.pi / 2 + k * 2 * math.pi / 3;
        final p = c + Offset(math.cos(a), math.sin(a)) * (r * 0.72);
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), stroke(4));
    }
    canvas.drawCircle(c, r * 0.3, stroke(4));

    // The keyhole.
    final fill = Paint()
      ..color = base.color
      ..maskFilter = base.maskFilter;
    canvas
      ..drawCircle(c - Offset(0, r * 0.06), r * 0.085, fill)
      ..drawPath(
        Path()
          ..moveTo(c.dx - r * 0.045, c.dy - r * 0.03)
          ..lineTo(c.dx + r * 0.045, c.dy - r * 0.03)
          ..lineTo(c.dx + r * 0.08, c.dy + r * 0.17)
          ..lineTo(c.dx - r * 0.08, c.dy + r * 0.17)
          ..close(),
        fill,
      );
  }

  draw(Paint()
    ..color = const Color(0x66FFFFFF)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
  draw(Paint()..color = const Color(0xFFFFFFFF));
  return recorder.endRecording().toImage(size, size);
}

/// A soft round spark: white core, fading edge (tinted by the particles).
Future<ui.Image> _dot({int size = 64}) async {
  final recorder = ui.PictureRecorder();
  final r = size / 2.0;
  Canvas(recorder).drawCircle(
    Offset(r, r),
    r,
    Paint()
      ..shader = ui.Gradient.radial(Offset(r, r), r, const [
        Color(0xFFFFFFFF),
        Color(0x88FFFFFF),
        Color(0x00FFFFFF),
      ], const [
        0.0,
        0.35,
        1.0,
      ]),
  );
  return recorder.endRecording().toImage(size, size);
}
