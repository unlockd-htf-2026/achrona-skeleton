import 'dart:typed_data';

import 'tile_grid.dart';

/// Movement tuning, ported from Metroid: Zero Mission (`include/constants/samus.h`
/// and the integration in `src/samus.c` ~L6757).
///
/// Internally we keep velocity in **raw GBA units** (matching the decomp exactly)
/// and convert to pixels only for displacement. Raw → px/frame = raw / 32
/// (raw/8 = sub-px/frame, then /4 = px/frame; 4 sub-px = 1 px). ~60 fps.
///
/// MZM detail that defines the feel: `yVelocity` is an **up-positive accumulator**
/// that gravity decrements every frame, but the *displacement* is clamped to
/// [-fallCap, +riseCap]. So High Jump rises no faster — its larger accumulator
/// just stays positive for more frames, giving a taller arc.
class PlatformerTuning {
  const PlatformerTuning();

  // --- Horizontal (raw; samus.h SAMUS_X_*) ---
  final double xAccel = 8; // SAMUS_X_ACCELERATION
  final double runSpeedCapRaw = 96; // SAMUS_X_VELOCITY_CAP (3.0 px/frame)
  final double airSpeedCapRaw = 64; // SAMUS_X_MID_AIR_VELOCITY_CAP (2.0 px/frame)

  // --- Vertical (raw; samus.h SAMUS_Y_*) ---
  final double yAccel = 10; // SAMUS_Y_ACCELERATION (gravity, per frame)
  final double riseDispCapRaw = 192; // SAMUS_Y_POSITIVE_VELOCITY_CAP (6.0 px/f up)
  final double fallDispCapRaw = 128; // SAMUS_Y_NEGATIVE_VELOCITY_CAP (4.0 px/f down)
  final double accumulatorFloorRaw = -231; // gravity stops decrementing below this

  // --- Jump impulses (raw; samus.h SAMUS_*_JUMP_VELOCITY) ---
  final double jumpImpulseRaw = 192; // SAMUS_LOW_JUMP_VELOCITY (apex ≈ 60px ≈ 3.8 tiles)
  final double highJumpImpulseRaw = 232; // SAMUS_HIGH_JUMP_VELOCITY (taller arc)

  /// MZM jump is a FIXED arc (no release cut). Set < 1.0 for a modern variable
  /// jump: the up-accumulator is multiplied by this when jump is released while
  /// still rising. 1.0 = authentic Metroid.
  final double jumpReleaseCut = 1.0;

  /// Frames of "landing" pose after touching ground (cosmetic only).
  final int landingFrames = 4;

  // --- Hurt / knockback (samus.c ~L2124 + L2153) ---
  /// Up-velocity on hit while grounded: QUARTER_BLOCK − PIXEL/2 → 3.5 px/f up.
  final double hurtUpRaw = 112;

  /// Up-velocity on hit while airborne: EIGHTH_BLOCK − 1 → 1.75 px/f up.
  final double hurtUpMidairRaw = 56;

  /// Horizontal knockback away from the hazard (run-cap magnitude).
  final double knockbackXRaw = 96;

  /// Invincibility frames after a hit (MZM: 48 = 0.8s at 60fps).
  final int invincibilityFrames = 48;

  /// Frames of control-locked knockback before input resumes.
  final int knockbackControlFrames = 16;

  /// Jump-input buffer: a jump requested up to this many frames before landing
  /// still fires on landing (~100ms). Prevents dropped/early jump presses.
  final int jumpBufferFrames = 6;

  /// Coyote time: a jump still works for this many frames after walking off a
  /// ledge (~100ms). Makes jumping feel forgiving.
  final int coyoteFrames = 6;

  // --- Dash (unlockable ability; not stock MZM, but follows the same suit-flag
  // model as High Jump) ---
  /// Horizontal dash speed (raw). 160 = 5.0 px/frame — clearly past the run cap.
  final double dashSpeedRaw = 160;

  /// Dash duration in frames (~0.2s burst).
  final int dashFrames = 12;

  /// Frames after a dash ends before another can fire (prevents spam-flight).
  final int dashCooldownFrames = 26;

  /// Crouch collision height (px). Standing is [PlayerPhysics.height] (24 =
  /// 1.5 tiles); crouched fits under a 1-tile (16px) ceiling to slip through
  /// low passages. The player auto-stands when there's headroom again.
  final double crouchHeight = 13;

