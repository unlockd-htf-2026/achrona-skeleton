/// **Concept cards** — one per team. Every team designs a level (base-01);
/// the card says what kind of place it is and names one mechanic the level
/// must be built around. The rule is checked off the [LevelSpec] alone, next
/// to "it can be finished" — so no team can meet its card with a level
/// nobody can play.
///
/// Every level is then played by every other team, and each finished run
/// heals Achrona: the card keeps twelve levels from being the same level.
library;

import 'level_one.dart' show Enemy;

import 'kit.dart';

/// A team's brief: a place in Achrona, and the one mechanic it is built on.
class ConceptCard {
  const ConceptCard(this.id, this.title, this.pitch, this.rule, this.check);

  /// What `kMyConcept` is set to.
  final String id;
  final String title;

  /// The place, in a sentence — the theme to dress it in.
  final String pitch;

  /// The mechanic, in words, exactly as [check] tests it.
  final String rule;

  /// Null when [spec] meets the card; otherwise what is missing.
  final String? Function(LevelSpec spec) check;
}

const List<ConceptCard> kConcepts = [
  ConceptCard(
    'archive',
    'The Sunken Archive',
    'A library the Desync pulled underground, shelf by shelf.',
    'A descent: the gate is at least 8 rows below the spawn.',
    _descent,
  ),
  ConceptCard(
    'clocktower',
    'The Broken Clocktower',
    'Its gears still turn; the hands point at nothing.',
    'An ascent: the gate is at least 12 rows above the spawn.',
    _ascent,
  ),
  ConceptCard(
    'scaffold',
    'The Lantern Scaffold',
    'Builders fled mid-repair; their planks still hang in the dark.',
    'At least 6 separate one-way ledges (`=` runs).',
    _scaffold,
  ),
  ConceptCard(
    'thorns',
    'The Thorn Gallery',
    'A hall where the Desync grew spikes instead of moss.',
    'At least 12 spikes.',
    _thorns,
  ),
  ConceptCard(
    'causeway',
    'The Shattered Causeway',
    'A road across the void, missing its stones.',
    'At least 3 bottomless gaps (columns with no ground at all).',
    _causeway,
  ),
  ConceptCard(
    'rift',
    'The Rift Bridge',
    'The bridge fell. The rift did not.',
    'A bottomless gap at least 5 tiles wide — one only the double jump '
        'crosses.',
    _rift,
  ),
  ConceptCard(
    'barracks',
    'The Orc Barracks',
    'Where the Desync keeps its soldiers.',
    'At least 8 enemies, of at least 3 species.',
    _barracks,
  ),
  ConceptCard(
    'belfry',
    'The Haunted Belfry',
    'The bells ring by themselves; something is up there.',
    'At least 4 flying enemies (Ghost, GhostSkull, Armabee).',
    _belfry,
  ),
  ConceptCard(
    'road',
    'The Long Road',
    'The pilgrims\' way to the first seal — it goes on.',
    'A long level: at least 160 tiles wide.',
    _road,
  ),
  ConceptCard(
    'needle',
    'The Needle',
    'A tower so thin the wind moves it.',
    'A tower: at most 48 tiles wide and at least 30 tall.',
    _needle,
  ),
  ConceptCard(
    'vault',
    'The Forgotten Vault',
    'The door is right there. The keys are not.',
    'A loop: the gate within 12 columns of the spawn, and a fragment at '
        'least 40 columns away.',
    _vault,
  ),
  ConceptCard(
    'ramparts',
    'The Rampart Walls',
    'Fortress walls, built to keep climbers out.',
    'At least 2 walls of 4+ rows on the way to the gate — each one a '
        'double jump.',
    _ramparts,
  ),
];

/// The card with [id]; throws, naming the real ones, on anything else.
ConceptCard conceptById(String id) => kConcepts.firstWhere(
      (c) => c.id == id,
      orElse: () => throw ArgumentError(
          'no concept card "$id" — set kMyConcept to your card: '
          '${kConcepts.map((c) => c.id).join(', ')}'),
    );

