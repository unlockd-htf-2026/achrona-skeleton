import 'package:achrona_engine/src/hazards/hazard_model.dart';
import 'package:achrona_engine/src/hazards/scheduled_spawn.dart';

/// Thrown when a [TeamGameManifest] cannot be parsed from JSON because it
/// violates the v1 contract (unknown version, unknown enum value, malformed
/// hex, missing/oversized fields, too many spawns).
///
/// This is the typed failure the engine surfaces to a host BEFORE an
/// `AchronaGame` is ever constructed — a malformed manifest can therefore never
/// crash the engine at render time (T-04-01 / T-04-02). The host catches this
/// and degrades gracefully (skips the team's game / falls back to a default).
class ManifestFormatException implements Exception {
  /// Creates a manifest-format failure with a human-readable [message].
  const ManifestFormatException(this.message);

  /// Why the manifest was rejected.
  final String message;

  @override
  String toString() => 'ManifestFormatException: $message';
}

/// Cosmetic-only skin for a team game (palette + enemy tint hex colors).
///
/// Drives the sky/tint and enemy color. Cosmetic only — it cannot affect
/// gameplay balance (mirrors the AI-skin discipline in the Worker schema).
class ManifestSkin {
  /// Creates a validated skin. Both colors are six-hex-digit `#RRGGBB`.
  const ManifestSkin({required this.palette, required this.enemyTint});

  /// Sky/world palette as `#RRGGBB`.
  final String palette;

  /// Enemy tint as `#RRGGBB`.
  final String enemyTint;
}

/// Bounded tuning numbers for a team game.
///
/// Every field is CLAMPED into its documented range by [TeamGameManifest]'s
/// parser, so a manifest can never make a level unwinnable or trivially empty
/// (RESEARCH §Pattern 1 bounds table).
class ManifestTuning {
  /// Creates a tuning block. Callers should pass values already clamped via
  /// [TeamGameManifest.fromJson]; the bounds are documented per field.
  const ManifestTuning({
    required this.initialScrollSpeed,
    required this.initialDesyncSpeed,
    required this.desyncSpeedRampPerSecond,
    required this.scrollSpeedRampPerSecond,
    required this.fragmentSpawnInterval,
    required this.augmentCost,
  });

  /// Starting world scroll speed (px/s). Bounds: 80..300.
  final double initialScrollSpeed;

  /// Starting Desync wall advance speed (px/s). Bounds: 3..40.
  final double initialDesyncSpeed;

  /// Desync speed increase per second. Bounds: 0.1..2.0.
  final double desyncSpeedRampPerSecond;

  /// Scroll speed increase per second. Bounds: 1..15.
  final double scrollSpeedRampPerSecond;

  /// Seconds between fragment spawns. Bounds: 1.0..6.0.
  final double fragmentSpawnInterval;

  /// Fragments required for an augment perk. Bounds: 1..10.
  final int augmentCost;
}

/// A versioned, declarative team-authored game (ARCD-03 / D-42 contract).
///
/// Parsed from JSON via [TeamGameManifest.fromJson], which performs
/// defense-in-depth validation that MIRRORS the Worker Zod schema (built in
/// 04-02) — both validate independently. This Dart parser is the second line of
/// defense behind the Worker so a malformed manifest can never reach engine
/// construction (T-04-01 / T-04-02).
///
/// The manifest is DATA ONLY — no field holds or evaluates code (D-42). Unknown
/// JSON keys are ignored, never executed.
///
/// Lives in the engine package so the Arcade host and the Rung-4 reference game
/// share one source of truth (D-41 / PATTERNS barrel-export note).
class TeamGameManifest {
  /// Creates a manifest from already-validated parts. Prefer
  /// [TeamGameManifest.fromJson] for untrusted input.
  const TeamGameManifest({
    required this.version,
    required this.levelName,
    required this.skin,
    required this.tuning,
    required this.spawns,
  });

