import 'dart:async' as async show Timer;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:achrona_engine/src/desync/desync_wall.dart';
import 'package:achrona_engine/src/fragments/augment_perk.dart';
import 'package:achrona_engine/src/fragments/fragment_component.dart';
import 'package:achrona_engine/src/fragments/fragment_manager.dart';
import 'package:achrona_engine/src/fx/shader_controller.dart';
import 'package:achrona_engine/src/game/parallax_background.dart';
import 'package:achrona_engine/src/game/player_component.dart';
import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:achrona_engine/src/hazards/hazard_spawner.dart';
import 'package:achrona_engine/src/hazards/scheduled_spawn.dart';
import 'package:achrona_engine/src/scoring/run_result.dart';
import 'package:achrona_engine/src/weapons/gun_pickup_component.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// The main Flame game class for The Curse of Achrona.
///
/// Accepts the student hazard list and tuning constants from the app layer so
/// the engine package stays free of hard-coded student values.
///
/// Difficulty ramp (D-02): both [currentScrollSpeed] and [currentDesyncSpeed]
/// increase linearly with elapsed time, capped at sane maximums.
///
/// Audio (T-04-03): BGM and SFX calls are wrapped in try/catch — if a file is
/// missing the game degrades gracefully rather than crashing.
///
/// Shader (SHDR-01, D-16): [_shaderController] applies the desync glitch
/// effect each frame on native builds. Intensity = max(waveProximity,
/// zoneIntensity). On web ([kIsWeb]) the controller is a no-op — the game
/// renders with clean sprites (D-18).
class AchronaGame extends FlameGame
    with HasCollisionDetection, HasKeyboardHandlerComponents<World> {
  AchronaGame({
    required this.studentHazards,
    required this.initialScrollSpeed,
    required this.initialDesyncSpeed,
    required this.desyncSpeedRampPerSecond,
    required this.scrollSpeedRampPerSecond,
    required this.hazardSpawnMinSeconds,
    required this.hazardSpawnMaxSeconds,
    required this.fragmentSpawnInterval,
    required this.augmentCost,
    this.pledgedPurist = false,
    this.audioEnabled = true,
    this.scriptedSpawns,
    int? raceSeed,
  }) : _rng = raceSeed != null ? Random(raceSeed) : Random();

  /// Hazard descriptors defined by the student.
  final List<Hazard> studentHazards;

  /// Optional EXPLICIT authored spawn sequence (D-42 / ARCD-03).
  ///
  /// Null (the student-app default, D-41) → the engine runs the original
  /// random-pick hazard path, byte-for-byte unchanged. Non-null (the Arcade /
  /// Rung-4 reference-game host path) → [HazardSpawner] renders this ordered
  /// sequence deterministically by `timeOffset`. Threaded into the spawner in
  /// [onLoad]; declarative data only — the engine never executes team code.
  final List<ScheduledSpawn>? scriptedSpawns;

  /// Starting world scroll speed (px/s).
  final double initialScrollSpeed;

  /// Starting Desync wall advance speed (px/s).
  final double initialDesyncSpeed;

  /// How much the Desync speed increases per second.
  final double desyncSpeedRampPerSecond;

  /// How much the world scroll speed increases per second.
  final double scrollSpeedRampPerSecond;

  /// Minimum seconds between hazard spawns.
  final double hazardSpawnMinSeconds;

  /// Maximum seconds between hazard spawns.
  final double hazardSpawnMaxSeconds;

  /// Seconds between fragment collectible spawns (from tuning.dart — D-12).
  final double fragmentSpawnInterval;

  /// Fragments required for an augment perk (from tuning.dart — D-12).
  final int augmentCost;

  /// Whether the player pledged Purist mode on the start screen (D-10).
  final bool pledgedPurist;

  /// Whether audio is enabled (persisted via shared_preferences key
  /// 'audio_enabled'; read by the app layer on start). (SCAF-06)
  final bool audioEnabled;

  /// Shared seeded RNG source for all gameplay-affecting randomness (D-31).
  ///
  /// Initialised from the `raceSeed` constructor param:
  ///   - `raceSeed != null` → `Random(raceSeed)` — deterministic race run
  ///   - `raceSeed == null` → `Random()` — free-play (non-deterministic)
  ///
  /// Passed to [HazardSpawner] and used directly for fragment lane picks so
  /// that a single seed produces an identical hazard+fragment sequence across
  /// any two race runs (ONLN-01 fairness).
  final Random _rng;

  static const double _viewportWidth = 900;

  /// World content height (logical px). Defines the layout band (900×360) —
  /// the game is a 3-lane horizontal runner where the action happens at ground
  /// level. This is NOT the rendered viewport: the fit-to-width camera (see
  /// [_applyCameraFit]) maps [_viewportWidth] to the canvas width and lets the
  /// height fill the window, so there are no letterbox bars; taller windows
  /// reveal more sky upward (filled by [backgroundColor] + parallax).
  ///
  /// All content is bottom-anchored (`_viewportHeight - X`) or full-height, so
  /// changing this value auto-repositions the ground, player, lanes, hazards,
  /// fragments, and Desync wall. The world's bottom edge (y = _viewportHeight)
  /// is pinned to the screen bottom by the camera.
  static const double _viewportHeight = 360;

  /// Fixed world height of the parallax city band (px). Taller than the
  /// [_viewportHeight] gameplay band (~1.4×) and bottom-anchored at the ground
  /// line, so the skyline reaches up into the extra world height revealed by
  /// the camera on tall/portrait windows — filling them with city instead of a
  /// sliver of rooftops — while still scaling uniformly under the camera zoom
  /// like every other world object (NOT a per-window resize). On the canonical
  /// 2.5:1 wide window the camera reveals only the bottom 360 of this band, so
  /// the wide framing keeps its skyline-with-sky-above look.
  ///
  /// This value is a deliberate balance: the camera (zoom floored by lane
  /// fairness) reveals ~3× more world height in portrait (≈1134 px) than in the
  /// wide window (360 px), so a SINGLE fixed band — required by uniform scaling
  /// — cannot make portrait fill 45% AND keep the wide window from saturating
  /// with no sky. 500 keeps the wide skyline open while giving tall/portrait a
  /// real bottom-anchored cityscape (not a sliver).
  static const double _parallaxBandHeight = 500;
  // The Desync has already consumed everything behind its leading edge, so the
  // corruption fills that whole region — the wall is very wide and its trailing
  // edge stays off-screen for the entire run (left edge never exceeds ~-460,
  // far left of any visible area). Only the leading edge (right) is the
  // collision surface; it keeps its original trajectory
  // (_wallStartX + _wallWidth = -60, same as the old 20-wide / -80-start wall),
  // so gameplay/balance is unchanged. See DesyncWall.render for the field.
  // Leading edge at start = _wallStartX + _wallWidth = +160, i.e. a visible
  // band of the wave inside the left edge at rest (still left of the lanes).
  // The wall can't recover past this — see DesyncWall. Body trails far
  // off-screen left.
  static const double _wallStartX = -1240;
  static const double _wallWidth = 1400;
  static const double _maxScrollSpeed = 500;
  static const double _maxDesyncSpeed = 300;

  // Skill-based Desync model (see [currentDesyncSpeed]).
  static const double _recoverSpeed = 30; // px/s the wall recedes when clean
  static const double _recoverDelaySeconds = 2; // clean run before recovering
  static const double _stumbleLurch = 75; // px the wall lurches on a stumble

  /// Elapsed seconds since the run started (for difficulty ramp).
  double _elapsed = 0;

  /// Seconds since the last stumble. Once it passes [_recoverDelaySeconds] the
  /// Desync recedes (you're outrunning it); a stumble resets it to 0. Drives
  /// the skill-based pressure in [currentDesyncSpeed].
  double _cleanTime = 0;

  // --------------- Shader (SHDR-01 / SHDR-02) --------------------------
  /// The desync glitch shader controller.
  ///
  /// On native it composites the GLSL shader at canvas level (SHDR-01).
  /// On web it drives the WebGL2 overlay or ColorFilter fallback via
  /// [ShaderController.wrapWithEffect] (SHDR-02, D-17). The app layer reads
  /// this getter to wrap the [GameWidget] surface.
  final ShaderController _shaderController = ShaderController();

  /// Public read-only access to the shader controller.
  ///
  /// The app's game page calls [ShaderController.wrapWithEffect] on this,
  /// driven by [intensityNotifier], to apply the web glitch overlay /
  /// ColorFilter fallback. On native this is a no-op passthrough.
  ShaderController get shaderController => _shaderController;

  /// Frame-updated effect intensity in `[0.0, 1.0]` (SHDR-02).
  ///
  /// Updated each frame in [_updateShaderIntensity] with the same
  /// `max(waveProximity, zoneIntensity)` value (D-16) used by the native
  /// shader path. The app layer listens to this via a
  /// `ValueListenableBuilder` so the web overlay / ColorFilter intensity
  /// tracks the Desync wall proximity. Cheap — a single double write/frame.
  final ValueNotifier<double> intensityNotifier = ValueNotifier(0);

  /// Previous frame captured as a [ui.Image] for the shader post-pass.
  /// One-frame lag is imperceptible at 60 fps.
  ui.Image? _prevFrameImage;

  /// Accumulated score for the run.
  final ValueNotifier<int> score = ValueNotifier(0);

  /// The perk most recently triggered by spending fragments (D-13). Set in
  /// `FragmentManager.spend` to a fresh [AugmentResult] each time so the HUD
  /// can show a transient "perk fired" callout via a `ListenableBuilder` —
  /// making the collect→spend→effect loop legible. Null until the first spend.
  final ValueNotifier<AugmentResult?> lastPerk = ValueNotifier(null);

  /// Run-started signal the HUD listens to so it can show the opening goal hint
  /// ("Outrun the Desync — grab ◈, spend on Augment to slow it"), which frames
  /// the collect→spend→slow loop for first-time players. Bumped on the first
  /// run-start (end of [onLoad]) and on every [restart]; the HUD replays its
  /// fade each time the value changes. Same lifecycle contract as [score] /
  /// [lastPerk]: NOT disposed in [onRemove] (web remove/re-add safety), disposed
  /// only in [disposeRunResources].
  final ValueNotifier<int> runStartTick = ValueNotifier(0);

  /// Whether the slow-wave perk is active (reduces effective Desync speed).
  bool _slowWaveActive = false;
  async.Timer? _slowWaveTimer;

  /// Fragment spawn timer accumulator.
  double _fragmentTimer = 0;

  /// Gun-powerup pickup spawn accumulator (seconds). One pickup roughly every
  /// [_gunPickupInterval]s, on a seeded track (race determinism preserved).
  double _gunPickupTimer = 0;
  static const double _gunPickupInterval = 11;

  late PlayerComponent _player;
  // Nullable (not late) so [_applyCameraFit] can guard it — Flame may call
  // onGameResize before onLoad assigns the wall.
  DesyncWall? _wall;
  late HazardSpawner _spawner;
  late World _gameWorld;
  late FragmentManager _fragmentManager;
  CameraComponent? _camera;

  /// True once [onLoad] has completed at least once. Guards
  /// [disposeRunResources] from touching the `late` [_fragmentManager] if the
  /// game is torn down before it ever finished loading.
  bool _loaded = false;

  /// True once [disposeRunResources] has run — makes disposal idempotent.
  bool _disposed = false;

  /// Full-cover sky gradient behind the parallax. Resized in [_applyCameraFit]
  /// to fill the camera's entire visible vertical extent so there is never a
  /// flat dark bar above the parallax on tall/wide windows (ISSUE 1).
  _SkyCover? _skyCover;

  /// Fixed world-band width in logical px. Lane positions (and any other world
  /// layout) MUST be fractions of THIS — never `size.x` (raw canvas pixels), or
  /// the player slides horizontally on resize and can drift into the Desync
  /// wall, which sits at a fixed world x.
  double get worldWidth => _viewportWidth;

  /// Fixed world-band height in logical px. The 3 vertical tracks
  /// ([PlayerComponent.trackCenters]) are fractions of THIS — never `size.y`
  /// (raw canvas px) — so they never drift on window resize.
  double get worldHeight => _viewportHeight;

  /// The world-y of the TOP of the currently visible area (may be negative —
  /// sky above the ground band — on landscape windows). Lets the player roam
  /// the full visible height, not just the fixed 360 band. Returns 0 before the
  /// canvas has a size. Derived from the fit-to-width camera zoom.
  double get visibleTopWorldY {
    if (size.x <= 0 || size.y <= 0) return 0;
    final zoom = cameraZoomFor(size.x, size.y);
    return _viewportHeight - size.y / zoom;
  }

  /// Public read-only access to the player (needed by [FragmentManager.spend]).
  PlayerComponent get player => _player;

  /// Public read-only access to [FragmentManager].
  FragmentManager get fragmentManager => _fragmentManager;

  /// Current world scroll speed — increases over time (D-02).
  double get currentScrollSpeed =>
      (initialScrollSpeed + scrollSpeedRampPerSecond * _elapsed)
          .clamp(initialScrollSpeed, _maxScrollSpeed);

  /// Net Desync advance rate (px/s, SIGNED — positive = closing on the player,
  /// negative = receding). Skill-based model (D-09 reworked):
  ///  - a gentle [initialDesyncSpeed] creep ramps over time
  ///    (via [desyncSpeedRampPerSecond]);
  ///  - after [_recoverDelaySeconds] of clean running the wall recedes
  ///    ([_recoverSpeed]) — you are outrunning the Desync;
  ///  - a stumble resets [_cleanTime] (see [onPlayerStumble]) so the creep
  ///    closes the gap again;
  ///  - slowWave softens any advance.
  /// The wall consumes this in [DesyncWall.update] and is clamped there so it
  /// never recovers past its start gap.
  double get currentDesyncSpeed {
    final creep = (initialDesyncSpeed + desyncSpeedRampPerSecond * _elapsed)
        .clamp(initialDesyncSpeed, _maxDesyncSpeed);
    return desyncNetRate(
      creep: creep,
      cleanTime: _cleanTime,
      slowWave: _slowWaveActive,
    );
  }

  /// Pure net-rate computation for [currentDesyncSpeed] — extracted so the
  /// skill-based model is unit-testable. [creep] is the already-ramped creep.
  @visibleForTesting
  static double desyncNetRate({
    required double creep,
    required double cleanTime,
    required bool slowWave,
  }) {
    // CHALLENGE c11-desyncnetrate (Creative): compute the SIGNED net Desync
    // advance rate. After `cleanTime` reaches the recover delay the wall
    // recedes; `slowWave` softens an advance but never flips a recede.
    // See CHALLENGES.md → c11-desyncnetrate.
    throw UnimplementedError('c11-desyncnetrate: implement desyncNetRate');
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _fragmentManager = FragmentManager(augmentCost: augmentCost, game: this);

    _gameWorld = World();
    // FIT-TO-WIDTH camera that FILLS the whole canvas (no letterbox bars).
    //
    // Default CameraComponent uses a MaxViewport that always covers the entire
    // canvas. We then zoom so exactly _viewportWidth (900) world units map to
    // the screen WIDTH — every team sees the same horizontal play area
    // (fairness). The HEIGHT simply fills the window; taller windows reveal
    // more sky upward (the dark sky [backgroundColor] + parallax fill it).
    //
    // The viewfinder anchor is bottomCenter and its position is the world's
    // bottom-centre (_viewportWidth/2, _viewportHeight), so the ground line
    // stays pinned to the screen bottom and lanes stay horizontally centred.
    final camera = CameraComponent(world: _gameWorld);
    camera.viewfinder.anchor = Anchor.bottomCenter;
    _camera = camera;
    await addAll([_gameWorld, camera]);

    // Full-cover sky gradient (priority -2 — behind the parallax). Anchored at
    // the ground line (y = _viewportHeight) and extends UPWARD to fill the
    // camera's full visible height, so the purple sky reaches the top of the
    // window with no flat dark gap (ISSUE 1). Sized in _applyCameraFit.
    final sky = _SkyCover()
      ..priority = -2
      ..width = _viewportWidth
      ..height = _viewportHeight;
    _skyCover = sky;
    await _gameWorld.add(sky);

    _applyCameraFit(size);

    // Parallax background — priority -1 so it renders behind game objects but
    // in front of the sky cover. FIXED-size world band (NOT fullscreen — see
    // ParallaxBackground) so it scales uniformly with every other world object
    // under the single camera zoom (no per-window resize — that decouples it
    // from the player/hazards). The band is TALLER than the _viewportHeight
    // gameplay band and bottom-anchored at the ground line, so its skyline
    // reaches up into the extra world height revealed on tall/portrait windows
    // instead of collapsing to a sliver of rooftops.
    await _gameWorld.add(
      ParallaxBackground(
        bandSize: Vector2(_viewportWidth, _parallaxBandHeight),
        groundLine: _viewportHeight,
      ),
    );

    // Ground bar.
    await _gameWorld.add(
      RectangleComponent(
        position: Vector2(0, _viewportHeight - 10),
        size: Vector2(_viewportWidth, 10),
        paint: Paint()..color = const Color(0xFF3A3A5C),
      ),
    );

    // Player — fixed x at 0.30 of the world; starts mid-height. Movement is
    // free vertical now; x never changes, so the player can never move into the
    // Desync wall or off-screen right. 84px box → centre offset 42.
    _player = PlayerComponent(
      position: Vector2(
        _viewportWidth * 0.30 - 42,
        _viewportHeight * 0.5 - 42,
      ),
    );
    await _gameWorld.add(_player);

    // Desync wall — starts off-screen left.
    final wall = DesyncWall(
      position: Vector2(_wallStartX, 0),
      size: Vector2(_wallWidth, _viewportHeight),
    );
    _wall = wall;
    await _gameWorld.add(wall);

    // Hazard spawner — receives the shared seeded RNG for race determinism
    // (D-31). Free-play passes an unseeded Random; race passes Random(seed).
    _spawner = HazardSpawner(
      hazards: studentHazards,
      minPeriod: hazardSpawnMinSeconds,
      maxPeriod: hazardSpawnMaxSeconds,
      viewportSize: Vector2(_viewportWidth, _viewportHeight),
      rng: _rng,
      scriptedSpawns: scriptedSpawns,
    );
    await _gameWorld.add(_spawner);

    // Start background music if audio is enabled (SCAF-06).
    if (audioEnabled) {
      await _startBgm();
    }

    // Load the desync glitch shader (no-op on web — D-18).
    await _shaderController.load();

    _loaded = true;

    // The run is now fully set up and playable — signal run-start so the HUD
    // shows the opening goal hint.
    runStartTick.value++;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _applyCameraFit(size);
  }

  /// Fits the camera so [_viewportWidth] world units span the canvas width
  /// (fairness: identical horizontal play area for every team) while the
  /// height fills the window. Pins the world bottom-centre to the screen
  /// bottom-centre so the ground stays at the bottom and lanes stay centred.
  ///
  /// Also resizes the [_skyCover] to the camera's full visible world height so
  /// the purple sky fills to the very top of the window (ISSUE 1).
  ///
  /// No-op until [_camera] is created in [onLoad] (Flame may call
  /// [onGameResize] before [onLoad] completes).

  /// Camera zoom for a canvas of [canvasWidth] × [canvasHeight] (px).
  ///
  /// Fits the FULL [_viewportWidth] world to the canvas width (D-01 framing
  /// follow-up). After the lanes were tightened to 0.30/0.50/0.70 (reachable
  /// span = 0.40·[_viewportWidth] = 360px), the old "zoom to a 0.7-width lane
  /// band" framing left the 3 lanes filling ~57% of the screen and scaled the
  /// player/hazards up — the game read as too big and a lane hop glided across
  /// more than half the surface. Fitting the whole world width drops the lanes
  /// to a ~40% central band (a crisp Subway-Surfers shift) and shrinks the
  /// sprites to a comfortable size.
  ///
  /// Height is NOT used to zoom in: the world's bottom edge (ground line) is
  /// pinned to the screen bottom and any extra vertical space fills with sky +
  /// parallax (see [_applyCameraFit]), so taller windows simply reveal more sky
  /// rather than enlarging the play area. We never zoom out past full width, so
  /// there is never empty space beyond the world on the sides.
  ///
  /// Pure + deterministic so the fit behaviour is unit-testable.
  /// [canvasHeight] is accepted for signature stability (callers pass the full
  /// canvas) but does not affect the zoom under the fit-to-full-width model.
  @visibleForTesting
  static double cameraZoomFor(double canvasWidth, double canvasHeight) {
    return canvasWidth / _viewportWidth;
  }

  void _applyCameraFit(Vector2 canvas) {
    final camera = _camera;
    if (camera == null || canvas.x <= 0 || canvas.y <= 0) return;

    final zoom = cameraZoomFor(canvas.x, canvas.y);

    camera.viewfinder
      ..zoom = zoom
      ..position = Vector2(_viewportWidth / 2, _viewportHeight);

    // Visible world height can exceed _viewportHeight on tall/wide windows.
    // Cover from the ground line (y = _viewportHeight) UP to fill it.
    final visibleWorldHeight = canvas.y / zoom;
    final sky = _skyCover;
    if (sky != null) {
      sky
        ..width = _viewportWidth
        ..height = visibleWorldHeight
        // Bottom edge at the ground line; extends upward (top can be negative).
        ..position = Vector2(0, _viewportHeight - visibleWorldHeight);
    }

    // The Desync "wave" must span the full visible height too — otherwise it
    // stops at y=0 and leaves a gap of sky above it on tall/wide windows.
    // Only touch height + y; the wall advances on x every frame (do not reset).
    final wall = _wall;
    if (wall != null) {
      wall.size.y = visibleWorldHeight;
      wall.position.y = _viewportHeight - visibleWorldHeight;
    }
  }

  /// Starts the background music.
  /// T-04-03: degrades gracefully if asset missing.
  Future<void> _startBgm() async {
    try {
      await FlameAudio.bgm.play('bgm_achrona.mp3', volume: 0.7);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('[AchronaGame] BGM load failed (asset missing?): $e');
      }
    }
  }

  /// Plays a one-shot SFX. T-04-03: logs and continues if asset missing.
  Future<void> _playSfx(String filename) async {
    if (!audioEnabled) return;
    try {
      await FlameAudio.play(filename);
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('[AchronaGame] SFX load failed ($filename): $e');
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    _cleanTime += dt;
    _updateScore(dt);
    _spawnFragments(dt);
    _spawnGunPickups(dt);
    _updateShaderIntensity();
  }

  /// Drives shader intensity = max(waveProximity, zoneIntensity) per D-16.
  ///
  /// waveProximity: how close the Desync wall is to the player (0 = far,
  /// 1 = touching). zoneIntensity is 0 in Phase 1 (no corruption zones yet;
  /// D-15 zones are Phase 2). Both combined via max so either source
  /// independently drives maximum effect.
  ///
  /// The computed intensity drives BOTH paths:
  /// - Native (SHDR-01): fed to [_shaderController] for the canvas-level
  ///   GLSL post-pass.
  /// - Web (SHDR-02): published on [intensityNotifier] so the app's
  ///   [ShaderController.wrapWithEffect] overlay / ColorFilter tracks it.
  ///
  /// RUNG-1 SAFETY (D-18): wrapped in try/catch so a shader-path error can
  /// never break the update loop — the game keeps running regardless.
  void _updateShaderIntensity() {
    try {
      // Compute wall-to-player gap as a 0→1 proximity value.
      final wallX = _wall!.position.x;
      final playerX = _player.position.x;
      // Gap shrinks from _viewportWidth (start) to 0 (death).
      final gap = (playerX - wallX).clamp(0.0, _viewportWidth);
      final waveProximity = 1.0 - (gap / _viewportWidth);

      // Phase 1: no corruption zones — zoneIntensity is always 0.
      // Phase 2: read from a corruption zone manager (D-15).
      const zoneIntensity = 0.0;

      final proximity = max(waveProximity, zoneIntensity);

      // SHDR-02 tuning: barely-there baseline (0.08) + a steep QUADRATIC ramp.
      // Stays a calm, subtle shimmer through most of the run, then climbs hard
      // to ~1.0 only as the Desync wall gets close — maximum contrast between
      // calm running and about-to-die.
      final intensity =
          (0.08 + 0.92 * pow(proximity, 2.0).toDouble()).clamp(0.0, 1.0);

      // Publish for the web overlay / ColorFilter (cheap single write).
      intensityNotifier.value = intensity;

      // Native canvas-level GLSL path (no-op internals on web).
      if (!kIsWeb) {
        _shaderController
          ..setIntensity(intensity)
          ..setTime(_elapsed);
      }
    } on Object catch (e) {
      // RUNG-1: shader intensity must never crash the game loop (D-18).
      if (kDebugMode) {
        debugPrint('[AchronaGame] shader intensity update failed: $e');
      }
    }
  }

  /// Renders the game and composites the desync glitch shader on top.
  ///
  /// On web (`kIsWeb == true`), the shader controller is a no-op so we just
  /// call `super.renderTree` and return (no `PictureRecorder` overhead).
  ///
  /// On native: (1) record the scene to a `ui.Picture`; (2) convert to a
  /// `ui.Image` synchronously via `Picture.toImageSync`; (3) paint the
  /// clean frame; (4) composite the shader pass on top.
  @override
  void renderTree(ui.Canvas canvas) {
    if (!_shaderController.isReady) {
      // Web path or shader not yet loaded — render normally with no shader.
      super.renderTree(canvas);
      return;
    }

    // --- Native path: capture scene, apply shader ----------------------
    final vpWidth = size.x.toInt();
    final vpHeight = size.y.toInt();

    if (vpWidth <= 0 || vpHeight <= 0) {
      super.renderTree(canvas);
      return;
    }

    // Record the full game scene into a Picture.
    final recorder = ui.PictureRecorder();
    final recordCanvas = ui.Canvas(recorder);
    super.renderTree(recordCanvas);
    final picture = recorder.endRecording();

    // Convert to image synchronously (Flutter 3.3+, Impeller-safe).
    final frameImage = picture.toImageSync(vpWidth, vpHeight);

    // 1. Paint the clean frame so the game is always visible.
    canvas.drawImage(frameImage, ui.Offset.zero, ui.Paint());

    // 2. Composite the shader overlay on top.
    _shaderController.applyToCanvas(
      canvas,
      ui.Size(size.x, size.y),
      frameImage,
    );

    // Release the previous frame's image after it has been used.
    _prevFrameImage?.dispose();
    _prevFrameImage = frameImage;
  }

  void _updateScore(double dt) {
    // Score = scrollSpeed * multiplier per second.
    // Multiplier 1.5× when pledged Purist AND never augmented (D-10).
    final multiplier =
        (pledgedPurist && !_fragmentManager.isAugmented.value) ? 1.5 : 1.0;
    score.value += (currentScrollSpeed * multiplier * dt).toInt();
  }

  void _spawnFragments(double dt) {
    // Halve interval when magnet perk is active (fragmentMagnet — D-09).
    final interval = _fragmentManager.isMagnetActive
        ? fragmentSpawnInterval * 0.5
        : fragmentSpawnInterval;
    _fragmentTimer += dt;
    if (_fragmentTimer >= interval) {
      _fragmentTimer = 0;
      _spawnFragment();
    }
  }

  void _spawnGunPickups(double dt) {
    _gunPickupTimer += dt;
    if (_gunPickupTimer < _gunPickupInterval) return;
    _gunPickupTimer = 0;
    final track = _rng.nextInt(3); // D-31: shared seeded source for race runs
    final trackCentres = PlayerComponent.trackCenters(_viewportHeight);
    const pickupSize = 52.0;
    // ignore: discarded_futures — onLoad has no async work; add is synchronous
    _gameWorld.add(
      GunPickupComponent(
        position: Vector2(
          _viewportWidth + pickupSize,
          trackCentres[track] - pickupSize / 2,
        ),
      ),
    );
  }

  void _spawnFragment() {
    final track = _rng.nextInt(3); // D-31: shared seeded source for race runs
    // Spawn on a track centre (y) off the right edge and let it scroll in, on
    // the SAME tracks the player can reach (PlayerComponent.trackCenters), so
    // every fragment is collectable.
    final trackCentres = PlayerComponent.trackCenters(_viewportHeight);
    const fragmentSize = 54.0;
    // Fragment.onLoad has no async work; add is effectively synchronous.
    // ignore: discarded_futures
    _gameWorld.add(
      FragmentComponent(
        position: Vector2(
          _viewportWidth + fragmentSize,
          trackCentres[track] - fragmentSize / 2,
        ),
      ),
    );
  }

  @override
  // Dark sky purple — fills any area above the parallax on tall windows so the
  // canvas blends seamlessly into the bg_far sky (no empty gap above the band).
  Color backgroundColor() => const Color(0xFF1A0E2D);

  /// Activate the slow-wave perk — halves [currentDesyncSpeed] for [duration].
  void activateSlowWave(Duration duration) {
    _slowWaveActive = true;
    _slowWaveTimer?.cancel();
    _slowWaveTimer = async.Timer(duration, () {
      _slowWaveActive = false;
    });
  }

  /// Called by [FragmentManager] when a fragment is collected.
  /// Plays the collect SFX.
  void onFragmentCollected() {
    // ignore: discarded_futures — T-04-03: fire-and-forget; errors logged in _playSfx
    _playSfx('sfx_collect.mp3');
  }

  /// Called by [PlayerComponent] when the Desync wall reaches the player.
  void onPlayerDeath() {
    // ignore: discarded_futures — T-04-03: stop is fire-and-forget
    FlameAudio.bgm.stop();
    // Build the run result and store it on the game so the overlay can read it.
    lastRunResult = RunResult(
      score: score.value,
      tag:
          _fragmentManager.isAugmented.value ? RunTag.augmented : RunTag.purist,
      pledgedPurist: pledgedPurist,
      timestamp: DateTime.now().toUtc(),
      fragments: _fragmentManager.totalFragmentsCollected,
    );
    overlays.add('gameOver');
    pauseEngine();
  }

  /// The result of the most recent completed run.
  ///
  /// Set in [onPlayerDeath]; read by the game-over overlay.
  RunResult? lastRunResult;

  /// Called by [PlayerComponent] on hazard collision — stumble, NOT death
  /// (D-03). The Desync wall closes 40 logical pixels toward the player.
  void onPlayerStumble() {
    // Reset the clean streak so the Desync stops receding and the creep closes
    // in again, and lurch it toward the player — mistakes are the real threat.
    _cleanTime = 0;
    _wall!.closeGap(_stumbleLurch);
    // ignore: discarded_futures — T-04-03: fire-and-forget; errors logged in _playSfx
    _playSfx('sfx_stumble.mp3');
  }

  /// Resets the run — called from the game-over overlay restart button.
  void restart() {
    overlays.remove('gameOver');
    _elapsed = 0;
    _cleanTime = 0;
    score.value = 0;
    _fragmentTimer = 0;
    _gunPickupTimer = 0;
    _slowWaveActive = false;
    _slowWaveTimer?.cancel();
    _fragmentManager.reset();
    _player.reset();
    _wall!.reset();
    _spawner.resetSpawner();
    // Remove any live fragments.
    for (final fragment
        in _gameWorld.children.whereType<FragmentComponent>().toList()) {
      fragment.removeFromParent();
    }
    if (audioEnabled) {
      // ignore: discarded_futures — T-04-03: fire-and-forget; errors logged in _startBgm
      _startBgm();
    }
    resumeEngine();

    // A fresh run has started — re-show the opening goal hint.
    runStartTick.value++;
  }

  @override
  void onRemove() {
    // TRANSIENT teardown only. On web, Flame's GameWidget removes and re-adds
    // the game during its initial canvas attach, so onRemove can fire BETWEEN
    // mounts — it must NOT dispose the run notifiers (score, intensityNotifier,
    // fragmentManager.*), or the re-mounted HUD would call addListener on a
    // disposed notifier ("ValueNotifier used after disposed" red screen).
    // Notifier/shader/image disposal is owned by the hosting page via
    // [disposeRunResources]. See 03-HUMAN-UAT gap G-2.
    if (audioEnabled) {
      // ignore: discarded_futures — T-04-03: stop is fire-and-forget
      FlameAudio.bgm.stop();
    }
    _slowWaveTimer?.cancel();
    super.onRemove();
  }

  /// Dispose run-lifetime resources: the run notifiers, the shader controller,
  /// and the cached previous frame.
  ///
  /// Called from the hosting page's `State.dispose()` — NOT from [onRemove],
  /// because Flame's web GameWidget transiently removes+re-adds the game and
  /// onRemove can fire mid-attach (see [onRemove]). Idempotent.
  void disposeRunResources() {
    if (_disposed) return;
    _disposed = true;
    if (_loaded) _fragmentManager.dispose();
    score.dispose();
    lastPerk.dispose();
    runStartTick.dispose();
    intensityNotifier.dispose();
    _shaderController.dispose();
    _prevFrameImage?.dispose();
    _prevFrameImage = null;
  }
}

