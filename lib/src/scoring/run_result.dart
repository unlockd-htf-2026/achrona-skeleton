/// Whether the run was completed as a purist or with augmented help (D-11).
///
/// This tag is the Phase 3 leaderboard split key (ONLN-03/04).
/// The score is transmitted to the Worker in Phase 3 — never directly to
/// Supabase from the client (T-03-02).
enum RunTag {
  /// Player never spent a fragment during the run.
  purist,

  /// Player spent at least one fragment during the run.
  augmented,
}

/// The final result of a completed run, ready for Phase 3 server submission.
class RunResult {
  const RunResult({
    required this.score,
    required this.tag,
    required this.pledgedPurist,
    required this.timestamp,
    required this.fragments,
  });

  /// Final score for this run.
  final int score;

  /// Whether augments were used during the run (D-11).
  final RunTag tag;

  /// Whether the player pledged Purist on the start screen (D-10).
  final bool pledgedPurist;

  /// UTC timestamp when the run ended.
  final DateTime timestamp;

  /// Number of fragments collected during the run.
  ///
  /// Required by the Worker ScoreSubmit Zod schema (Plan 04 — ONLN-02).
  final int fragments;

  @override
  String toString() => 'RunResult(score: $score, tag: $tag, '
      'pledgedPurist: $pledgedPurist, timestamp: $timestamp, '
      'fragments: $fragments)';
}