  /// raw GBA velocity → pixels per frame.
  static double rawToPx(double raw) => raw / 32;
}

/// Player animation/logic state. Subset of MZM's SPOSE_* relevant to a runner.
enum PlayerPose { standing, running, skidding, jumping, midair, landing, crouching, hurt }

/// Per-frame input intent. [jumpPressed] is a one-shot request (it fills the
/// jump buffer); for responsive input prefer calling [PlayerPhysics.requestJump]
/// directly off the key-down event so a press is never dropped between frames.
class PlayerIntent {
  const PlayerIntent({
    this.moveX = 0,
    this.jumpPressed = false,
    this.jumpHeld = false,
    this.crouch = false,
  });

  /// -1 left, 0 none, 1 right.
  final int moveX;
  final bool jumpPressed;
  final bool jumpHeld;
  final bool crouch;

  PlayerIntent consumePressed() => PlayerIntent(
        moveX: moveX,
        jumpPressed: false,
        jumpHeld: jumpHeld,
        crouch: crouch,
      );
}

/// Pure-Dart, deterministic platformer body. No Flame import → runs identically
/// on native and web and is unit-testable without a game loop.
///
/// Coordinates: (x, y) is the AABB top-left in pixels, y-down. Call [step] once
/// per fixed 60Hz frame.
class PlayerPhysics {
  PlayerPhysics({
    required this.x,
    required this.y,
    this.width = 12,
    this.height = 24,
    this.tuning = const PlatformerTuning(),
    this.hasHighJump = false,
    this.hasDoubleJump = false,
    this.hasDash = false,
    this.maxHp = 3,
  }) : hp = maxHp;

  /// Max and current hit points. [hp] reaching 0 sets [isDead].
  final int maxHp;
  int hp;

  bool get isDead => hp <= 0;

  double x;
  double y;
  final double width;
  final double height;
  final PlatformerTuning tuning;

  /// Toggles which jump impulse is used (the MZM "High Jump" item).
  bool hasHighJump;

  /// Unlockable suit flags. [hasDoubleJump] grants one mid-air jump; [hasDash]
  /// grants the horizontal dash ([requestDash]). Set true when collected.
  bool hasDoubleJump;
  bool hasDash;

  /// Raw GBA velocity accumulators. X is signed screen-space (right +). Y is
  /// **up-positive** like MZM (gravity decrements it).
  double _vxRaw = 0;
  double _vyRaw = 0;

  bool onGround = false;

  /// Facing for sprite mirroring; updated whenever horizontal input is applied.
  bool facingRight = true;

  PlayerPose pose = PlayerPose.standing;
  int _landingTimer = 0;

  /// Remaining invincibility frames after a hit (0 = vulnerable).
  int invincibilityFrames = 0;
  int _knockbackFrames = 0;
  int _jumpBufferFrames = 0;
  int _coyoteFrames = 0;
  int _airJumps = 0; // mid-air jumps used since last grounded (double-jump)
  int _dashFrames = 0; // remaining dash-burst frames
  int _dashCooldown = 0; // frames until dash can fire again
  int _dashBuffer = 0; // pending dash request (buffered like jump)
  bool _crouching = false; // collision box is shortened to slip under ceilings

  /// True while crouched (collision height reduced) — for sprite/fx.
  bool get isCrouching => _crouching;

  /// Collision height this frame (shorter while crouching).
  double get _effHeight => _crouching ? tuning.crouchHeight : height;

  /// Collision-box top this frame. Feet stay at `y + height`; crouching lowers
  /// the head (raises the top), so a low ceiling no longer blocks the body.
  double get _effTop => y + height - _effHeight;

  /// Buffer a jump (call off the key-down event). Fires on the next step where
  /// the player is grounded, within coyote time, or — with [hasDoubleJump] — has
  /// a mid-air jump left.
  void requestJump() => _jumpBufferFrames = tuning.jumpBufferFrames;

  /// Buffer a dash (call off the key-down event). Fires next step if [hasDash]
  /// and not on cooldown. Dashes horizontally in the current facing direction.
  void requestDash() => _dashBuffer = tuning.jumpBufferFrames;

  /// True during the dash burst (for sprite/fx).
  bool get isDashing => _dashFrames > 0;

