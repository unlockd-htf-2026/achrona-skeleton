// The leaderboard's logic, off the backend's `GET /leaderboard` contract:
// parsing, which aspect each tab ranks by, and test teams kept out of sight.

import 'dart:convert';
import 'dart:io';

import 'package:achrona/leaderboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final board = Board.fromJson(jsonDecode(
          File('assets/leaderboard/fixture.json').readAsStringSync())
      as Map<String, dynamic>);

  test('the fixture parses, weights and all', () {
    expect(board.teams, isNotEmpty);
    expect(board.weights.keys,
        containsAll(['code', 'play', 'quality', 'rating', 'design', 'creativity']));
    expect(board.challenges, isNotEmpty);
  });

  test('each tab ranks by its own aspect', () {
    expect(BoardTab.overall.aspect, isNull);
    expect(BoardTab.code.aspect, 'code');
    expect(BoardTab.level.aspect, 'quality');
    expect(BoardTab.playing.aspect, 'play');
  });

  test('a tab lists teams by that rank, unranked last, ties kept', () {
    for (final tab in BoardTab.values) {
      final ranks = [for (final t in board.rows(tab)) t.rankFor(tab)];
      final ranked = ranks.whereType<int>().toList();
      expect(ranked, [...ranked]..sort(), reason: tab.name);
      // Nulls only after every ranked team.
      final firstNull = ranks.indexOf(null);
      if (firstNull >= 0) {
        expect(ranks.sublist(firstNull).every((r) => r == null), isTrue,
            reason: tab.name);
      }
    }
  });

  test('test teams are hidden unless asked for', () {
    expect(board.teams.any((t) => t.isTest), isTrue,
        reason: 'the fixture needs a test team to prove this');
    expect(board.rows(BoardTab.overall).any((t) => t.isTest), isFalse);
    expect(board.rows(BoardTab.overall, showTest: true).any((t) => t.isTest),
        isTrue);
  });

  test('a null aspect score reads as a dash, not a zero', () {
    expect(scoreText(null), '—');
    expect(scoreText(72.36), '72.4');
  });

  test('the level tab shows rating, design and creativity when present', () {
    final withAll = board.teams.firstWhere((t) => t.aspects['design']?.score != null);
    expect(levelExtras(withAll), containsAll(['rating', 'design', 'creativity']));
    final bare = board.teams.firstWhere((t) => t.aspects['design']?.score == null);
    expect(levelExtras(bare), isNot(contains('design')));
  });

  test('a level that does not count says why', () {
    final owner = board.teams.firstWhere((t) => t.name == 'Pathfinders');
    expect(notCountedReason(owner), 'owner has not cleared it');
    final counts = board.teams.firstWhere((t) => t.name == 'Byte Knights');
    expect(notCountedReason(counts), isNull);
  });

  test('players come through, and an unjudged team says so', () {
    expect(board.teams.first.players, isNotEmpty);
    final unjudged = board.teams.firstWhere((t) => t.aspects['creativity']?.score == null);
    expect(notYetJudged(unjudged), isTrue);
    final judged = board.teams.firstWhere((t) => t.aspects['creativity']?.score != null);
    expect(notYetJudged(judged), isFalse);
  });

  testWidgets('a burst of change signals is one refetch, 500 ms after the last',
      (t) async {
    var fetches = 0;
    final d = Debounce(const Duration(milliseconds: 500), () => fetches++);
    d();
    await t.pump(const Duration(milliseconds: 300));
    d();
    await t.pump(const Duration(milliseconds: 300));
    d();
    expect(fetches, 0);
    await t.pump(const Duration(milliseconds: 499));
    expect(fetches, 0);
    await t.pump(const Duration(milliseconds: 1));
    expect(fetches, 1);
    d.cancel();
  });

  test('the board comes from the leaderboard_json RPC when Supabase is set',
      () async {
    late http.Request sent;
    final b = await fetchBoard(
        server: '',
        supabaseUrl: 'http://s',
        anonKey: 'anon',
        client: MockClient((r) async {
          sent = r;
          // Postgres numerics keep trailing zeros; timestamps end in +00:00.
          return http.Response(
              '{"generated_at":"2026-10-08T14:30:00+00:00","weights":{"code":0.30},'
              '"challenges":["base-01"],"teams":[{"team_id":"t","team":"x","is_test":false,'
              '"total":83.10,"rank":1,"aspects":{"code":{"score":100.00,"weight":0.30,"rank":1}},'
              '"breakdown":{},"players":[]}]}',
              200);
        }));
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://s/rest/v1/rpc/leaderboard_json');
    expect(sent.headers['apikey'], 'anon');
    expect(b.teams.single.total, 83.1);
    expect(b.generatedAt, isNotNull);
  });
}
