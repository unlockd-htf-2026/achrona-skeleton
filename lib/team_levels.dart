/// The teams' levels: every team designs one (base-01, on its concept card),
/// every game can play all of them, and each finished run heals Achrona.
///
/// A team publishes its level to the Worker (`PUT /team-game/{id}`, manifest
/// v2 = [TeamLevel.toJson] + version); the sealed grader vouches for it and
/// deals it a slot; every game fetches the verified ones (`GET /team-game`).
/// `assets/team_levels/` is the offline fallback.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'concepts.dart';
import 'kit.dart';
import 'session.dart';

/// Where the Worker is and who we are: the same `--dart-define`s as RunLink.
const _server = String.fromEnvironment('AI_SERVER_URL');
const _teamKey = String.fromEnvironment('TEAM_API_KEY');
// Reads go straight to Supabase (legacy anon JWT) when configured.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Team-level slots there are: three per continent, four continents.
const int kTeamSlots = 12;

/// One team's published level.
class TeamLevel {
  TeamLevel(this.team, this.card, this.spec, {this.teamId, this.slot = 0});

  /// Throws on a malformed level or an unknown concept card.
  factory TeamLevel.fromJson(Map<String, dynamic> json,
          {String? teamId, int slot = 0}) =>
      TeamLevel(
        json['team'] as String,
        conceptById(json['concept'] as String),
        LevelSpec.fromJson(json['level'] as Map<String, dynamic>),
        teamId: teamId,
        slot: slot,
      );

  final String team;
  final ConceptCard card;
  final LevelSpec spec;

  /// The owning team's id on the backend; null for an offline (asset) level,
  /// which then cannot be reported cleared.
  final String? teamId;

  /// Where its landmark stands (0 to [kTeamSlots] − 1): slot `i` is on
  /// continent `i % 4`. Dealt by the backend on first verify, never moved.
  final int slot;

  Map<String, dynamic> toJson() =>
      {'team': team, 'concept': card.id, 'level': spec.toJson()};
}

/// Every team level there is: the verified ones from the Worker when a
/// server is configured and answers, else the local assets. One that does not
/// parse is left out, not allowed to break the globe for everyone else.
Future<List<TeamLevel>> loadTeamLevels(
    {String server = _server,
    String supabaseUrl = _supabaseUrl,
    String anonKey = _supabaseAnonKey,
    http.Client? client}) async {
  final supabase = supabaseUrl.isNotEmpty && anonKey.isNotEmpty;
  if (supabase || server.isNotEmpty) {
    final c = client ?? http.Client();
    try {
      // Reads come from Supabase's public view when it is configured (the
      // Worker only takes writes); the rows are what /team-game wraps.
      final r = supabase
          ? await c.get(
              Uri.parse('$supabaseUrl/rest/v1/team_games_public').replace(
                  queryParameters: {
                    'select': 'team_id,manifest,version,updated_at,'
                        'manifest_hash,verified_at,slot',
                  }),
              headers: {'apikey': anonKey, 'Authorization': 'Bearer $anonKey'},
            ).timeout(const Duration(seconds: 8))
          : await c
              .get(Uri.parse('$server/team-game'))
              .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception('${r.statusCode} ${r.body}');
      final body = jsonDecode(r.body);
      return teamLevelsFromBackend(body is List
          ? {'manifests': body}
          : body as Map<String, dynamic>);
    } catch (e) {
      debugPrint('team levels offline, using the local ones: $e');
    } finally {
      if (client == null) c.close();
    }
  }
  return _localTeamLevels();
}