  /// Full mutable-state snapshot for deterministic re-simulation (level
  /// solvers, AI search, tests). Config (abilities, tuning, maxHp) is NOT
  /// included — it doesn't change during a sim. Pair with [restore].
  Float64List snapshot() => Float64List.fromList([
        x, y, _vxRaw, _vyRaw,
        onGround ? 1 : 0, facingRight ? 1 : 0, hp.toDouble(),
        _landingTimer.toDouble(), invincibilityFrames.toDouble(),
        _knockbackFrames.toDouble(), _jumpBufferFrames.toDouble(),
        _coyoteFrames.toDouble(), _airJumps.toDouble(),
        _dashFrames.toDouble(), _dashCooldown.toDouble(), _dashBuffer.toDouble(),
      ]);

  /// Restore a [snapshot]. The grid/abilities are unchanged.
  void restore(Float64List s) {
    x = s[0];
    y = s[1];
    _vxRaw = s[2];
    _vyRaw = s[3];
    onGround = s[4] != 0;
    facingRight = s[5] != 0;
    hp = s[6].toInt();
    _landingTimer = s[7].toInt();
    invincibilityFrames = s[8].toInt();
    _knockbackFrames = s[9].toInt();
    _jumpBufferFrames = s[10].toInt();
    _coyoteFrames = s[11].toInt();
    _airJumps = s[12].toInt();
    _dashFrames = s[13].toInt();
    _dashCooldown = s[14].toInt();
    _dashBuffer = s[15].toInt();
  }

  bool get isInvincible => invincibilityFrames > 0;

  /// Take a hit from a hazard. [fromRight] = the hazard is to the player's right
  /// (so knockback pushes left). No-op while invincible. Mirrors MZM: up-launch
  /// + horizontal knockback + i-frames, control locked briefly.
  void hit({required bool fromRight, int damage = 1}) {
    if (invincibilityFrames > 0 || isDead) return;
    hp = (hp - damage).clamp(0, maxHp);
    invincibilityFrames = tuning.invincibilityFrames;
    _knockbackFrames = tuning.knockbackControlFrames;
    _vyRaw = onGround ? tuning.hurtUpRaw : tuning.hurtUpMidairRaw;
    _vxRaw = (fromRight ? -1 : 1) * tuning.knockbackXRaw;
    onGround = false;
    _dashFrames = 0; // a hit cancels an in-progress dash
  }

  /// Move to a position with zeroed velocity, leaving hp/lives untouched (e.g.
  /// arriving through a door).
  void placeAt(double atX, double atY) {
    x = atX;
    y = atY;
    _vxRaw = 0;
    _vyRaw = 0;
    _knockbackFrames = 0;
    onGround = false;
    pose = PlayerPose.standing;
  }

  /// Reset to full health at a position, with brief mercy invincibility.
  void respawn(double atX, double atY) {
    placeAt(atX, atY);
    hp = maxHp;
    invincibilityFrames = tuning.invincibilityFrames;
  }

  /// Current horizontal velocity in px/frame (right positive).
  double get vx => PlatformerTuning.rawToPx(_vxRaw);

  /// Current vertical velocity in px/frame, **screen-space (down positive)**.
  double get vy => -PlatformerTuning.rawToPx(_vyRaw);

  /// Advance one fixed frame against [grid]. Mirrors MZM's order: set impulse,
  /// apply displacement (clamped), THEN decrement the accumulator by gravity.
  void step(PlayerIntent intent, TileGrid grid) {
    if (intent.jumpPressed) _jumpBufferFrames = tuning.jumpBufferFrames;
    _updateCrouch(intent, grid);
    _triggerDash();
    _horizontal(intent);
    _applyJump(intent);

    _moveX(vx, grid);
    final wasGrounded = onGround;
    _moveY(grid);
    if (onGround && !wasGrounded) _landingTimer = tuning.landingFrames;
    if (_landingTimer > 0) _landingTimer--;

    _applyGravity();
    // Timers: coyote + air-jumps refill while grounded, buffers tick otherwise.
    if (onGround) {
      _coyoteFrames = tuning.coyoteFrames;
      _airJumps = 0;
    } else if (_coyoteFrames > 0) {
      _coyoteFrames--;
    }
    if (_jumpBufferFrames > 0) _jumpBufferFrames--;
    if (_dashBuffer > 0) _dashBuffer--;
    if (_dashFrames > 0) _dashFrames--;
    if (_dashCooldown > 0) _dashCooldown--;
    if (invincibilityFrames > 0) invincibilityFrames--;
    if (_knockbackFrames > 0) _knockbackFrames--;
    _setPose(intent);
  }

