/// Who is at the keys. One code-login for everyone: a team code (`htf-…`) and
/// a nickname make you a player of that team; a judge code (`jdg-…`) makes
/// you a judge. `POST /login` answers, the device remembers, and every call
/// to the Worker signs with it ([headers]).
///
/// Builds without a login (dev, the showcase) fall back to the
/// `--dart-define=TEAM_API_KEY` team, with no player ([devFallback]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _server = String.fromEnvironment('AI_SERVER_URL');

/// The code a judge types.
bool isJudgeCode(String code) => code.trim().startsWith('jdg-');

/// A login the Worker refused, with its reason ("unknown code", …).
class LoginError implements Exception {
  LoginError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Session {
  const Session._({
    required this.role,
    required this.code,
    this.teamId,
    this.team,
    this.playerId,
    this.nickname,
    this.judge,
  });

  /// `team` or `judge`.
  final String role;
  final String code;
  final String? teamId;
  final String? team;
  final String? playerId;
  final String? nickname;
  final String? judge;

  bool get isTeam => role == 'team';
  bool get isJudge => role == 'judge';

  /// This device's session: set at start-up ([restore] or the dev key) and
  /// by the login screen; null until someone logs in.
  static Session? current;

  static const _key = 'achrona.session';

  /// Headers for the Worker: the team key (+ which player), or the judge.
  Map<String, String> headers() => {
        'Authorization': isJudge ? 'Judge $code' : 'Bearer $code',
        'X-Player-Id': ?playerId,
        'Content-Type': 'application/json',
      };

  /// The dev/showcase team from `--dart-define`s, or null with no key.
  static Session? devFallback(String key, String teamId) => key.isEmpty
      ? null
      : Session._(role: 'team', code: key, teamId: teamId);

  /// Logs in with [code] (+ [nickname] for a team code), remembers it, and
  /// makes it [current]. Throws [LoginError] with the Worker's reason.
  static Future<Session> login(String code, String nickname,
      {String server = _server, http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(Uri.parse('$server/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'code': code.trim(),
                if (!isJudgeCode(code)) 'nickname': nickname.trim(),
              }))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) {
        throw LoginError(body['error'] as String? ?? 'login failed');
      }
      final s = Session._(
        role: body['role'] as String,
        code: code.trim(),
        teamId: body['team_id'] as String?,
        team: body['team'] as String?,
        playerId: body['player_id'] as String?,
        nickname: body['nickname'] as String?,
        judge: body['judge'] as String?,
      );
      await (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode(s._toJson()));
      return current = s;
    } on LoginError {
      rethrow;
    } catch (e) {
      throw LoginError('could not reach the server');
    } finally {
      if (client == null) c.close();
    }
  }

  /// The remembered session, if any (also sets [current]).
  static Future<Session?> restore() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return current = Session._(
      role: j['role'] as String,
      code: j['code'] as String,
      teamId: j['team_id'] as String?,
      team: j['team'] as String?,
      playerId: j['player_id'] as String?,
      nickname: j['nickname'] as String?,
      judge: j['judge'] as String?,
    );
  }

  /// Bumped when the Worker no longer knows this player (403 "player not in
  /// this team": the team's players were reset or renamed). The globe listens
  /// and shows the login again.
  static final rejected = ValueNotifier<int>(0);

  /// Call with any signed call's answer: on that 403 it logs out and bumps
  /// [rejected]. True when it did.
  static Future<bool> checkRejected(int status, String body) async {
    if (status != 403 || !body.contains('player not in this team')) return false;
    await logout();
    rejected.value++;
    return true;
  }

  /// Forgets this device's login ("switch team / log out").
  static Future<void> logout() async {
    current = null;
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  Map<String, dynamic> _toJson() => {
        'role': role,
        'code': code,
        'team_id': teamId,
        'team': team,
        'player_id': playerId,
        'nickname': nickname,
        'judge': judge,
      };
}
