// The judge's two calls: the team list (with their own earlier score) and
// scoring a team's creativity, both signed `Judge <code>`.

import 'dart:convert';

import 'package:achrona/judge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('the team list, with the level and this judge\'s own score', () async {
    late http.Request sent;
    final teams = await judgeTeams(
      code: 'jdg-1',
      server: 'http://w',
      client: MockClient((r) async {
        sent = r;
        return http.Response(
            jsonEncode({
              'judge': 'Mo',
              'teams': [
                {
                  'team_id': 't1',
                  'team': 'Byte Knights',
                  'level': {
                    'concept': 'rift', 'title': 'THE RIFT', 'slot': 2, 'counts': true,
                    'design_hints': ['route: 7 climbs, 3 gaps'], 'design_flagged': true,
                  },
                  'mine': {'score': 7.5, 'note': 'bold', 'at': '2026-10-08T12:00:00Z'},
                },
                {'team_id': 't2', 'team': 'Night Owls', 'level': null, 'mine': null},
              ],
            }),
            200);
      }),
    );
    expect(sent.headers['Authorization'], 'Judge jdg-1');
    expect(sent.url.toString(), 'http://w/judge/teams');
    expect(teams, hasLength(2));
    expect(teams.first.levelTitle, 'THE RIFT');
    expect(teams.first.myScore, 7.5);
    expect(teams.first.myNote, 'bold');
    expect(teams.first.designHints, ['route: 7 climbs, 3 gaps']);
    expect(teams.first.designFlagged, isTrue);
    expect(teams.last.levelTitle, isNull);
    expect(teams.last.designHints, isEmpty);
    expect(teams.last.myScore, isNull);
  });

  test('a score goes out rounded to one decimal, with the note', () async {
    late http.Request sent;
    await scoreCreativity('t1', 7.25, 'nice rift',
        code: 'jdg-1',
        server: 'http://w',
        client: MockClient((r) async {
          sent = r;
          return http.Response('{"saved":true}', 200);
        }));
    expect(sent.url.toString(), 'http://w/judge/creativity');
    expect(sent.headers['Authorization'], 'Judge jdg-1');
    expect(jsonDecode(sent.body), {'team_id': 't1', 'score': 7.3, 'note': 'nice rift'});
  });

  test('no note, no note field; a refusal throws with the reason', () async {
    late http.Request sent;
    await scoreCreativity('t1', 8, '',
        code: 'jdg-1',
        server: 'http://w',
        client: MockClient((r) async {
          sent = r;
          return http.Response('{"saved":true}', 200);
        }));
    expect(jsonDecode(sent.body), {'team_id': 't1', 'score': 8});
    expect(
      () => scoreCreativity('t1', 8, '',
          code: 'jdg-x',
          server: 'http://w',
          client: MockClient(
              (_) async => http.Response('{"error":"unauthorized"}', 401))),
      throwsA(isA<Exception>()),
    );
  });
}