  /// Parses an untrusted JSON map into a validated [TeamGameManifest].
  ///
  /// Throws [ManifestFormatException] on any contract violation: unknown
  /// version, unknown/out-of-range enum, malformed hex, missing/oversized
  /// fields, empty or > [maxSpawns] spawns. Numeric tuning fields are CLAMPED
  /// (not rejected) into their documented bounds so a slightly-out-of-range
  /// tune is corrected rather than discarded.
  factory TeamGameManifest.fromJson(Map<String, dynamic> json) {
    // ---- version (known integer only — never coerce a string) -------------
    final version = json['version'];
    if (version is! int || version != supportedVersion) {
      throw ManifestFormatException(
        'Unsupported manifest version: $version '
        '(expected integer $supportedVersion).',
      );
    }

    // ---- levelName --------------------------------------------------------
    final levelName = json['levelName'];
    if (levelName is! String ||
        levelName.isEmpty ||
        levelName.length > maxLevelNameLength) {
      throw const ManifestFormatException(
        'levelName must be a 1..$maxLevelNameLength character string.',
      );
    }

    // ---- skin -------------------------------------------------------------
    final skinJson = _requireMap(json['skin'], 'skin');
    final palette = _requireHex(skinJson['palette'], 'skin.palette');
    final enemyTint = _requireHex(skinJson['enemyTint'], 'skin.enemyTint');

    // ---- tuning (clamped) -------------------------------------------------
    final tuningJson = _requireMap(json['tuning'], 'tuning');
    final tuning = ManifestTuning(
      initialScrollSpeed: _clampNum(
        tuningJson['initialScrollSpeed'],
        'tuning.initialScrollSpeed',
        80,
        300,
      ),
      initialDesyncSpeed: _clampNum(
        tuningJson['initialDesyncSpeed'],
        'tuning.initialDesyncSpeed',
        3,
        40,
      ),
      desyncSpeedRampPerSecond: _clampNum(
        tuningJson['desyncSpeedRampPerSecond'],
        'tuning.desyncSpeedRampPerSecond',
        0.1,
        2,
      ),
      scrollSpeedRampPerSecond: _clampNum(
        tuningJson['scrollSpeedRampPerSecond'],
        'tuning.scrollSpeedRampPerSecond',
        1,
        15,
      ),
      fragmentSpawnInterval: _clampNum(
        tuningJson['fragmentSpawnInterval'],
        'tuning.fragmentSpawnInterval',
        1,
        6,
      ),
      augmentCost: _clampNum(
        tuningJson['augmentCost'],
        'tuning.augmentCost',
        1,
        10,
      ).round(),
    );

    // ---- spawns -----------------------------------------------------------
    final rawSpawns = json['spawns'];
    if (rawSpawns is! List) {
      throw const ManifestFormatException('spawns must be a list.');
    }
    if (rawSpawns.isEmpty) {
      throw const ManifestFormatException('spawns must not be empty.');
    }
    if (rawSpawns.length > maxSpawns) {
      throw ManifestFormatException(
        'spawns.length ${rawSpawns.length} exceeds the cap of $maxSpawns.',
      );
    }

    final spawns = <ScheduledSpawn>[];
    for (var i = 0; i < rawSpawns.length; i++) {
      spawns.add(_parseSpawn(rawSpawns[i], i));
    }

    return TeamGameManifest(
      version: version,
      levelName: levelName,
      skin: ManifestSkin(palette: palette, enemyTint: enemyTint),
      tuning: tuning,
      spawns: spawns,
    );
  }

  /// Only the integer `1` is supported in this engine build.
  static const int supportedVersion = 1;

  /// Maximum number of scripted spawns (DoS guard — T-04-01).
  static const int maxSpawns = 200;

  /// Maximum length of [levelName].
  static const int maxLevelNameLength = 40;

  /// `#RRGGBB` hex pattern (six hex digits).
  static final RegExp _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

  /// Manifest schema version (always [supportedVersion] for a parsed instance).
  final int version;

  /// Human-readable level name (1..[maxLevelNameLength] chars).
  final String levelName;

  /// Cosmetic skin.
  final ManifestSkin skin;

  /// Bounded tuning numbers.
  final ManifestTuning tuning;

  /// Ordered scripted spawn sequence (1..[maxSpawns] entries).
  final List<ScheduledSpawn> spawns;

  static ScheduledSpawn _parseSpawn(Object? raw, int index) {
    final spawn = _requireMap(raw, 'spawns[$index]');

    final timeOffset = spawn['timeOffset'];
    if (timeOffset is! num || timeOffset < 0) {
      throw ManifestFormatException(
        'spawns[$index].timeOffset must be a non-negative number.',
      );
    }

    final lane = spawn['lane'];
    if (lane is! int || lane < 0 || lane > 2) {
      throw ManifestFormatException(
        'spawns[$index].lane must be an integer in 0..2.',
      );
    }

    final height = spawn['height'];
    if (height is! int || height < 1 || height > 2) {
      throw ManifestFormatException(
        'spawns[$index].height must be an integer in 1..2.',
      );
    }

    final type = _parseEnum(
      spawn['type'],
      HazardType.values,
      'spawns[$index].type',
    );
    final behavior = _parseEnum(
      spawn['behavior'],
      Behavior.values,
      'spawns[$index].behavior',
    );

    return ScheduledSpawn(
      timeOffset: timeOffset.toDouble(),
      lane: lane,
      type: type,
      height: height,
      behavior: behavior,
    );
  }

  /// Maps a string onto an exact enum value, REJECTING unknowns rather than
  /// letting `.values.byName` throw a raw [ArgumentError] (Pitfall 4).
  static T _parseEnum<T extends Enum>(
    Object? raw,
    List<T> values,
    String field,
  ) {
    if (raw is! String) {
      throw ManifestFormatException('$field must be a string.');
    }
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw ManifestFormatException(
      '$field has unknown value "$raw" '
      '(expected one of ${values.map((v) => v.name).join(', ')}).',
    );
  }

  static Map<String, dynamic> _requireMap(Object? raw, String field) {
    if (raw is! Map) {
      throw ManifestFormatException('$field must be an object.');
    }
    return raw.cast<String, dynamic>();
  }

  static String _requireHex(Object? raw, String field) {
    if (raw is! String || !_hexColor.hasMatch(raw)) {
      throw ManifestFormatException(
        '$field must match #RRGGBB (six hex digits).',
      );
    }
    return raw;
  }

  static double _clampNum(
    Object? raw,
    String field,
    double min,
    double max,
  ) {
    if (raw is! num) {
      throw ManifestFormatException('$field must be a number.');
    }
    final value = raw.toDouble();
    // num.clamp returns the receiver unchanged when it is NaN (NaN is neither
    // < min nor > max), so NaN would slip past the clamp and crash the engine
    // update loop (NaN.toInt() throws). Reject non-finite values up front so
    // the "every field is clamped into range" guarantee actually holds (CR-02).
    if (value.isNaN || value.isInfinite) {
      throw ManifestFormatException('$field must be a finite number.');
    }
    return value.clamp(min, max);
  }
}