/// A full-cover vertical sky gradient that fills the camera's entire visible
/// height behind the parallax (ISSUE 1).
///
/// Painted top → bottom: deep space purple at the top fading to a lighter
/// horizon purple near the ground, matching the bg_far sky tones so the
/// scrolling parallax silhouette layers blend seamlessly on top. Its size and
/// position are set by [AchronaGame._applyCameraFit] on every resize.
/// A single procedural star in normalized [0,1] sky-space (resolution
/// independent so the same field fills any window height).
class _Star {
  const _Star(this.nx, this.ny, this.radius, this.brightness, this.tint);
  final double nx;
  final double ny;
  final double radius;
  final double brightness;
  final double tint;
}

/// Full-cover sky behind the parallax. Resized in [AchronaGame._applyCameraFit]
/// to the camera's full visible world height, so on tall/wide windows it fills
/// ALL the revealed area above the city band — which is why it carries the
/// scene's atmosphere (gradient + starfield + neon horizon glow) instead of a
/// flat gradient that reads as empty bands on non-wide windows.
class _SkyCover extends PositionComponent {
  // Sky palette — deep top → mid → neon-tinted horizon (Desync purples).
  static const ui.Color _top = ui.Color(0xFF0B0820);
  static const ui.Color _mid = ui.Color(0xFF18103A);
  static const ui.Color _horizon = ui.Color(0xFF2E1A52);

