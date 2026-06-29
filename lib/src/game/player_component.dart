import 'dart:async' as async show Timer;

import 'package:achrona_engine/src/desync/desync_wall.dart';
import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:achrona_engine/src/hazards/hazard_component.dart';
import 'package:achrona_engine/src/weapons/projectile_component.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The player character component.
///
/// FREE vertical movement: the player's x is FIXED and it moves CONTINUOUSLY
/// up/down across the full visible height while Up/W or Down/S is held (held
/// state read each frame from [HardwareKeyboard], immune to OS key-repeat
/// choppiness). Dodging hazards = moving to a clear height.
///
/// Gun powerup: collecting a gun pickup arms the player for a few seconds;
/// while armed, Space fires a [ProjectileComponent] rightward that destroys the
/// first hazard it hits at the player's height.
///
/// On collision with [HazardComponent] calls [AchronaGame.onPlayerStumble] —
/// the player does NOT die (D-03). Death is only on [DesyncWall] collision.
class PlayerComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<AchronaGame>, KeyboardHandler {
  PlayerComponent({super.position}) : super(size: Vector2(84, 84));

  bool _isDead = false;

  /// Held-movement base y (clamped to the play band); [position].y tracks it.
  double _baseY = 0;

  // Lane-shield perk (D-09): absorbs one hazard hit.
  bool _shieldActive = false;
  async.Timer? _shieldTimer;

  // Gun powerup state.
  double _armedRemaining = 0; // seconds the gun stays armed
  double _fireCooldown = 0; // seconds until the next shot is allowed
  static const double _fireInterval = 0.22;

  /// Continuous vertical move speed (px/s).
  static const double _moveSpeed = 520;

  late SpriteAnimationComponent _runAnim;
  bool _spritesReady = false;

  /// Whether the player has been caught by the Desync wall.
  bool get isDead => _isDead;

  /// Whether the lane-shield perk is active.
  bool get isShieldActive => _shieldActive;

  /// Whether the gun powerup is currently armed.
  bool get isArmed => _armedRemaining > 0;

  /// Top bound (top-left y): the visible top of the screen, so the player can
  /// rise all the way up; on wide-short windows fall back to the band top (0).
  double get _minY {
    final visTop = game.visibleTopWorldY;
    return visTop < 0 ? visTop : 0;
  }

  /// Bottom bound (top-left y): the ground line minus the player box.
  double get _maxY => game.worldHeight - size.y;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _baseY = position.y;

    add(RectangleHitbox());

