// The run→world link: what a run is worth, and that it speaks the Worker's
// /submit-score contract. Energy is the Worker's business now (it reads
// heal_config); tool/wire_check.dart holds the same claim against a live one.

import 'dart:convert';

import 'package:achrona/globe/run_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('runScore', () {
    test('pays for what was collected', () {
      expect(
        runScore(fragments: 3, kills: 8, seconds: 200, completed: true),
        3 * 10 + 8 * 25,
      );
    });

    test('a finish under par adds a bonus that fades to zero at par', () {
      final half = runScore(
          fragments: 0, kills: 0, seconds: 90, completed: true); // par/2
      final atPar =
          runScore(fragments: 0, kills: 0, seconds: 180, completed: true);
      expect(half, 400);
      expect(atPar, 0);
    });

    test('a death keeps the pickups and loses the bonus', () {
      expect(
        runScore(fragments: 2, kills: 1, seconds: 10, completed: false),
        2 * 10 + 25,
      );
    });
  });

  group('RunLink.submit', () {
    RunLink link(Map<String, dynamic> answer, {int status = 200,
        void Function(http.Request)? onSubmit}) =>
        RunLink('http://w', 'k', 'team', client: MockClient((r) async {
          if (r.url.path == '/daily-seed') {
            return http.Response(
                jsonEncode({'seed_date': '2026-09-23', 'seed_int': 7}), 200);
          }
          onSubmit?.call(r);
          return http.Response(jsonEncode(answer), status);
        }));

    test('posts a race run on today\'s seed with the team key', () async {
      late http.Request sent;
      await link({'accepted': true, 'best': 230, 'rank': 1},
          onSubmit: (r) => sent = r).submit(
          fragments: 3, kills: 8, seconds: 200, completed: true);
      expect(sent.headers['Authorization'], 'Bearer k');
      expect(jsonDecode(sent.body), {
        'team_id': 'team',
        'seed_date': '2026-09-23',
        'seed_int': 7,
        'score': 230,
        'fragments': 3,
        'mode': 'race',
      });
    });

    test('reads the heal the Worker reports', () async {
      final heal = await link({
        'accepted': true,
        'rank': 2,
        'drained': [
          {'challenge_id': 'base-01', 'amount': 6.3},
        ],
        'unlocked_count': 5,
      }).submit(fragments: 0, kills: 0, seconds: 90, completed: true);
      expect(heal.rank, 2);
      expect(heal.improved, isTrue);
      expect(heal.unlocked, 5);
      expect(heal.healed.single, (challengeId: 'base-01', drained: 6.3));
    });

    test('a kept previous best is not an improvement', () async {
      final heal = await link({
        'accepted': true,
        'kept': 'previous',
        'rank': 1,
        'drained': <Object>[],
        'unlocked_count': 5,
      }).submit(fragments: 0, kills: 0, seconds: 90, completed: true);
      expect(heal.improved, isFalse);
    });

    test('a rejection throws with the Worker\'s reason', () {
      expect(
        link({'error': 'score 9999 exceeds ceiling'}, status: 400)
            .submit(fragments: 0, kills: 0, seconds: 90, completed: true),
        throwsA(predicate((e) => '$e'.contains('exceeds ceiling'))),
      );
    });
  });
}
