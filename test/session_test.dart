// Who is playing: a team code + nickname (a player of that team) or a judge
// code, from POST /login, kept on the device. Every call to the Worker signs
// with it.

import 'dart:convert';

import 'package:achrona/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

MockClient worker(int status, Map<String, dynamic> body,
        [void Function(http.Request)? seen]) =>
    MockClient((req) async {
      seen?.call(req);
      return http.Response(jsonEncode(body), status);
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a team code logs a player in; its calls carry key and player', () async {
    late http.Request sent;
    final s = await Session.login('htf-abc', ' ada ',
        server: 'http://w',
        client: worker(200, {
          'role': 'team',
          'team_id': 't-1',
          'team': 'byte-knights',
          'player_id': 'p-1',
          'nickname': 'ada',
        }, (r) => sent = r));
    expect(jsonDecode(sent.body), {'code': 'htf-abc', 'nickname': 'ada'});
    expect(s.isTeam, isTrue);
    expect(s.teamId, 't-1');
    expect(s.nickname, 'ada');
    expect(s.headers(), {
      'Authorization': 'Bearer htf-abc',
      'X-Player-Id': 'p-1',
      'Content-Type': 'application/json',
    });
  });

  test('a judge code logs a judge in, signed as a judge', () async {
    final s = await Session.login('jdg-xyz', '',
        server: 'http://w', client: worker(200, {'role': 'judge', 'judge': 'Mo'}));
    expect(s.isJudge, isTrue);
    expect(s.judge, 'Mo');
    expect(s.headers()['Authorization'], 'Judge jdg-xyz');
    expect(s.headers(), isNot(contains('X-Player-Id')));
  });

  test('an unknown code says so', () async {
    expect(
      () => Session.login('htf-nope', 'ada',
          server: 'http://w', client: worker(401, {'error': 'unknown code'})),
      throwsA(isA<LoginError>()
          .having((e) => e.message, 'message', 'unknown code')),
    );
  });

  test('a judge code needs no nickname; a team code does', () {
    expect(isJudgeCode('jdg-1'), isTrue);
    expect(isJudgeCode(' htf-1'), isFalse);
  });

  test('it is remembered, and forgotten on log out', () async {
    await Session.login('htf-abc', 'ada',
        server: 'http://w',
        client: worker(200, {
          'role': 'team', 'team_id': 't-1', 'team': 'bk',
          'player_id': 'p-1', 'nickname': 'ada',
        }));
    final again = await Session.restore();
    expect(again?.playerId, 'p-1');
    await Session.logout();
    expect(await Session.restore(), isNull);
  });

  test('the dev key is a team session with no player', () {
    final s = Session.devFallback('heal-unlockd-reference-key', 'team-a1');
    expect(s!.headers(), {
      'Authorization': 'Bearer heal-unlockd-reference-key',
      'Content-Type': 'application/json',
    });
    expect(Session.devFallback('', 'x'), isNull);
  });

  test('a 403 "player not in this team" logs out and asks for the login',
      () async {
    await Session.login('htf-abc', 'ada',
        server: 'http://w',
        client: worker(200, {
          'role': 'team', 'team_id': 't-1', 'team': 'bk',
          'player_id': 'p-1', 'nickname': 'ada',
        }));
    final before = Session.rejected.value;
    expect(await Session.checkRejected(409, '{"error":"clear it first"}'), isFalse);
    expect(Session.current, isNotNull);
    expect(await Session.checkRejected(403, '{"error":"player not in this team"}'),
        isTrue);
    expect(Session.current, isNull);
    expect(await Session.restore(), isNull);
    expect(Session.rejected.value, before + 1);
  });
}