  // Deterministic starfield (seeded → stable, golden-safe). Built once, in
  // normalized space, biased toward the top so the revealed upper sky fills.
  List<_Star>? _stars;

  List<_Star> _buildStars() {
    final rng = Random(0xACE12);
    return List<_Star>.generate(150, (_) {
      final nx = rng.nextDouble();
      // Spread stars across the full sky height with a mild top lean (pow > 1
      // biases toward 0/top for depth) so the whole revealed band is populated,
      // not just the very top.
      final ny = pow(rng.nextDouble(), 1.3).toDouble();
      final radius = 0.5 + rng.nextDouble() * 1.7;
      final brightness = 0.30 + rng.nextDouble() * 0.70;
      final tint = rng.nextDouble();
      return _Star(nx, ny, radius, brightness, tint);
    });
  }

  @override
  void render(ui.Canvas canvas) {
    final rect = ui.Rect.fromLTWH(0, 0, width, height);

    // 3-stop vertical gradient.
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [_top, _mid, _horizon],
          const [0.0, 0.62, 1.0],
        ),
    );

    // Starfield. Cyan / magenta accents on a white majority.
    final stars = _stars ??= _buildStars();
    final starPaint = ui.Paint();
    for (final s in stars) {
      final ui.Color base;
      if (s.tint > 0.88) {
        base = const ui.Color(0xFF7DF9FF); // cyan
      } else if (s.tint > 0.74) {
        base = const ui.Color(0xFFFF6EC7); // magenta
      } else {
        base = const ui.Color(0xFFFFFFFF); // white
      }
      starPaint.color = base.withValues(alpha: s.brightness);
      canvas.drawCircle(
        ui.Offset(s.nx * width, s.ny * height),
        s.radius,
        starPaint,
      );
    }

    // Neon horizon glow — soft purple/magenta band where the sky meets the
    // city, tying the backdrop to the Desync palette.
    final glowH = height * 0.24;
    final glowRect = ui.Rect.fromLTWH(0, height - glowH, width, glowH);
    canvas.drawRect(
      glowRect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          glowRect.topCenter,
          glowRect.bottomCenter,
          const [ui.Color(0x00401C66), ui.Color(0x55512080)],
        ),
    );
  }
}