// ---------------------------------------------------------------------------
// The rules. Rows are the level's glyphs, row 0 at the top.
// ---------------------------------------------------------------------------

(int, int) _at(LevelSpec s, String kind) {
  final o = s.objects.firstWhere((o) => o.$1 == kind);
  return (o.$2, o.$3);
}

String? _need(bool ok, String what) => ok ? null : what;

String? _descent(LevelSpec s) => _need(
    _at(s, 'gate').$2 - _at(s, 'spawn').$2 >= 8,
    'the gate is not 8 rows below the spawn');

String? _ascent(LevelSpec s) => _need(
    _at(s, 'spawn').$2 - _at(s, 'gate').$2 >= 12,
    'the gate is not 12 rows above the spawn');

/// Maximal horizontal runs of one-way ledge.
int oneWayLedges(List<String> rows) => rows
    .map((r) => RegExp(RegExp.escape(kOneWay) + r'+').allMatches(r).length)
    .fold(0, (a, b) => a + b);

String? _scaffold(LevelSpec s) =>
    _need(oneWayLedges(s.rows()) >= 6, 'fewer than 6 one-way ledges');

String? _thorns(LevelSpec s) => _need(
    s.objects.where((o) => o.$1 == 'spikes').length >= 12,
    'fewer than 12 spikes');

/// Widths of the runs of columns with no solid ground in any row — drops
/// with no bottom. One-way ledges over them do not count as ground.
List<int> bottomlessGaps(List<String> rows) {
  final width = rows.first.length;
  final gaps = <int>[];
  var run = 0;
  for (var c = 0; c < width; c++) {
    if (rows.every((r) => r[c] != kSolid)) {
      run++;
    } else {
      if (run > 0) gaps.add(run);
      run = 0;
    }
  }
  if (run > 0) gaps.add(run);
  return gaps;
}

String? _causeway(LevelSpec s) =>
    _need(bottomlessGaps(s.rows()).length >= 3, 'fewer than 3 bottomless gaps');

String? _rift(LevelSpec s) => _need(
    bottomlessGaps(s.rows()).any((w) => w >= 5),
    'no bottomless gap 5 tiles wide');

Iterable<String> _species(LevelSpec s) => s.objects
    .where((o) => o.$1.startsWith('enemy:'))
    .map((o) => o.$1.substring(6));

String? _barracks(LevelSpec s) {
  final all = _species(s).toList();
  return _need(all.length >= 8 && all.toSet().length >= 3,
      'fewer than 8 enemies of 3 species');
}

String? _belfry(LevelSpec s) => _need(
    _species(s).where(Enemy.flyingKinds.contains).length >= 4,
    'fewer than 4 flying enemies');

String? _road(LevelSpec s) => _need(s.width >= 160, 'narrower than 160');

String? _needle(LevelSpec s) =>
    _need(s.width <= 48 && s.height >= 30, 'not 48 wide or less, 30 tall');

String? _vault(LevelSpec s) {
  final spawn = _at(s, 'spawn').$1;
  final far = s.objects
      .where((o) => o.$1 == 'fragment')
      .any((o) => (o.$2 - spawn).abs() >= 40);
  return _need((_at(s, 'gate').$1 - spawn).abs() <= 12 && far,
      'the gate is not near the spawn, or no fragment is 40 columns away');
}

/// Walls climbed on the way from the spawn to the gate: places where the
/// ground's top rises 4+ rows from one column to the next.
int wallsToClimb(LevelSpec s) {
  final rows = s.rows();
  int top(int c) {
    final r = rows.indexWhere((row) => row[c] == kSolid);
    return r < 0 ? rows.length : r;
  }

  final (from, _) = _at(s, 'spawn');
  final (to, _) = _at(s, 'gate');
  final step = to >= from ? 1 : -1;
  var walls = 0;
  for (var c = from; c != to; c += step) {
    final here = top(c), next = top(c + step);
    if (here < rows.length && next < rows.length && here - next >= 4) walls++;
  }
  return walls;
}

String? _ramparts(LevelSpec s) =>
    _need(wallsToClimb(s) >= 2, 'fewer than 2 walls of 4+ rows');