  /// Start a dash if one is buffered, unlocked, idle and off cooldown. The dash
  /// zeroes vertical velocity for a clean horizontal burst (see [_horizontal],
  /// [_applyGravity], which both defer to [_dashFrames]).
  void _triggerDash() {
    if (_dashBuffer > 0 &&
        hasDash &&
        _dashFrames == 0 &&
        _dashCooldown == 0 &&
        _knockbackFrames == 0) {
      _dashFrames = tuning.dashFrames;
      _dashCooldown = tuning.dashFrames + tuning.dashCooldownFrames;
      _vyRaw = 0;
      _dashBuffer = 0;
    }
  }

  void _horizontal(PlayerIntent intent) {
    if (_dashFrames > 0) {
      // Dash overrides normal control: lock to dash speed in the facing dir.
      _vxRaw = (facingRight ? 1 : -1) * tuning.dashSpeedRaw;
      return;
    }
    if (_knockbackFrames > 0) return; // knockback momentum carries; no control
    final runCap = tuning.runSpeedCapRaw;
    final airCap = tuning.airSpeedCapRaw;
    if (intent.moveX != 0) {
      facingRight = intent.moveX > 0;
      final dir = intent.moveX.toDouble();
      if (onGround) {
        _vxRaw = (_vxRaw + dir * tuning.xAccel).clamp(-runCap, runCap);
      } else {
        // Air control: accel is limited to the air cap, BUT momentum carried in
        // from a running jump is preserved — don't yank a fast jump down to the
        // air cap (that's what made running jumps fall short). Cap = the larger
        // of the air cap and the speed already held in the held direction.
        final speed = _vxRaw.abs();
        final sameDir = dir > 0 ? _vxRaw > 0 : _vxRaw < 0;
        final cap = (sameDir && speed > airCap) ? speed : airCap;
        _vxRaw = (_vxRaw + dir * tuning.xAccel).clamp(-cap, cap);
      }
    } else if (onGround) {
      // Decelerate to rest on the ground; keep momentum in the air (Metroid feel).
      if (_vxRaw > 0) {
        _vxRaw = (_vxRaw - tuning.xAccel).clamp(0, runCap);
      } else if (_vxRaw < 0) {
        _vxRaw = (_vxRaw + tuning.xAccel).clamp(-runCap, 0);
      }
    }
  }

  void _applyJump(PlayerIntent intent) {
    if (_knockbackFrames > 0 || _dashFrames > 0) return; // locked mid-dash/hit
    final impulse = hasHighJump ? tuning.highJumpImpulseRaw : tuning.jumpImpulseRaw;
    if (_jumpBufferFrames > 0) {
      if (onGround || _coyoteFrames > 0) {
        _vyRaw = impulse;
        onGround = false;
        _jumpBufferFrames = 0;
        _coyoteFrames = 0;
        _airJumps = 0;
      } else if (hasDoubleJump && _airJumps < 1) {
        // Mid-air jump: same impulse, consumed once per airborne stretch.
        _vyRaw = impulse;
        _jumpBufferFrames = 0;
        _airJumps++;
      }
    }
    // Optional variable-jump cut (off by default → authentic fixed arc).
    if (!intent.jumpHeld && _vyRaw > 0 && tuning.jumpReleaseCut < 1.0) {
      _vyRaw *= tuning.jumpReleaseCut;
    }
  }

  void _applyGravity() {
    // MZM only integrates Y velocity for mid-air poses; grounded poses skip it.
    // A dash is a flat horizontal burst — no gravity for its duration.
    if (onGround || _dashFrames > 0) return;
    // Decrements the up-positive accumulator, with a floor (MZM samus.c ~L6770).
    if (_vyRaw >= tuning.accumulatorFloorRaw) {
      _vyRaw -= tuning.yAccel;
    }
  }

  /// Displacement applied per frame is the accumulator clamped to the disp caps,
  /// converted to px. Returns down-positive px for this frame's vertical move.
  double get _vyDisplacementPx {
    final clamped =
        _vyRaw.clamp(-tuning.fallDispCapRaw, tuning.riseDispCapRaw);
    return -PlatformerTuning.rawToPx(clamped); // up-positive → down-positive
  }

