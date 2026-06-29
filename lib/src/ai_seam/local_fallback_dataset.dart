import 'package:achrona_engine/src/fragments/augment_perk.dart';

// Source of truth: achrona-ai-server/src/fallbackDataset.json — keep in sync
// manually (Phase 3 may automate). These values mirror fallbackDataset.json's
// augmentedHint array so the client offline fallback and the Worker fallback
// never drift (D-28 two-layer fallback contract).

/// Local offline fallback dataset for `callAITool`.
///
/// Returned when the AI content server is unreachable (D-28 client-side layer).
/// Values mirror `achrona-ai-server/src/fallbackDataset.json` — update both
/// files together if the fallback content changes.
const List<AugmentResult> kLocalAugmentFallbacks = [
  // perk: laneShield, duration: 6 — matches fallbackDataset.json[0]
  AugmentResult(AugmentPerk.laneShield, Duration(seconds: 6)),
  // perk: slowWave, duration: 5 — matches fallbackDataset.json[1]
  AugmentResult(AugmentPerk.slowWave, Duration(seconds: 5)),
  // perk: fragmentMagnet, duration: 7 — matches fallbackDataset.json[2]
  AugmentResult(AugmentPerk.fragmentMagnet, Duration(seconds: 7)),
];
