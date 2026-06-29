import 'package:achrona_engine/src/game/achrona_game.dart';

/// The three local perks a player can trigger by spending fragments (D-09).
///
/// Phase 2 will keep this enum and `AugmentResult` unchanged; only the
/// `callAITool` body swaps to call the AI server.
enum AugmentPerk {
  /// Temporarily halves the Desync wall's advance speed.
  slowWave,

  /// Grants the player one free hazard hit (shield absorbs then deactivates).
  laneShield,

  /// Doubles the fragment spawn rate for the perk duration.
  fragmentMagnet,
}

/// The result returned by `callAITool` describing which perk to apply and
/// how long it should last.
class AugmentResult {
  const AugmentResult(this.perk, this.duration);

  final AugmentPerk perk;
  final Duration duration;
}

/// Apply [result] to [game], reverting the effect automatically after
/// `result.duration` using a Dart Timer (no Flame effect needed).
void applyPerk(AugmentResult result, AchronaGame game) {
  switch (result.perk) {
    case AugmentPerk.slowWave:
      game.activateSlowWave(result.duration);

    case AugmentPerk.laneShield:
      game.player.activateLaneShield(result.duration);

    case AugmentPerk.fragmentMagnet:
      game.fragmentManager.activateMagnet(result.duration);
  }
}
