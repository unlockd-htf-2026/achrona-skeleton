/// Achrona — the shared globe, and the way into the game.
///
/// The globe is home: PLAY runs a level on top of it, and coming back shows
/// what the run did — the camera swings to each region it healed and flares
/// there. Heals that arrive while a level is up are held, not wasted offscreen.
///
/// Phase 2 / SPIKE-05 — the heal flare on flutter_scene's post stack.
///
/// Ported first, deliberately: the territories are geometry and will work, but
/// the flare is the **post-processing stack**, which is the thing PORT-07 bets
/// the whole migration on. On web this runs through fscene's own WebGL2
/// backend rather than Impeller, so "bloom works on web" is a claim to verify,
/// not inherit.
///
/// Tap anywhere to fire a heal. Rapid taps exercise the ≤3/sec strobe cap.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'fx/desync.dart';
import 'globe/camera.dart';
import 'globe/chrome.dart';
import 'globe/desync_void.dart';
import 'globe/flare.dart';
import 'globe/landmarks.dart';
import 'globe/menus.dart';
import 'globe/seals.dart';
import 'globe/territories.dart';
import 'globe/world.dart';
import 'globe/palette.dart';
import 'globe/progress.dart';
import 'hero_model.dart';
import 'level_one.dart';
import 'my_level.dart';
import 'team_levels.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: GlobePage()),
);

class GlobePage extends StatefulWidget {
  const GlobePage({super.key});

  @override
  State<GlobePage> createState() => _GlobePageState();
}

class _GlobePageState extends State<GlobePage> {
  final Scene scene = Scene();
  Node? camera;
  FlareLayer? flares;
  Territories? territories;
  Landmarks? landmarks;
  Seals? _seals;
  World? world;
  GlobeLink _link = GlobeLink.connecting;
  double? _liveCorruption;
  bool _hasNodes = false;

  /// The Desync glitch, the same shader the level runs: a faint haze that
  /// scales with how corrupted the world is, and clears for a moment on every
  /// heal — the curse lifting where you can see it.
  PostEffect? _desyncFx;
  double _desync = 0;
  DesyncVoid? _void;

  /// The selector's picks: which level, played by whom.
  int _level = 0;

  /// Every level on the globe: ours, then one per team.
  List<(String, LevelSpec)> _levels = kLevels;
  int _hero = 0;

  /// Supplied at build time so no key is ever committed:
  ///   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  Object? error;
  final math.Random _rng = math.Random(7);

