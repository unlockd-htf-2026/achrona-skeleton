/// Achrona — the heal flare (GLOBE-02), ported from `globe/src/flare.js`.
///
/// A white-hot core scale-pulse plus an expanding cyan shockwave ring, with a
/// brief bloom OVERDRIVE so the flare is momentarily the brightest thing on
/// screen. In the JS this was a three.js `UnrealBloomPass` whose `strength` was
/// driven per frame; here it is `EnvironmentSettings.bloomIntensity`, which
/// flutter_scene runs on **every** platform — including web, through its own
/// WebGL2 backend. That single fact is what PORT-07 is betting on, which is why
/// this is the first thing Phase 2 ports.
///
/// [FlareQueue] is deliberately dependency-free (no engine imports) so the
/// strobe cap stays unit-testable, exactly as `createFlareQueue` was in JS.
library;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'palette.dart';

/// ≤3 flashes/sec photosensitivity cap → ≥334ms between flare STARTS.
///
/// A locked accessibility requirement. Heals are never dropped, only spaced.
const Duration kMinFlareInterval = Duration(milliseconds: 334);

const Duration _attack = Duration(milliseconds: 120);
const Duration _duration = Duration(milliseconds: 1300);

/// Globe radius is 1.0 here; the JS worked in globe.gl's 100-unit world, so
/// every size below is its JS constant ÷ 100.
const double _coreRadius = 0.02; // JS CORE_RADIUS 2.0
const double _ringMax = 0.16; // JS RING_MAX 16
const double _surfaceAlt = 1.012; // JS getCoords(..., 0.012)

const double _bloomBase = 0.25;
const double _bloomBoost = 0.55;

/// FIFO heal queue that starts at most one flare per [minInterval].
///
/// Pure: driven by a monotonic clock via [pump]. Owns no timers, no GPU
/// resources, no widgets — so the strobe cap can be tested directly.
class FlareQueue<T> {
  FlareQueue({required this.onStart, this.minInterval = kMinFlareInterval});

  final void Function(T item, Duration now) onStart;
  final Duration minInterval;

  final List<T> _queue = [];
  Duration? _lastStart; // null ⇒ the first heal fires immediately

  void enqueue(T item) => _queue.add(item);

  void pump(Duration now) {
    if (_queue.isEmpty) return;
    final last = _lastStart;
    if (last != null && now - last < minInterval) return;
    _lastStart = now;
    onStart(_queue.removeAt(0), now);
  }

  int get pending => _queue.length;
}

/// Envelope 0→1→0: linear ramp to peak over the attack, quadratic ease-out
/// after. The peak (=1) lands at the end of the attack — the brightest instant.
double flareEnvelope(Duration age) {
  final ms = age.inMicroseconds / 1000.0;
  final attackMs = _attack.inMilliseconds.toDouble();
  final totalMs = _duration.inMilliseconds.toDouble();
  if (ms <= attackMs) return (ms / attackMs).clamp(0.0, 1.0);
  final decay = (ms - attackMs) / (totalMs - attackMs);
  return (1 - decay * decay).clamp(0.0, 1.0);
}

class _ActiveFlare {
  _ActiveFlare(this.t0, this.core, this.ring);

  final Duration t0;
  final Node core;
  final Node ring;
}

/// Renders queued heal flares and drives the bloom overdrive.
///
/// Attached as a [Component] so the engine ticks it on the render path — the
/// documented alternative to a hand-rolled `Ticker`.
class FlareLayer extends Component {
  FlareLayer(this._scene);

  final Scene _scene;

  late final FlareQueue<vm.Vector3> _queue = FlareQueue<vm.Vector3>(
    onStart: _start,
  );
  final List<_ActiveFlare> _active = [];
  Duration _now = Duration.zero;

  /// Enqueue a flare at [surface], a point on a (drifted) shard; the flare
  /// sits just above it.
  void enqueueAt(vm.Vector3 surface) => _queue.enqueue(surface.clone());

  void _start(vm.Vector3 normal, Duration now) {
    final pos = normal * _surfaceAlt;

    final core = Node(
      mesh: Mesh(
        SphereGeometry(radius: _coreRadius, segments: 16, rings: 12),
        UnlitMaterial()
          ..alphaMode = AlphaMode.blend
          ..baseColorFactor = srgb(0xFFFFFFFF, alpha: 1),
      ),
    )..position = pos;

    // Base outer radius 1.0, so the node's scale IS the world radius.
    final ring = Node(
      mesh: Mesh(
        RingGeometry(innerRadius: 0.72, outerRadius: 1.0, segments: 48),
        UnlitMaterial()
          ..alphaMode = AlphaMode.blend
          ..baseColorFactor = srgb(kCyan, alpha: 0.9),
      ),
    )..position = pos;
    // flutter_scene's RingGeometry lies in the **XZ plane with normal +Y** —
    // unlike three.js's, which is XY with normal +Z. So `lookAt(centre)`, which
    // aligns +Z, leaves the disc slicing THROUGH the globe instead of lying on
    // it. Rotate +Y onto the surface normal instead.
    ring.rotation = vm.Quaternion.fromTwoVectors(vm.Vector3(0, 1, 0), normal.normalized());

    _scene.add(core);
    _scene.add(ring);
    _active.add(_ActiveFlare(now, core, ring));
  }

  @override
  void update(double deltaSeconds) {
    _now += Duration(microseconds: (deltaSeconds * 1e6).round());
    _queue.pump(_now);

    var peak = 0.0;
    for (var i = _active.length - 1; i >= 0; i--) {
      final f = _active[i];
      final age = _now - f.t0;
      if (age >= _duration) {
        _scene.remove(f.core);
        _scene.remove(f.ring);
        _active.removeAt(i);
        continue;
      }

      final env = flareEnvelope(age);
      if (env > peak) peak = env;

      // Core: scale pulse 1.0→1.4→1.0, fading out.
      final s = _coreRadius * (1 + 0.4 * env) / _coreRadius;
      f.core.scale = vm.Vector3.all(s);
      (f.core.mesh!.primitives.first.material as UnlitMaterial).baseColorFactor =
          srgb(0xFFFFFFFF, alpha: env);

      // Ring: grow 0→_ringMax over its life (ease-out), fading as it expands.
      final t = age.inMicroseconds / _duration.inMicroseconds;
      final grow = 1 - (1 - t) * (1 - t);
      f.ring.scale = vm.Vector3.all(0.005 + _ringMax * grow);
      (f.ring.mesh!.primitives.first.material as UnlitMaterial).baseColorFactor =
          srgb(kCyan, alpha: env * 0.9);
    }

    // Bloom OVERDRIVE: at any flare's peak the whole scene blooms hard, so the
    // white core dominates without washing the territories out. `postProcess`
    // is the live effect object, so this is a field write per frame rather
    // than rebuilding an EnvironmentSettings snapshot.
    _scene.postProcess.bloom.intensity = _bloomBase + _bloomBoost * peak;
  }
}