/// The `GET /team-game` body → the levels the game shows: verified v2
/// manifests with a slot, ordered by slot.
@visibleForTesting
List<TeamLevel> teamLevelsFromBackend(Map<String, dynamic> body) {
  final levels = <TeamLevel>[];
  for (final row in (body['manifests'] as List? ?? const [])
      .cast<Map<String, dynamic>>()) {
    final slot = row['slot'];
    if (row['version'] != 2 ||
        row['verified_at'] == null ||
        slot is! int ||
        slot < 0 ||
        slot >= kTeamSlots) {
      continue;
    }
    try {
      levels.add(TeamLevel.fromJson(row['manifest'] as Map<String, dynamic>,
          teamId: row['team_id'] as String, slot: slot));
    } catch (e) {
      debugPrint('team level ${row['team_id']} skipped: $e');
    }
  }
  return levels..sort((a, b) => a.slot.compareTo(b.slot));
}

/// The levels in `assets/team_levels/`, slotted in index order.
Future<List<TeamLevel>> _localTeamLevels() async {
  final List<String> files;
  try {
    files = (jsonDecode(
            await rootBundle.loadString('assets/team_levels/index.json'))
        as List).cast<String>();
  } catch (_) {
    return const [];
  }
  final levels = <TeamLevel>[];
  for (final (i, f) in files.take(kTeamSlots).indexed) {
    try {
      levels.add(TeamLevel.fromJson(
          jsonDecode(await rootBundle.loadString('assets/team_levels/$f'))
              as Map<String, dynamic>,
          slot: i));
    } catch (e) {
      debugPrint('team level $f skipped: $e');
    }
  }
  return levels;
}

/// Tell the Worker this team cleared [level] (the game only calls a level
/// cleared once all three fragments are in). The first clear of another
/// team's level drains its continent (the globe hears it over Realtime); a
/// clear of your OWN level is what makes it count. True when this clear made
/// the player's own level count (`owner_clear`).
/// Best-effort: offline, a local level, or a rejection is logged and dropped.
Future<bool> reportLevelClear(TeamLevel level,
    {required double seconds,
    String server = _server,
    String? teamKey,
    String? playerId,
    http.Client? client}) async {
  final id = level.teamId;
  final key = teamKey ?? Session.current?.code ?? _teamKey;
  if (server.isEmpty || key.isEmpty || id == null) return false;
  final c = client ?? http.Client();
  try {
    final r = await c
        .post(
          Uri.parse('$server/level-clear'),
          headers: _signed(key, playerId),
          body: jsonEncode(
              {'level_team_id': id, 'seconds': seconds, 'fragments': 3}),
        )
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      debugPrint('level clear not counted: ${r.statusCode} ${r.body}');
      await Session.checkRejected(r.statusCode, r.body);
      return false;
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['owner_clear'] == true;
  } catch (e) {
    debugPrint('level clear not sent: $e');
    return false;
  } finally {
    if (client == null) c.close();
  }
}

/// Rate another team's level, 1–5 stars (re-rating overwrites). The Worker
/// refuses your own level, one you have not cleared, and test teams; any
/// refusal is quiet. True when the stars were taken.
Future<bool> rateLevel(String levelTeamId, int stars,
    {String server = _server,
    String? teamKey,
    String? playerId,
    http.Client? client}) async {
  final key = teamKey ?? Session.current?.code ?? _teamKey;
  if (server.isEmpty || key.isEmpty) return false;
  final c = client ?? http.Client();
  try {
    final r = await c
        .post(Uri.parse('$server/level-rating'),
            headers: _signed(key, playerId),
            body: jsonEncode({'level_team_id': levelTeamId, 'stars': stars}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      debugPrint('rating not taken: ${r.statusCode}');
      await Session.checkRejected(r.statusCode, r.body);
    }
    return r.statusCode == 200;
  } catch (e) {
    debugPrint('rating not sent: $e');
    return false;
  } finally {
    if (client == null) c.close();
  }
}

/// The team key, and which player (the logged-in one unless given).
Map<String, String> _signed(String key, String? playerId) => {
      'Authorization': 'Bearer $key',
      'X-Player-Id': ?(playerId ?? Session.current?.playerId),
      'Content-Type': 'application/json',
    };