  /// Global rollup. The live `world_state.corruption_pct` once it arrives,
  /// otherwise derived from region state so the readout is never blank.
  double? get _corruptionPct {
    final live = _liveCorruption;
    if (live != null) return live;
    final terr = territories;
    if (terr == null) return null;
    final worst = kRegionIds
        .map((id) => math.max(terr.state[id]!.lock, terr.state[id]!.fill))
        .reduce((a, b) => a + b);
    return worst / kRegionIds.length * 100;
  }

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    try {
      await Scene.initializeStaticResources();

      _void = await dressPlanet(scene);
      _desyncFx = await addDesyncEffect(scene);
      scene.add(Node()..addComponent(_EveryFrame(_tickDesync)));

      final terr = await Territories.load();
      terr
        ..addTo(scene)
        ..restyle();
      // The teams' levels stand beside ours: one landmark each.
      final teams = _teams = await loadTeamLevels();
      _levels = [
        ...kLevels,
        for (final t in teams) ('${t.team} · ${t.card.title}', t.spec),
      ];
      final progress = _progress = await Progress.load();
      _cleared.addAll(
          progress.clearedIndices([for (final (name, _) in _levels) name]));
      final marks = await Landmarks.load(terr,
          teamSlots: [for (final t in teams) t.slot])
        ..attach()
        ..select(0, cleared: _cleared);

      // Build-locked regions are bound by seals, read off region state.
      final seals = _seals = await Seals.create(terr);
      scene.add(Node()..addComponent(seals));

      final layer = FlareLayer(scene);
      // A component needs a node to ride; this one is the layer's own root.
      scene.add(Node()..addComponent(layer));

      final cam = Node()
        // The frustum is tight (far 20, not the default 1000) for depth
        // precision. Near was 0.5 while an ocean sphere sat a hair under the
        // plates and z-fought them; there is no ocean now, and the level
        // close-up sits ~0.55 from its landmark — at 0.5 the land in front of
        // it was clipped away. 0.05 keeps ~1e-5 of depth resolution at the
        // resting distance, far finer than any gap left in the scene.
        ..addComponent(
          CameraComponent(
            activateOnMount: true,
            projection: PerspectiveProjection(near: 0.05, far: 20),
          ),
        )
        ..addComponent(
          OrbitCameraController(
            target: vm.Vector3.zero(),
            distance: 3.0,
            minDistance: 1.6,
            maxDistance: 8,
          ),
        );
      scene.add(cam);
      _void?.camera = cam.getComponent<CameraComponent>()!.toCamera();
      seals.camera = cam.getComponent<CameraComponent>()!.toCamera();

      if (mounted) {
        setState(() {
          camera = cam;
          flares = layer;
          territories = terr;
          landmarks = marks;
        });
      }

      // Warm the hero picker's stage while the opening plays — it is heavy,
      // and the first ENTER should not wait on it.
      HeroStage.shared().ignore();

      // Live wiring. Without config the globe stays on the reference's dark
      // state rather than pretending to be connected.
      final live = World.connect(url: _supabaseUrl, anonKey: _supabaseAnonKey);
      if (live == null) {
        if (mounted) setState(() => _link = GlobeLink.lost);
      } else {
        world = live;
        live
          ..onNodes = (nodes) {
            _fireHeals(nodes, terr);
            terr.update(nodes);
            if (mounted) setState(() => _hasNodes = nodes.isNotEmpty);
          }
          ..onRollup = (pct) {
            if (mounted) setState(() => _liveCorruption = pct);
          }
          ..onConnectionChange = (connected) {
            if (mounted) {
              setState(
                () => _link = connected ? GlobeLink.live : GlobeLink.lost,
              );
            }
          }
          ..start();
      }
    } catch (e, st) {
      debugPrint('scene init failed: $e\n$st');
      if (mounted) setState(() => error = e);
    }
  }

  /// Last-seen (structural, residual) pools per node, for heal detection.
  final Map<String, (double, double)> _prev = {};

  /// A level is on top of the globe. Heals wait in [_held] until it is gone.
  bool _away = false;
  final Set<int> _held = {};

  /// A heal is either pool DROPPING between two Realtime snapshots. The
  /// reference (`main.js fireHeals`) watched structural only — the build gate —
  /// but a finished run drains *residual*, so that alone never flared for a
  /// run. One flare per region: a run drains every unlocked node in a track,
  /// and five flares on one centroid is noise, not news.
  void _fireHeals(List<GlobeNode> nodes, Territories terr) {
    final healed = <int>{};
    for (final n in nodes) {
      final prev = _prev[n.challengeId];
      // Never flare on the initial seed — only on a real drop.
      if (prev != null &&
          (n.structuralRemaining < prev.$1 || n.residualRemaining < prev.$2)) {
        healed.add(n.regionId);
      }
      _prev[n.challengeId] = (n.structuralRemaining, n.residualRemaining);
    }
    if (_away) {
      _held.addAll(healed);
    } else {
      healed.forEach(_showHeal);
    }
  }

  /// Choose a level: light its landmark and swing the camera round to it.
  /// Choose a level: dive to its landmark, as the opening does.
  void _selectLevel(int i) => _diveTo(i);

  /// Where the chosen level's card sits on screen, beside its landmark —
  /// null when the camera is not down on a level. Projected every frame.
  final ValueNotifier<Offset?> _menuAt = ValueNotifier(null);
  Size _view = Size.zero;

  void _placeMenu() {
    final marks = landmarks, terr = territories, cam = camera;
    if (!_closeUp ||
        _intro != null ||
        marks == null ||
        terr == null ||
        cam == null ||
        _view.isEmpty) {
      _menuAt.value = null;
      return;
    }
    final site = marks.sites[_level];
    // A little above the landmark, so the card sits beside its top.
    final at = site * (terr.liftOf(marks.regions[_level]) + 0.05);
    _menuAt.value = cam
        .getComponent<CameraComponent>()!
        .toCamera()
        .worldToScreen(at, _view);
  }

  /// ENTER: choose who goes in, then play.
  Future<void> _enter() async {
    // The level's downloads run while the hero is being picked.
    prefetchLevel(_levels[_level].$2, kHeroes[_hero]).ignore();
    final hero = await showHeroPicker(
      context,
      level: _levels[_level].$1,
      initial: _hero,
    );
    if (hero == null || !mounted) return;
    setState(() => _hero = hero);
    await _play();
  }

  /// Whether the camera is down on a level's landmark (see [_diveTo]).
  bool _closeUp = false;

  /// Dive to level [i]: the orbit pivots onto its landmark and drops close,
  /// tilted so the landmark is seen standing. Touching
  /// the globe leaves ([_leaveCloseUp]); picking another level hops to it.
  void _diveTo(int i) {
    final orbit = camera?.getComponent<OrbitCameraController>();
    final marks = landmarks, terr = territories;
    if (orbit == null || marks == null || terr == null) return;
    setState(() => _level = i);
    marks.select(i, cleared: _cleared);
    final site = marks.sites[i] * terr.liftOf(marks.regions[i]);
    // Angles around the pivot the orbit is on now — the core, or the last
    // landmark, both close enough to the site's direction for the delta.
    final turn = orbitToward(camera!.globalTransform.getTranslation(), site);
    orbit
      ..minDistance = 0.3
      ..orbitBy(turn.azimuth, turn.polar - 0.6)
      ..frame(
        vm.Aabb3.centerAndHalfExtents(site, vm.Vector3.all(0.1)),
        margin: 1.6,
      );
    _closeUp = true;
    focusLevel(scene, orbit.distance);
  }

  /// Glide back out from a close-up to the whole world.
  void _leaveCloseUp() {
    if (!_closeUp) return;
    _closeUp = false;
    scene.depthOfField.enabled = false;
    final orbit = camera?.getComponent<OrbitCameraController>();
    if (orbit == null) return;
    // A box of radius 1 at the core frames back to the resting distance, 3.
    orbit
      ..minDistance = 1.6
      ..frame(
        vm.Aabb3.centerAndHalfExtents(
          vm.Vector3.zero(),
          vm.Vector3.all(1 / math.sqrt(3)),
        ),
      );
  }

  /// Swing the orbit round to [at], by default aimed a little below it so
  /// what stands there is seen standing, not from above; [below] 0 centres it.
  void _swingTo(vm.Vector3 at, {double below = 0.35}) {
    final cam = camera;
    if (cam == null) return;
    final turn = orbitToward(cam.globalTransform.getTranslation(), at);
    cam.getComponent<OrbitCameraController>()!.orbitBy(
      turn.azimuth,
      turn.polar - below,
    );
  }

  /// A tap picks the landmark under it; offline, a tap anywhere else fakes a
  /// heal (with a live world, a fake heal would lie).
  void _tap(TapUpDetails d, Size view) {
    if (_intro != null) return _skipIntro();
    final cam = camera, marks = landmarks;
    if (cam != null && marks != null) {
      final hit = marks.hit(
        cam.getComponent<CameraComponent>()!.toCamera(),
        view,
        d.localPosition,
        cam.globalTransform.getTranslation(),
      );
      if (hit != null) return _selectLevel(hit);
    }
    if (_link != GlobeLink.live) _fireHeal();
  }

  /// Swing round to [regionId] and flare there. The flare queue's strobe cap
  /// spaces several out; the camera goes to the last one asked for.
  void _showHeal(int regionId) {
    final terr = territories, cam = camera;
    if (terr == null || cam == null) return;
    _leaveCloseUp();
    final at = terr.centroidOf(regionId);
    final turn = orbitToward(cam.globalTransform.getTranslation(), at);
    cam.getComponent<OrbitCameraController>()!.orbitBy(
      turn.azimuth,
      turn.polar,
    );
    _desync = 0;
    // Land the flare as the eye arrives, not while the region is still round
    // the back.
    Future<void>.delayed(
      const Duration(milliseconds: 700),
      () => flares?.enqueueAt(at),
    );
  }

  /// Per frame: aim the fog at the current zoom, and ease the glitch toward
  /// the world's corruption (0.12 at 100%, none when clean). A heal sets the
  /// glitch to zero, so it visibly clears and creeps back.
  void _tickDesync(double dt) {
    _placeMenu();
    // Close up, focus rides the dive: the orbit's distance IS the distance
    // to the landmark it pivots on.
    final orbit = camera?.getComponent<OrbitCameraController>();
    if (_closeUp && orbit != null) focusLevel(scene, orbit.distance);
    // Fog follows the zoom and starts just past the void (distance d), so
    // the void stays black and the near shards crisp, while the far side of
    // the world fades into violet haze. (Fog has no per-material opt-out.)
    final eye = camera?.globalTransform.getTranslation();
    if (eye != null) {
      final d = eye.length;
      scene.fog
        ..start = d + 0.1
        ..end = d + 1.3;
    }
    final corruption = (_corruptionPct ?? 0) / 100;
    final hole = _void;
    if (hole != null) {
      _tickIntro(dt, hole, corruption);
      hole.tick(dt, corruption);
    }
    territories?.tick(dt, whole: hole?.whole ?? 0);
    final target = corruption * 0.12;
    _desync += (target - _desync) * math.min(1.0, dt * 0.8);
    setDesync(_desyncFx, _desync);
  }

  /// The opening: Achrona whole, then the Desync cracks it open. Seconds
  /// since the globe first drew; null once it has played.
  ///
  /// ponytail: plays on every launch. Once per device needs a stored flag
  /// (shared_preferences — not a dependency yet).
  double? _intro = 0;

  /// The beats: the world whole; the crack at [_crackAt]; the crust bursts
  /// at [_fallAt]; the seals bind every zone from [_sealAt]; the camera
  /// centres on Base at [_swingAt]; Base's seal breaks at [_openAt] — the
  /// first zone opens, every team starts there — and at [_diveAt] the camera
  /// dives to the first level. The caption card clears at [_endAt].
  static const double _crackAt = 2.6,
      _fallAt = 3.8,
      _sealAt = 5.2,
      _swingAt = 7.2,
      _openAt = 8.4,
      _diveAt = 9.8,
      _endAt = 13.0;

  /// The line under the opening, per beat (the level cutscenes' voice).
  static const _lines = [
    (0.3, 'ACHRONA WAS WHOLE — MAGIC AND MACHINE, ONE WORLD'),
    (_crackAt, 'THEN THE DESYNC CAME'),
    (_fallAt, 'IT TORE THE WORLD APART'),
    (_sealAt, 'AND BOUND EVERY LAND IN ITS SEALS'),
    (_swingAt, 'BUT ONE SEAL IS WEAKENING…'),
    (_openAt, 'THE FIRST LAND IS FREE'),
    (_diveAt, 'ENTER THE SEALED GATE — AND HEAL ACHRONA'),
  ];

  /// The opening's caption, or null when there is none.
  String? _caption;

  /// Drive the opening, and afterwards seal the world only when it is fully
  /// purified — and break it again if the curse ever returns.
  void _tickIntro(double dt, DesyncVoid hole, double corruption) {
    final t = _intro;
    if (t == null) {
      hole.wholeTarget = corruption <= 0.005 ? 1 : 0;
      return;
    }
    if (t == 0) {
      // Open on the whole world: snap, don't ease.
      hole.wholeTarget = 1;
      hole.tick(1e3, corruption);
      // Hold it there until the land and the camera are up — the scene ticks
      // from the moment the void exists, well before the rest has loaded.
      if (territories == null || landmarks == null || hole.camera == null) {
        return;
      }
      // Seen it before, on this device: open on the world as the film
      // leaves it, without the film. `?intro` shows it anyway.
      if ((_progress?.seenOpening ?? false) &&
          !Uri.base.queryParameters.containsKey('intro')) {
        _seals?.reveal(instant: true);
        _openBase();
        // Already broken — snap there rather than play the shattering.
        hole
          ..wholeTarget = 0
          ..tick(1e3, corruption);
        if (mounted) setState(() => _intro = null);
        return;
      }
    }
    // Clamped: a stalled first frame (the view still revealing, a busy tab)
    // must not skip the whole show in one step.
    final next = t + math.min(dt, 0.05);
    bool at(double beat) => t < beat && next >= beat;
    for (final (beat, line) in _lines) {
      if (at(beat) && mounted) setState(() => _caption = line);
    }
    if (at(_crackAt)) {
      hole.crack(16);
      _desync = 0.85; // the glitch burst, as a hit in the level
    }
    if (at(_fallAt)) {
      hole.wholeTarget = 0;
      territories?.burst();
    }
    if (at(_sealAt)) _seals?.reveal();
    if (at(_swingAt)) _swingTo(kRegionCentroids[1]!, below: 0);
    if (at(_openAt)) _openBase();
    if (at(_diveAt)) _diveTo(0);
    if (next >= _endAt) {
      if (mounted) setState(() => _caption = null);
      _intro = null;
      _progress?.sawOpening();
      return;
    }
    _intro = next;
  }

  /// Base's seal breaks. Offline there is no world to say Base is open, so
  /// the opening does.
  void _openBase() {
    final terr = territories;
    if (world == null && terr != null) {
      terr.state[1]!.lock = 0;
      terr.restyle();
    }
    _seals?.release();
  }

  /// Any key or tap during the opening jumps to where it ends: the world
  /// broken, Base open, the camera diving to the first level. Beats already
  /// played are not repeated.
  void _skipIntro() {
    final t = _intro;
    if (t == null || t == 0 || _seals == null) return; // not started yet
    if (t < _fallAt) territories?.burst();
    if (t < _sealAt) _seals!.reveal(instant: true);
    if (t < _openAt) _openBase();
    if (t < _diveAt) _diveTo(0);
    setState(() {
      _caption = null;
      _intro = null;
    });
    _progress?.sawOpening();
  }

  /// What this device remembers: its cleared levels, and the opening.
  Progress? _progress;

  /// Levels cleared (this visit or before), by index into [_levels]. Their landmarks
  /// wear the healed colour and the menu ticks them.
  final Set<int> _cleared = {};

  /// Cleared on this trip, not yet shown on the globe.
  final Set<int> _newlyCleared = {};

  /// The team levels, in [_levels] order after [kLevels].
  List<TeamLevel> _teams = const [];

  Future<void> _play() async {
    _away = true;
    // ponytail: wall-clock since the run (or the last clear) began, intro
    // included — onCleared carries no time. Pass the run's own seconds
    // through onCleared if best times ever need to be exact.
    final clock = Stopwatch()..start();
    // One route for the whole run: N swaps the level inside it. A
    // pushReplacement would finish this await while the player is still
    // playing, and the globe would think they were back.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LevelRun(
          start: _levels[_level].$2,
          hero: kHeroes[_hero],
          onCleared: (spec) {
            final i = _levels.indexWhere((l) => identical(l.$2, spec));
            if (i >= 0 && _cleared.add(i)) {
              _newlyCleared.add(i);
              _progress?.clear(_levels[i].$1);
            }
            // Another team's level: count it (every clear, for the best time).
            // The first one drains the owner's continent and Realtime flares it.
            final t = i - kLevels.length;
            if (t >= 0) {
              unawaited(reportLevelClear(_teams[t],
                  seconds: clock.elapsedMilliseconds / 1000));
            }
            clock.reset();
          },
        ),
      ),
    );
    _away = false;
    landmarks?.select(_level, cleared: _cleared);
    final held = {..._held};
    _held.clear();
    // A cleared level heals the land it stands on. Live, the Worker drains
    // the pool and Realtime says so (held above); offline the globe does it.
    for (final i in _newlyCleared) {
      final region = landmarks?.regions[i];
      if (region == null) continue;
      if (world == null) _healRegion(region);
      held.add(region);
    }
    _newlyCleared.clear();
    held.forEach(_showHeal);
    if (mounted) setState(() {});
  }

  /// Stand in for a Realtime heal when no backend is configured.
  ///
  /// Drops one region a notch — structural first (the build gate: LOCKED →
  /// UNLOCKED, the territory rises and goes neon), then residual (UNLOCKED →
  /// CLEAN, it settles cyan) — and flares on that region's centroid, exactly
  /// as `main.js fireHeals()` does off a Realtime delta.
  void _fireHeal() {
    final terr = territories;
    if (terr == null) return;

    final id = kRegionIds[_rng.nextInt(kRegionIds.length)];
    _healRegion(id);
    flares?.enqueueAt(terr.centroidOf(id));
  }

  /// Offline, heal [id] a notch: structural first (the build gate), then
  /// residual — what a Realtime drain would report.
  void _healRegion(int id) {
    final terr = territories;
    if (terr == null) return;
    final s = terr.state[id]!;
    if (s.lock > 0.001) {
      s.lock = (s.lock - 0.34).clamp(0.0, 1.0);
    } else {
      s.fill = (s.fill - 0.34).clamp(0.0, 1.0);
    }
    terr.restyle();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        backgroundColor: const Color(kBgVoid),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '$error',
              style: const TextStyle(color: Color(0xFFFF6B8A), fontSize: 13),
            ),
          ),
        ),
      );
    }

    final cam = camera;
    if (cam == null) {
      return const Scaffold(
        backgroundColor: Color(kBgVoid),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(kBgVoid),
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (_intro == null || e is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          _skipIntro();
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            Positioned.fill(
              // The void's bolts are PolylineGeometry, inert until told the
              // camera AND the viewport size, so the size is threaded from the
              // layout rather than guessed from MediaQuery.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _view = Size(constraints.maxWidth, constraints.maxHeight);
                  _void?.viewport = _view;
                  // Touching the globe leaves a level close-up. (No ambient
                  // spin: every camera move is deliberate — the opening, the
                  // dive, a heal swing — and a spin only carried it off.)
                  return Listener(
                    onPointerDown: (_) => _leaveCloseUp(),
                    child: CameraControls(
                      controller: cam.getComponent<OrbitCameraController>()!,
                      child: SceneView(scene, pixelRatio: kScenePixelRatio),
                    ),
                  );
                },
              ),
            ),
            // Taps land above the scene so the orbit controller still gets drags.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) => _tap(d, constraints.biggest),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // The JS kept all text in the DOM, never in WebGL, for selectability
            // and screen readers. Flutter widgets over the SceneView are the same
            // separation.
            GlobeChrome(
              // Offline is the point of a showcase build, not news.
            link: kShowcase ? GlobeLink.connecting : _link,
              corruptionPct: _corruptionPct,
              hasNodes: _hasNodes || _link != GlobeLink.live,
            ),
            // Beside the chosen level's landmark, while the camera is on it.
            ValueListenableBuilder<Offset?>(
              valueListenable: _menuAt,
              builder: (context, at, _) => at == null
                  ? const SizedBox.shrink()
                  : Positioned(
                      left: at.dx + 26,
                      top: at.dy - 24,
                      child: LandmarkMenu(
                        name: _levels[_level].$1,
                        onEnter: _enter,
                      ),
                    ),
            ),
            if (kShowStats) const Positioned(top: 12, right: 16, child: _Fps()),
          // The opening's caption card.
            Positioned(
              left: 24,
              right: 24,
              bottom: 36,
              child: IgnorePointer(
                child: Center(child: _CaptionCard(_caption)),
              ),
            ),
            Positioned(
              right: 28,
              bottom: 22,
              // Hidden through the opening; it arrives with the first level.
              child: IgnorePointer(
                ignoring: _intro != null,
                child: AnimatedOpacity(
                  opacity: _intro == null ? 1 : 0,
                  duration: const Duration(milliseconds: 800),
                  child: LevelDropdown(
                    levels: [for (final (name, _) in _levels) name],
                  cleared: _cleared,
                    level: _level,
                    onLevel: _selectLevel,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Desync void and the post stack — everything the globe draws before
/// the territories. Returns the void so the world's corruption can drive its
/// pulse. Shared with `snapshots/globe_snapshot_test.dart`.
///
/// There is no ocean: the Desync broke the world, and the continents hang as
/// shards around the hole it left. That is what stops them reading as Earth.
Future<DesyncVoid> dressPlanet(Scene scene) async {
  final hole = await DesyncVoid.create(scene);

  // Bloom threshold is high on purpose: only the white-hot flare core
  // blooms hard, so the planet stays crisp instead of hazing out. This
  // mirrors the JS `UnrealBloomPass(..., threshold: 0.30)` decision.
  scene.environmentSettings = EnvironmentSettings(
    toneMapping: ToneMappingMode.aces,
    exposure: 1.0,
    // The level's grade, so the globe and the dungeon read as one world.
    colorGradingEnabled: true,
    saturation: 1.12,
    contrast: 1.16,
    temperature: -0.1,
    bloomEnabled: true,
    bloomThreshold: 0.75,
    bloomIntensity: 0.25,
    bloomScatter: 0.8,
    vignetteEnabled: true,
    vignetteIntensity: 0.4,
    // Atmosphere, the level's way: fog that leaves the void and the near
    // shards crisp and fades the far side of the world into a violet haze.
    // Tuned for the resting orbit (distance 3); `GlobePage` re-aims it as the
    // camera zooms.
    fogEnabled: true,
    fogMode: FogMode.linear,
    fogColor: vm.Vector3(0.05, 0.02, 0.11),
    fogStart: 3.1,
    fogEnd: 4.3,
    fogMaxOpacity: 0.7,
  );
  return hole;
}

/// Runs [onUpdate] every frame, riding the scene's own component loop.
class _EveryFrame extends Component {
  _EveryFrame(this.onUpdate);
  final void Function(double dt) onUpdate;

  @override
  void update(double deltaSeconds) => onUpdate(deltaSeconds);
}

/// Depth of field on a level's landmark [distance] away: it stays crisp and
/// the void and far shards melt into bokeh. Only while close up — the pass
/// costs frame time. Shared with the snapshot fixture.
void focusLevel(Scene scene, double distance) => scene.depthOfField
  ..enabled = true
  // The web/mobile tier; this runs on phones.
  ..quality = DepthOfFieldQuality.low
  ..focusDistance = distance
  // The lens treats units as metres and the globe is ~1 across, so the
  // in-focus band is thin: a modest aperture and blur keep the whole level
  // crisp and soften only the void and the far side.
  ..fStop = 2.8
  ..blurScale = kDofBlur;

/// How strongly the close-up blurs what is off the focus plane. Knob.
const double kDofBlur = 1.5;

/// The opening's caption: a dark card at the bottom that fades and rises
/// between lines, in the level cutscenes' voice.
class _CaptionCard extends StatelessWidget {
  const _CaptionCard(this.line);

  final String? line;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 900),
    // The old line fades out in the first half, the new one rises in the
    // second: never two lines on top of each other.
    switchInCurve: const Interval(0.5, 1),
    switchOutCurve: const Interval(0.5, 1),
    transitionBuilder: (child, t) => FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: t, curve: Curves.easeOut)),
        child: child,
      ),
    ),
    child: line == null
        ? const SizedBox.shrink(key: ValueKey('none'))
        : Container(
            key: ValueKey(line),
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xD90A0818),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(kNeon).withValues(alpha: 0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(kNeon).withValues(alpha: 0.25),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Text(
              line!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                letterSpacing: 3,
                height: 1.4,
              ),
            ),
          ),
  );
}

