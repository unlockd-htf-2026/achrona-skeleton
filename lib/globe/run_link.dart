/// Achrona — a finished run, pushed into the shared world.
///
/// This closes the loop the event is built on: a team plays, the world they
/// share visibly heals. The globe (`main.dart`) already watches `nodes` over
/// Realtime, so nothing here talks to the globe — the Worker drains the shared
/// residual pool, Postgres notifies, and every globe on every screen flares.
///
/// This is the shipping wire: `POST /submit-score` on the Cloudflare Worker,
/// the same one `achrona_app`'s Daily Race uses. The Worker authenticates the
/// team key, validates the score against today's seed ceiling, keeps the
/// team's best on the leaderboard, reads the `heal_config` knobs and only then
/// calls `drain_residual_detail`. The run goes in as a `race` run because
/// that is the only mode the Worker lets touch the shared economy.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// One node this run cleansed, as the Worker reports it (D-06).
/// `drained` is the server-computed delta — never anything the client asked for.
typedef HealedNode = ({String challengeId, double drained});

/// What the shared world did with a run. [healed] can be empty for different
/// reasons, and saying the wrong one is worse than saying nothing: a run that
/// did not beat today's best ([improved] false — no energy, by design), a team
/// that has unlocked nothing ([unlocked] 0, the D-04 cold start), or a run
/// worth nothing. [rank] is null when the Worker could not compute it.
typedef RunHeal = ({
  int score,
  int? rank,
  bool improved,
  int unlocked,
  List<HealedNode> healed,
});

/// What a finished level-one run is worth.
///
/// Same shape as the Daily Race's own score (`achrona_app/lib/game/
/// race_score.dart`): ten a fragment, plus a bonus that fades to nothing at
/// par. Kills are level one's own addition — the 2D race has nothing to fight.
/// A run that ended in death keeps what it collected and loses the bonus: you
/// are paid for the level you finished, not the one you died in.
///
/// Not clamped to the race ceiling. Level one is not a seeded race, and the
/// bound that actually matters is the energy cap below.
int runScore({
  required int fragments,
  required int kills,
  required double seconds,
  required bool completed,
  double parSeconds = 180,
}) {
  final base = fragments * 10 + kills * 25;
  if (!completed || seconds >= parSeconds || parSeconds <= 0) return base;
  return base + (800 * (1 - seconds / parSeconds)).round();
}

/// The link from a finished run to the shared world.
class RunLink {
  RunLink(this._serverUrl, this._teamKey, this._teamId, {http.Client? client})
      : _client = client ?? http.Client();

  final String _serverUrl;
  final String _teamKey;
  final String _teamId;
  final http.Client _client;

  /// Built from the same `--dart-define`s `achrona_app` uses: `AI_SERVER_URL`,
  /// `TEAM_API_KEY`, `TEAM_ID`. Returns null when the server or key is
  /// missing, so an unconfigured build plays offline rather than throwing at
  /// the end of a good run.
  static RunLink? fromEnvironment() {
    const url = String.fromEnvironment('AI_SERVER_URL');
    const key = String.fromEnvironment('TEAM_API_KEY');
    // The reference team's canonical UUID (supabase/migrations team bridge);
    // its key there is `heal-unlockd-reference-key`.
    const team = String.fromEnvironment(
      'TEAM_ID',
      defaultValue: '00000000-0000-0000-0000-0000000000a1',
    );
    if (url.isEmpty || key.isEmpty) return null;
    return RunLink(url, key, team);
  }

  /// Submit this run as today's race run and report what the world did.
  /// Throws on a transport failure or a rejection, with the Worker's reason —
  /// the caller prints it on the end screen.
  Future<RunHeal> submit({
    required int fragments,
    required int kills,
    required double seconds,
    required bool completed,
  }) async {
    // CHALLENGE online-01: GET the daily seed, then POST this run to
    // /submit-score and read back what the world did. See CHALLENGES.md.
    // The fields below go unused until you do:
    // ignore_for_file: unused_field, unused_element
    throw UnimplementedError('online-01: submit is not wired yet');
  }

  static Map<String, dynamic> _json(http.Response r) {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw Exception('${r.statusCode} ${body['error'] ?? r.reasonPhrase}');
    }
    return body;
  }
}