    try {
      final runImage = await game.images.load('hero_run.png');
      final runAnim = SpriteAnimation.fromFrameData(
        runImage,
        SpriteAnimationData.sequenced(
          amount: 6,
          stepTime: 0.08,
          textureSize: Vector2(64, 64),
        ),
      );
      _runAnim = SpriteAnimationComponent(animation: runAnim, size: size);
      await add(_runAnim);
      _spritesReady = true;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[PlayerComponent] sprite load failed: $e — using fallback');
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!(_spritesReady && _runAnim.isMounted)) _renderFallback(canvas);
    if (isArmed) _renderArmedAura(canvas);
  }

  /// A simple glowing hero silhouette sized to the player box.
  void _renderFallback(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    const body = Color(0xFF39E6FF);
    canvas
      ..drawCircle(
        Offset(w * 0.5, h * 0.5),
        w * 0.5,
        Paint()
          ..color = const Color(0x3339E6FF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawCircle(Offset(w * 0.5, h * 0.26), w * 0.16, Paint()..color = body)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.34, h * 0.42, w * 0.32, h * 0.5),
          const Radius.circular(6),
        ),
        Paint()..color = body,
      );
  }

  /// A neon ring around the player while the gun is armed (cue + readability).
  void _renderArmedAura(Canvas canvas) {
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x * 0.58,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFF6BFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Read the ACTUAL held keys each frame (no key-repeat choppiness).
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final up = keys.contains(LogicalKeyboardKey.arrowUp) ||
        keys.contains(LogicalKeyboardKey.keyW);
    final down = keys.contains(LogicalKeyboardKey.arrowDown) ||
        keys.contains(LogicalKeyboardKey.keyS);
    final dir = (up == down) ? 0 : (up ? -1 : 1);

    position.y = _baseY = stepY(
      currentY: _baseY,
      dir: dir,
      speed: _moveSpeed,
      dt: dt,
      minY: _minY,
      maxY: _maxY,
    );

    if (_armedRemaining > 0) _armedRemaining -= dt;
    if (_fireCooldown > 0) _fireCooldown -= dt;
  }

  /// CHALLENGE SEAM (c1-stepy): pure single-frame vertical step. You
  /// reimplement how a held direction advances the hero each frame
  /// and how it is kept inside the play band. Pure (no RNG/clock)
  /// so a fixed dir/dt sequence is deterministic.
  @visibleForTesting
  static double stepY({
    required double currentY,
    required int dir,
    required double speed,
    required double dt,
    required double minY,
    required double maxY,
  }) {
    // CHALLENGE c1-stepy (Base): reimplement the single-frame vertical step so
    // a held direction key moves the hero, and the hero never leaves the band.
    // This safe-default stub holds position so the app still launches (the hero
    // just cannot move up/down yet). See CHALLENGES.md -> c1-stepy.
    return currentY;
  }

  /// Reference hazard/fragment heights (top, middle, bottom) spread across the
  /// FULL play height — the SINGLE source of truth shared by the hazard spawner
  /// / track-jump and the fragment/pickup spawners. Pure (fractions of the
  /// FIXED [worldHeight], not raw canvas px) so it is resize-safe and testable.
  static List<double> trackCenters(double worldHeight) =>
      [worldHeight * 0.18, worldHeight * 0.5, worldHeight * 0.82];

  /// Arm the gun powerup for [seconds] (refreshes the timer on re-pickup).
  void armGun(double seconds) {
    if (seconds > _armedRemaining) _armedRemaining = seconds;
  }

  /// Fire a bolt rightward if armed and off cooldown.
  void fire() {
    if (_armedRemaining <= 0 || _fireCooldown > 0) return;
    final p = parent;
    if (p == null) return;
    _fireCooldown = _fireInterval;
    const boltH = 12.0;
    // ignore: discarded_futures — fire-and-forget component add
    p.add(
      ProjectileComponent(
        position: Vector2(
          position.x + size.x,
          position.y + size.y / 2 - boltH / 2,
        ),
      ),
    );
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      fire();
      return true;
    }
    // Consume the movement keys so the browser doesn't scroll the page; the
    // actual movement is read from HardwareKeyboard each frame in [update].
    return event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.keyW ||
        event.logicalKey == LogicalKeyboardKey.keyS;
  }

  /// Activate the lane-shield perk — absorbs the next hazard hit (D-09).
  void activateLaneShield(Duration duration) {
    _shieldActive = true;
    _shieldTimer?.cancel();
    _shieldTimer = async.Timer(duration, () {
      _shieldActive = false;
    });
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is DesyncWall && !_isDead) {
      _isDead = true;
      game.onPlayerDeath();
    } else if (other is HazardComponent) {
      if (_shieldActive) {
        _shieldActive = false;
        _shieldTimer?.cancel();
        other.onHitByPlayer();
      } else {
        game.onPlayerStumble();
        other.onHitByPlayer();
      }
    }
  }

  /// Reset the player to the alive state and the middle of the play band.
  void reset() {
    _isDead = false;
    _armedRemaining = 0;
    _fireCooldown = 0;
    _shieldActive = false;
    _shieldTimer?.cancel();
    _baseY = game.worldHeight * 0.5 - size.y / 2;
    position.y = _baseY;
    if (!_spritesReady) return;
    if (!_runAnim.isMounted) {
      // ignore: discarded_futures — Flame add() FutureOr completes synchronously in reset
      add(_runAnim);
    }
  }
}