/// The levels on offer, by name.
final List<(String, LevelSpec)> kLevels = [
  ('I · THE SEALED GATE', kLevelOne),
  ('II · THE DESCENT', kLevelTwo),
  ('III · THE SPIRE', kLevelThree),
  ('IV · YOUR LEVEL', kMyLevel),
];


/// Frames per second, averaged over the last second (`?stats`).
class _Fps extends StatefulWidget {
  const _Fps();

  @override
  State<_Fps> createState() => _FpsState();
}

class _FpsState extends State<_Fps> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _since = Duration.zero;
  int _frames = 0;
  String _text = '… fps';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _frames++;
      if (elapsed - _since >= const Duration(seconds: 1)) {
        final secs = (elapsed - _since).inMicroseconds / 1e6;
        setState(() => _text = '${(_frames / secs).toStringAsFixed(0)} fps');
        _since = elapsed;
        _frames = 0;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_text,
      style: const TextStyle(color: Colors.white70, fontSize: 12));
}


/// One trip into the levels: the chosen one, and each N after it, inside a
/// single route. A new key per level, so every level is built from nothing,
/// as before.
class _LevelRun extends StatefulWidget {
  const _LevelRun(
      {required this.start, required this.hero, required this.onCleared});

  final LevelSpec start;
  final HeroKind hero;
  final ValueChanged<LevelSpec> onCleared;

  @override
  State<_LevelRun> createState() => _LevelRunState();
}

class _LevelRunState extends State<_LevelRun> {
  late LevelSpec _spec = widget.start;

  @override
  Widget build(BuildContext context) => LevelOne(
        key: ObjectKey(_spec),
        spec: _spec,
        hero: widget.hero,
        onCleared: widget.onCleared,
        onNext: (next) => setState(() => _spec = next),
      );
}
