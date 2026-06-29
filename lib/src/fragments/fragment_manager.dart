import 'dart:async' as async;

import 'package:achrona_engine/src/ai_seam/call_ai_tool.dart';
import 'package:achrona_engine/src/fragments/augment_perk.dart';
import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:flutter/foundation.dart';

/// Manages the fragment economy for a single run.
///
/// Tracks how many fragments the player has collected. When [spend] is called
/// it invokes [callAITool] — the single Phase 2 swap point (D-13) — and
/// applies the returned [AugmentResult] via [applyPerk].
///
/// Exposes [fragmentCount] and [isAugmented] as `ValueNotifier`s so the HUD
/// can rebuild with `ListenableBuilder` without calling setState on the full
/// widget tree.
class FragmentManager {
  FragmentManager({required this.augmentCost, required this.game});

  /// Number of fragments required to trigger an augment.
  final int augmentCost;

  /// Reference to the game; needed to apply perk effects.
  final AchronaGame game;

  bool _magnetActive = false;
  async.Timer? _magnetTimer;

  /// Whether the fragment-magnet perk is currently active.
  bool get isMagnetActive => _magnetActive;

  /// Live fragment count for the HUD.
  final ValueNotifier<int> fragmentCount = ValueNotifier(0);

  /// Whether the player has spent any fragment this run (D-10 auto-flag).
  final ValueNotifier<bool> isAugmented = ValueNotifier(false);

  /// Total fragments collected during this run (gross, not net).
  ///
  /// Used in `RunResult.fragments` for the Phase 3 Worker ScoreSubmit payload.
  /// Unlike [fragmentCount] this counter is never decremented on spend.
  int totalFragmentsCollected = 0;

  /// Called when the player passes through a fragment collectible.
  void collect() {
    fragmentCount.value += 1;
    totalFragmentsCollected += 1;
    game.onFragmentCollected();
  }

  /// Attempt to spend [augmentCost] fragments to trigger a perk.
  ///
  /// Returns `false` if the player has insufficient fragments.
  /// On success: decrements count, flags run as augmented, calls
  /// [callAITool] (the Phase 2 seam), and applies the perk.
  Future<bool> spend(int cost) async {
    if (fragmentCount.value < cost) return false;
    fragmentCount.value -= cost;
    isAugmented.value = true;

    // D-13: this is the single call site for `callAITool`.
    final result = await callAITool(
      '/augmented-hint',
      {'cost': cost, 'y': game.player.position.y.round()},
    );
    applyPerk(result, game);
    // Surface which perk fired so the HUD can show a callout (the effect is
    // otherwise invisible — e.g. slowWave just halves a speed). A fresh
    // AugmentResult each spend guarantees the notifier fires even on a repeat.
    game.lastPerk.value = result;
    return true;
  }

  /// Activate the fragment-magnet perk — doubles effective spawn rate by
  /// halving the spawn interval for [duration], then self-reverts.
  void activateMagnet(Duration duration) {
    _magnetActive = true;
    _magnetTimer?.cancel();
    _magnetTimer = async.Timer(duration, () {
      _magnetActive = false;
    });
  }

  /// Reset state for a new run.
  void reset() {
    fragmentCount.value = 0;
    isAugmented.value = false;
    _magnetActive = false;
    _magnetTimer?.cancel();
    totalFragmentsCollected = 0;
  }

  void dispose() {
    fragmentCount.dispose();
    isAugmented.dispose();
    _magnetTimer?.cancel();
  }
}