  /// Crouch state: shrink the box on request (grounded), and STAY crouched
  /// while a ceiling sits in the head space, so you can't pop up into solid.
  void _updateCrouch(PlayerIntent intent, TileGrid grid) {
    if (intent.crouch && onGround && _knockbackFrames == 0) {
      _crouching = true;
    } else if (_crouching && !_ceilingBlocksStanding(grid)) {
      _crouching = false;
    }
  }

  /// True if standing up (restoring full height) would push the head into a
  /// solid tile — i.e. there's a low ceiling above the crouched body.
  bool _ceilingBlocksStanding(TileGrid grid) {
    final ts = grid.tileSize;
    final crouchTop = y + height - tuning.crouchHeight;
    final c0 = (x / ts).floor();
    final c1 = ((x + width - 1e-4) / ts).floor();
    final r0 = (y / ts).floor();
    final r1 = ((crouchTop - 1e-4) / ts).floor();
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (grid.solidityAt(c, r) == TileSolidity.solid) return true;
      }
    }
    return false;
  }

  // --- Axis-separated AABB vs tile grid -------------------------------------

  void _moveX(double dx, TileGrid grid) {
    if (dx == 0) return;
    final nx = x + dx;
    final ts = grid.tileSize;
    final rowStart = (_effTop / ts).floor();
    final rowEnd = ((y + height - 1e-4) / ts).floor();

    if (dx > 0) {
      final col = ((nx + width - 1e-4) / ts).floor();
      if (_solidColumn(grid, col, rowStart, rowEnd)) {
        x = (col * ts - width).toDouble();
        _vxRaw = 0;
        return;
      }
    } else {
      final col = (nx / ts).floor();
      if (_solidColumn(grid, col, rowStart, rowEnd)) {
        x = ((col + 1) * ts).toDouble();
        _vxRaw = 0;
        return;
      }
    }
    x = nx;
  }

  void _moveY(TileGrid grid) {
    final dy = _vyDisplacementPx;
    final ts = grid.tileSize;
    final ny = y + dy;
    final colStart = (x / ts).floor();
    final colEnd = ((x + width - 1e-4) / ts).floor();

    if (dy >= 0) {
      // Falling/resting: probe the tile at the exact bottom edge so a player
      // flush on a floor stays grounded. Land on solids; on one-way tops only
      // when crossing onto them.
      final feet = ny + height;
      final row = (feet / ts).floor();
      final prevFeet = y + height;
      for (var c = colStart; c <= colEnd; c++) {
        final s = grid.solidityAt(c, row);
        final isFloor = s == TileSolidity.solid ||
            (s == TileSolidity.oneWayPlatform && prevFeet <= row * ts);
        if (isFloor) {
          y = (row * ts - height).toDouble();
          _vyRaw = 0;
          onGround = true;
          return;
        }
      }
      y = ny;
      onGround = false;
    } else {
      // Rising: bonk solid ceilings (one-way never blocks upward).
      final row = (ny / ts).floor();
      for (var c = colStart; c <= colEnd; c++) {
        if (grid.solidityAt(c, row) == TileSolidity.solid) {
          y = ((row + 1) * ts).toDouble();
          _vyRaw = 0; // hit head → kill upward accumulator
          return;
        }
      }
      y = ny;
      onGround = false;
    }
  }

  bool _solidColumn(TileGrid grid, int col, int rowStart, int rowEnd) {
    for (var r = rowStart; r <= rowEnd; r++) {
      // One-way platforms never block horizontal movement.
      if (grid.solidityAt(col, r) == TileSolidity.solid) return true;
    }
    return false;
  }

  void _setPose(PlayerIntent intent) {
    if (_knockbackFrames > 0) {
      pose = PlayerPose.hurt;
      return;
    }
    if (!onGround) {
      pose = _vyRaw > 0 ? PlayerPose.jumping : PlayerPose.midair;
      return;
    }
    if (_landingTimer > 0) {
      pose = PlayerPose.landing;
      return;
    }
    if (_crouching) {
      pose = PlayerPose.crouching;
      return;
    }
    final moving = _vxRaw.abs() > 1;
    final reversing =
        intent.moveX != 0 && _vxRaw != 0 && intent.moveX.sign != _vxRaw.sign;
    if (reversing) {
      pose = PlayerPose.skidding;
    } else if (moving) {
      pose = PlayerPose.running;
    } else {
      pose = PlayerPose.standing;
    }
  }
}
