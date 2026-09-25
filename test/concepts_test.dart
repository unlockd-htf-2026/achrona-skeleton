// Each concept card's rule must tell a level that meets it from one that
// does not — checked here on small made-up levels, one of each per card.

import 'package:achrona/concepts.dart';
import 'package:achrona/kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [w]×[h] level: flat ground on the bottom row, then [draw] edits it.
LevelSpec level(
  List<(String, int, int)> objects, {
  int w = 60,
  int h = 20,
  void Function(List<List<String>> g)? draw,
}) {
  final g = List.generate(h, (_) => List.filled(w, kAir));
  for (var c = 0; c < w; c++) {
    g[h - 1][c] = kSolid;
  }
  draw?.call(g);
  final rows = [for (final r in g) r.join()];
  return LevelSpec(
    title: 'T',
    width: w,
    height: h,
    rows: () => rows,
    objects: objects,
    intro: ('', ''),
  );
}

const spawn = ('spawn', 2, 18), gate = ('gate', 50, 18);

void hole(List<List<String>> g, int c0, int c1) {
  for (final row in g) {
    for (var c = c0; c <= c1; c++) {
      row[c] = kAir;
    }
  }
}

void main() {
  test('twelve cards, twelve different ids', () {
    expect(kConcepts, hasLength(12));
    expect(kConcepts.map((c) => c.id).toSet(), hasLength(12));
  });

  final flat = level([spawn, gate]);

  // (card, a level that meets it). The flat level meets none of them.
  final meets = <String, LevelSpec>{
    'archive': level([('spawn', 2, 5), gate]),
    'clocktower': level([spawn, ('gate', 50, 4)]),
    'scaffold': level([spawn, gate], draw: (g) {
      for (var i = 0; i < 6; i++) {
        g[15][4 + i * 5] = kOneWay;
        g[15][5 + i * 5] = kOneWay;
      }
    }),
    'thorns': level([spawn, gate, for (var c = 10; c < 22; c++) ('spikes', c, 18)]),
    'causeway': level([spawn, gate], draw: (g) {
      hole(g, 10, 12);
      hole(g, 20, 22);
      hole(g, 30, 32);
    }),
    'rift': level([spawn, gate], draw: (g) => hole(g, 20, 24)),
    'barracks': level([
      spawn,
      gate,
      for (var i = 0; i < 8; i++)
        ('enemy:${['Birb', 'Cactoro', 'OrcEnemy'][i % 3]}', 10 + i * 4, 18),
    ]),
    'belfry': level([
      spawn,
      gate,
      for (var i = 0; i < 4; i++) ('enemy:Ghost', 10 + i * 5, 16),
    ]),
    'road': level([spawn, ('gate', 150, 18)], w: 160),
    'needle': level([spawn, ('gate', 40, 18)], w: 48, h: 30),
    'vault': level([spawn, ('gate', 10, 18), ('fragment', 45, 18)]),
    'ramparts': level([spawn, ('gate', 50, 10)], draw: (g) {
      for (var r = 15; r < 20; r++) {
        for (var c = 20; c < 60; c++) {
          g[r][c] = kSolid;
        }
      }
      for (var r = 11; r < 20; r++) {
        for (var c = 40; c < 60; c++) {
          g[r][c] = kSolid;
        }
      }
    }),
  };

  for (final card in kConcepts) {
    test('${card.id}: the rule tells yes from no', () {
      expect(card.check(meets[card.id]!), isNull, reason: card.rule);
      expect(card.check(flat), isNotNull,
          reason: 'a flat corridor should not meet "${card.rule}"');
    });
  }
}
