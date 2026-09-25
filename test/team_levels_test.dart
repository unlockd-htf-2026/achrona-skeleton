// Team levels travel as JSON (a team publishes its LevelSpec; every game
// fetches all of them) and stand as landmarks, three to a continent.

import 'dart:convert';
import 'dart:math' as math;

import 'package:achrona/globe/landmarks.dart' show spreadSites;
import 'package:achrona/level_one.dart';
import 'package:achrona/my_level.dart';
import 'package:achrona/concepts.dart';
import 'package:achrona/team_levels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'support/example_team_levels.dart';

void main() {
  test('a level survives the trip through JSON', () {
    for (final spec in [kLevelOne, kLevelTwo, kLevelThree, kMyLevel]) {
      final back = LevelSpec.fromJson(
          jsonDecode(jsonEncode(spec.toJson())) as Map<String, dynamic>);
      expect(back.title, spec.title);
      expect((back.width, back.height), (spec.width, spec.height));
      expect(back.rows(), spec.rows());
      expect(back.objects, spec.objects);
      expect(back.intro, spec.intro);
    }
  });

  test('a team level names its team and its concept card', () {
    final t = TeamLevel.fromJson({
      'team': 'Unlock\'d',
      'concept': 'ramparts',
      'level': kMyLevel.toJson(),
    });
    expect(t.team, 'Unlock\'d');
    expect(t.card.id, 'ramparts');
    expect(t.spec.rows(), kMyLevel.rows());
  });

  test('an unknown concept card is refused, not played', () {
    expect(
      () => TeamLevel.fromJson(
          {'team': 'x', 'concept': 'nope', 'level': kMyLevel.toJson()}),
      throwsArgumentError,
    );
  });

  test('sites spread over a continent and keep clear of the others', () {
    // A patch of "hexes": directions on a small cap of the sphere.
    final rng = math.Random(3);
    final hexes = [
      for (var i = 0; i < 400; i++)
        vm.Vector3(1, rng.nextDouble() * 0.4 - 0.2, rng.nextDouble() * 0.4 - 0.2)
            .normalized(),
    ];
    final taken = [hexes.first];
    final sites = spreadSites(hexes, 3, avoid: taken);
    expect(sites, hasLength(3));
    for (final s in sites) {
      expect(hexes, contains(s), reason: 'a site stands on a hex');
      expect(s.angleTo(taken.first), greaterThan(0.03));
      for (final o in sites) {
        if (!identical(o, s)) expect(s.angleTo(o), greaterThan(0.1));
      }
    }
  });

  group('the example team levels', () {
    final examples = exampleTeamLevels();

    test('one per concept card', () {
      expect(examples.map((t) => t.card.id).toSet(),
          kConcepts.map((c) => c.id).toSet());
    });

    for (final t in examples) {
      test('${t.card.title} meets its card', () {
        expect(t.card.check(t.spec), isNull, reason: t.card.rule);
      });
    }

    test('the Rampart Walls example is the reference student level', () {
      final r = examples.firstWhere((t) => t.card.id == 'ramparts').spec;
      expect(r.rows(), kMyLevel.rows());
      expect(r.objects, kMyLevel.objects);
    });
  });

  group('levels from the backend (GET /team-game)', () {
    Map<String, dynamic> row(String team, int? slot,
            {int version = 2, bool verified = true, String? concept}) =>
        {
          'team_id': 'id-$team',
          'version': version,
          'verified_at': verified ? '2026-09-25T10:00:00Z' : null,
          'slot': slot,
          'manifest': {
            'version': version,
            'team': team,
            'concept': concept ?? 'ramparts',
            'level': kMyLevel.toJson(),
          },
        };

    test('keeps verified v2 levels, ordered by slot, and knows whose they are',
        () {
      final levels = teamLevelsFromBackend({
        'manifests': [
          row('c', 5),
          row('a', 0),
          row('unverified', 1, verified: false),
          row('v1', 2, version: 1),
          row('bad card', 3, concept: 'nope'),
          row('no slot', null),
          row('b', 1),
        ],
      });
      expect([for (final t in levels) t.team], ['a', 'b', 'c']);
      expect([for (final t in levels) t.slot], [0, 1, 5]);
      expect(levels.first.teamId, 'id-a');
      expect(levels.first.spec.rows(), kMyLevel.rows());
    });

    test('loadTeamLevels fetches them when a server is configured', () async {
      late Uri asked;
      final levels = await loadTeamLevels(
        server: 'http://w',
        client: MockClient((r) async {
          asked = r.url;
          // As the Worker sends it: UTF-8 (the intro has an em dash), no charset.
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'manifests': [row('a', 4)]
              })),
              200,
              headers: {'content-type': 'application/json'});
        }),
      );
      expect(asked.toString(), 'http://w/team-game');
      expect([for (final t in levels) (t.team, t.slot)], [('a', 4)]);
    });

    testWidgets('an unreachable backend falls back to the local levels',
        (tester) async {
      final levels = (await tester.runAsync(() => loadTeamLevels(
            server: 'http://w',
            client: MockClient((_) async => http.Response('down', 503)),
          )))!;
      expect(levels, hasLength(12));
      expect([for (final t in levels) t.slot], List.generate(12, (i) => i));
      expect(levels.every((t) => t.teamId == null), isTrue);
    });
  });

  group('reportLevelClear (POST /level-clear)', () {
    final theirs = TeamLevel.fromJson(
        {'team': 'a', 'concept': 'ramparts', 'level': kMyLevel.toJson()},
        teamId: 'id-a',
        slot: 0);

    test('posts the level, the time and all three fragments', () async {
      late http.Request sent;
      await reportLevelClear(theirs,
          seconds: 41.5,
          server: 'http://w',
          teamKey: 'k',
          client: MockClient((r) async {
            sent = r;
            return http.Response('{"accepted":true}', 200);
          }));
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'http://w/level-clear');
      expect(sent.headers['Authorization'], 'Bearer k');
      expect(jsonDecode(sent.body),
          {'level_team_id': 'id-a', 'seconds': 41.5, 'fragments': 3});
    });

    test('stays quiet offline, for a local level, and on a rejection',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{"error":"that level is not verified"}', 409);
      });
      final local = TeamLevel.fromJson(
          {'team': 'a', 'concept': 'ramparts', 'level': kMyLevel.toJson()});
      await reportLevelClear(theirs,
          seconds: 1, server: '', teamKey: 'k', client: client);
      await reportLevelClear(local,
          seconds: 1, server: 'http://w', teamKey: 'k', client: client);
      expect(calls, 0);
      await reportLevelClear(theirs,
          seconds: 1, server: 'http://w', teamKey: 'k', client: client);
      expect(calls, 1);
    });
    test('signs as the player, and says when it made your own level count',
        () async {
      late http.Request sent;
      final counts = await reportLevelClear(theirs,
          seconds: 12,
          server: 'http://w',
          teamKey: 'k',
          playerId: 'p-1',
          client: MockClient((r) async {
            sent = r;
            return http.Response('{"accepted":true,"owner_clear":true}', 200);
          }));
      expect(sent.headers['X-Player-Id'], 'p-1');
      expect(counts, isTrue);
    });
  });

  group('rateLevel (POST /level-rating)', () {
    test('posts the level and the stars, signed as the player', () async {
      late http.Request sent;
      final ok = await rateLevel('id-a', 4,
          server: 'http://w',
          teamKey: 'k',
          playerId: 'p-1',
          client: MockClient((r) async {
            sent = r;
            return http.Response('{"rated":true}', 200);
          }));
      expect(ok, isTrue);
      expect(sent.url.toString(), 'http://w/level-rating');
      expect(sent.headers['Authorization'], 'Bearer k');
      expect(sent.headers['X-Player-Id'], 'p-1');
      expect(jsonDecode(sent.body), {'level_team_id': 'id-a', 'stars': 4});
    });

    test('a refusal (not cleared, test team) is quiet, not a crash', () async {
      final ok = await rateLevel('id-a', 5,
          server: 'http://w',
          teamKey: 'k',
          client: MockClient(
              (_) async => http.Response('{"error":"clear it first"}', 409)));
      expect(ok, isFalse);
    });
  });
}
