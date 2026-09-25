/// The event leaderboard: every team ranked overall and by what it did —
/// its code (challenges GREEN), its level (cleared by others, rated, judged)
/// and its play (other teams' levels it cleared). One screen for a team's
/// game and for the venue's big screen (the SHOWCASE build, `?board`).
///
/// Reads the Worker's public `GET /leaderboard`. Live: the backend broadcasts
/// `changed` on the public Realtime channel `leaderboard` whenever a score
/// moves, and the screen refetches (debounced); a slow poll backs it up.
/// Without Realtime config it polls every 10 s; with no server at all it
/// shows `assets/leaderboard/fixture.json`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart'
    show RealtimeChannel, RealtimeSubscribeStatus, SupabaseClient;

import 'globe/palette.dart';
import 'level_one.dart' show kShowcase;

const _server = String.fromEnvironment('AI_SERVER_URL');
// The globe's Realtime config: the legacy anon JWT (a publishable key breaks
// Realtime).
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Runs [action] once, [delay] after the last call — a burst of Realtime
/// signals becomes one refetch.
class Debounce {
  Debounce(this.delay, this.action);
  final Duration delay;
  final VoidCallback action;
  Timer? _timer;

  void call() {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();
}

/// How each tab ranks: overall by the total, the rest by one aspect. "Level"
/// is the `quality` aspect; rating, design and creativity show inside it.
enum BoardTab {
  overall('OVERALL', null),
  code('CODE', 'code'),
  level('LEVEL', 'quality'),
  playing('PLAYING', 'play');

  const BoardTab(this.label, this.aspect);
  final String label;
  final String? aspect;
}

/// One aspect of a team's score: 0–100 (null until there is one), its weight
/// in the total, and its competition rank among real teams.
typedef Aspect = ({double? score, double weight, int? rank});

class TeamRow {
  TeamRow.fromJson(Map<String, dynamic> j)
      : id = j['team_id'] as String,
        name = j['team'] as String,
        isTest = j['is_test'] as bool? ?? false,
        total = (j['total'] as num?)?.toDouble(),
        rank = j['rank'] as int?,
        aspects = {
          for (final e in (j['aspects'] as Map<String, dynamic>).entries)
            e.key: (
              score: (e.value['score'] as num?)?.toDouble(),
              weight: (e.value['weight'] as num? ?? 0).toDouble(),
              rank: e.value['rank'] as int?,
            ),
        },
        breakdown = j['breakdown'] as Map<String, dynamic>? ?? const {},
        players = (j['players'] as List? ?? const []).cast<String>();

  final String id;
  final String name;
  final bool isTest;
  final double? total;
  final int? rank;
  final Map<String, Aspect> aspects;

  /// Nicknames of the team's players.
  final List<String> players;

  /// The contract's `breakdown`, read where it is shown.
  final Map<String, dynamic> breakdown;

  int? rankFor(BoardTab tab) =>
      tab.aspect == null ? rank : aspects[tab.aspect]?.rank;
  double? scoreFor(BoardTab tab) =>
      tab.aspect == null ? total : aspects[tab.aspect]?.score;
}

class Board {
  Board.fromJson(Map<String, dynamic> j)
      : generatedAt = DateTime.tryParse(j['generated_at'] as String? ?? ''),
        weights = {
          for (final e in (j['weights'] as Map<String, dynamic>).entries)
            e.key: (e.value as num).toDouble(),
        },
        challenges = (j['challenges'] as List).cast<String>(),
        teams = [
          for (final t in j['teams'] as List)
            TeamRow.fromJson(t as Map<String, dynamic>),
        ];

  final DateTime? generatedAt;
  final Map<String, double> weights;
  final List<String> challenges;
  final List<TeamRow> teams;

  /// The teams as [tab] ranks them: ranked first by rank (ties keep the
  /// backend's order), unranked after; test teams only when [showTest].
  List<TeamRow> rows(BoardTab tab, {bool showTest = false}) {
    final list = [
      for (final t in teams)
        if (showTest || !t.isTest) t,
    ];
    final order = {for (final (i, t) in list.indexed) t: i};
    return list
      ..sort((a, b) {
        final ra = a.rankFor(tab), rb = b.rankFor(tab);
        if (ra != rb) return (ra ?? 1 << 30).compareTo(rb ?? 1 << 30);
        return order[a]!.compareTo(order[b]!);
      });
  }
}

/// A score as shown: one decimal, or a dash when there is none yet.
String scoreText(double? score) => score == null ? '—' : score.toStringAsFixed(1);

/// Why [t]'s level does not count yet ("owner has not cleared it", …), or
/// null when it counts. Only a counting level feeds the level scores.
String? notCountedReason(TeamRow t) {
  final level = t.breakdown['level'] as Map<String, dynamic>?;
  if (level == null || level['counts'] == true) return null;
  return level['not_counted_reason'] as String?;
}

/// True while the jury has not scored [t]'s creativity: its total leaves
/// creativity out until then.
bool notYetJudged(TeamRow t) =>
    (t.aspects['creativity']?.weight ?? 0) > 0 &&
    t.aspects['creativity']?.score == null;

/// The extra aspects the Level tab shows for [t], in order, when scored.
List<String> levelExtras(TeamRow t) => [
      for (final a in const ['rating', 'design', 'creativity'])
        if (t.aspects[a]?.score != null) a,
    ];

const _aspectNames = {
  'code': 'Code',
  'play': 'Playing',
  'quality': 'Level',
  'rating': 'Rating',
  'design': 'Design (advisory)',
  'creativity': 'Creativity',
};

/// Fetches the board: the Worker when configured, else the bundled fixture.
Future<Board> fetchBoard({http.Client? client}) async {
  if (_server.isEmpty) {
    return Board.fromJson(jsonDecode(
            await rootBundle.loadString('assets/leaderboard/fixture.json'))
        as Map<String, dynamic>);
  }
  final res = await (client ?? http.Client())
      .get(Uri.parse('$_server/leaderboard'))
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) throw Exception('leaderboard ${res.statusCode}');
  return Board.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------
// The screen.
// ---------------------------------------------------------------------------

const _bg = Color(kBgVoid);
const _neon = Color(kNeon);
const _cyan = Color(kCyan);
const _panel = Color(0xFF14102A);

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  Board? _board;
  Object? _error;
  bool _showTest = false;
  Timer? _poll;
  late final _refetch = Debounce(const Duration(milliseconds: 500), _load);
  SupabaseClient? _realtime;
  RealtimeChannel? _channel;
  Timer? _resubscribe;

  @override
  void initState() {
    super.initState();
    _load();
    final live = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
    if (live) {
      _realtime = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
      _subscribe();
    }
    // Realtime does the work when it is there; the poll only backs it up.
    _poll = Timer.periodic(Duration(seconds: live ? 60 : 10), (_) => _load());
  }

  /// `changed` on the `leaderboard` channel → refetch; on an error or a
  /// close, subscribe again a little later (as the globe's world does).
  void _subscribe() {
    final client = _realtime;
    if (client == null || !mounted) return;
    _channel = client
        .channel('leaderboard')
        .onBroadcast(event: 'changed', callback: (_) => _refetch())
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _resubscribe?.cancel();
        _resubscribe = Timer(const Duration(seconds: 5), () async {
          final old = _channel;
          if (old != null) await client.removeChannel(old);
          _subscribe();
        });
      } else if (status == RealtimeSubscribeStatus.subscribed) {
        _refetch(); // anything that moved while we were away
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _refetch.cancel();
    _resubscribe?.cancel();
    final client = _realtime;
    _realtime = null;
    if (client != null) {
      client.removeAllChannels();
      client.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await fetchBoard();
      if (mounted) {
        setState(() {
          _board = b;
          _error = null;
        });
      }
    } catch (e) {
      // Keep showing the last board; say it is stale.
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The venue screen is read from across the room.
    final scale = kShowcase ? 1.6 : 1.0;
    final board = _board;
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: DefaultTabController(
        length: BoardTab.values.length,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            title: const Text('LEADERBOARD',
                style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w300)),
            actions: [
              if (_error != null)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Tooltip(
                      message: 'Could not refresh — showing the last board',
                      child: Icon(Icons.cloud_off, color: Colors.white38)),
                ),
              if (!kShowcase)
                IconButton(
                  tooltip: _showTest ? 'Hide test teams' : 'Show test teams',
                  icon: Icon(_showTest ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white54),
                  onPressed: () => setState(() => _showTest = !_showTest),
                ),
            ],
            bottom: TabBar(
              indicatorColor: _cyan,
              labelColor: _cyan,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(letterSpacing: 2),
              tabs: [for (final t in BoardTab.values) Tab(text: t.label)],
            ),
          ),
          body: board == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator(color: _neon)
                      : const Text('The leaderboard is not reachable yet.',
                          style: TextStyle(color: Colors.white54)))
              : Column(
                  children: [
                    _Weights(board.weights),
                    Expanded(
                      child: TabBarView(children: [
                        for (final tab in BoardTab.values)
                          _Table(
                            tab: tab,
                            rows: board.rows(tab, showTest: _showTest),
                            onTap: (t) => _details(context, board, t),
                          ),
                      ]),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _details(BuildContext context, Board board, TeamRow t) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: _panel,
        isScrollControlled: true,
        builder: (_) => _Breakdown(board: board, team: t),
      );
}

/// The weights, so a total can be explained: "Code 30% · Playing 20% …".
class _Weights extends StatelessWidget {
  const _Weights(this.weights);
  final Map<String, double> weights;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            const Text('TOTAL =',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            for (final e in weights.entries)
              if (e.value > 0)
                Text('${_aspectNames[e.key] ?? e.key} ${(e.value * 100).round()}%',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      );
}

class _Table extends StatelessWidget {
  const _Table({required this.tab, required this.rows, required this.onTap});
  final BoardTab tab;
  final List<TeamRow> rows;
  final ValueChanged<TeamRow> onTap;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final t = rows[i];
          final rank = t.rankFor(tab);
          return Material(
            color: _panel,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTap(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(rank == null ? '–' : '$rank',
                          style: TextStyle(
                              color: rank == 1 ? _cyan : Colors.white70,
                              fontSize: 22,
                              fontWeight: FontWeight.w300)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name + (t.isTest ? '  (test)' : ''),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 17)),
                          if (tab == BoardTab.level && notCountedReason(t) != null)
                            Text('not counting: ${notCountedReason(t)}',
                                style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic)),
                          if (tab == BoardTab.level && notYetJudged(t))
                            const Text('not yet judged',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic)),
                          if (tab == BoardTab.level && levelExtras(t).isNotEmpty)
                            Text(
                              [
                                for (final a in levelExtras(t))
                                  '${_aspectNames[a]} ${scoreText(t.aspects[a]!.score)}',
                              ].join('  ·  '),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    Text(scoreText(t.scoreFor(tab)),
                        style: const TextStyle(
                            color: _neon, fontSize: 22, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// A team's detail: every aspect, then what is behind each.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.board, required this.team});
  final Board board;
  final TeamRow team;

  static String _secs(Object? s) =>
      s is num ? '${s.toStringAsFixed(1)} s' : '—';
  static String _by(Map<String, dynamic> run) =>
      run['player'] == null ? '' : '  (${run['player']})';

  @override
  Widget build(BuildContext context) {
    final b = team.breakdown;
    final code = b['code'] as Map<String, dynamic>?;
    final level = b['level'] as Map<String, dynamic>?;
    final play = b['play'] as Map<String, dynamic>?;
    final creativity = b['creativity'] as Map<String, dynamic>?;
    final rating = level?['rating'] as Map<String, dynamic>?;
    final design = level?['design'] as Map<String, dynamic>?;
    const h = TextStyle(color: _cyan, letterSpacing: 2, fontSize: 13);
    const body = TextStyle(color: Colors.white70);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          Text(team.name,
              style: const TextStyle(color: Colors.white, fontSize: 24)),
          if (team.players.isNotEmpty)
            Text(team.players.join(' · '),
                style: const TextStyle(color: Colors.white38)),
          const SizedBox(height: 4),
          Text('Total ${scoreText(team.total)}'
              '${team.rank == null ? '' : '  ·  rank ${team.rank}'}',
              style: const TextStyle(color: _neon)),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 6, children: [
            for (final e in team.aspects.entries)
              Text('${_aspectNames[e.key] ?? e.key} ${scoreText(e.value.score)}',
                  style: body),
          ]),
          const Divider(color: Colors.white12, height: 32),
          const Text('CODE', style: h),
          if (code != null) ...[
            Text('${code['passed']} of ${code['of']} challenges GREEN', style: body),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in (code['challenges'] as List).cast<Map<String, dynamic>>())
                Chip(
                  label: Text(c['id'] as String),
                  backgroundColor: c['green'] == true
                      ? const Color(0xFF1C5E3A)
                      : const Color(0xFF2A2440),
                  labelStyle: const TextStyle(color: Colors.white),
                  side: BorderSide.none,
                ),
            ]),
          ],
          const Divider(color: Colors.white12, height: 32),
          const Text('LEVEL', style: h),
          if (level == null || level['published'] != true)
            const Text('No level published yet.', style: body)
          else ...[
            Text('${level['title'] ?? ''}  ·  ${level['concept'] ?? ''}'
                '${level['verified'] == true ? '' : '  ·  not verified'}',
                style: body),
            if (notCountedReason(team) != null)
              Text('Not counting yet: ${notCountedReason(team)}',
                  style: const TextStyle(color: Colors.white38)),
            Text('Cleared by ${level['cleared_count']} of ${level['of']}',
                style: body),
            for (final r in (level['cleared_by'] as List? ?? const [])
                .cast<Map<String, dynamic>>())
              Text('  ${r['team']}  ${_secs(r['best_seconds'])}${_by(r)}',
                  style: body),
            if (rating != null && (rating['count'] as num? ?? 0) > 0)
              Text('Rating ${(rating['avg'] as num).toStringAsFixed(1)} ★ '
                  'from ${rating['count']}  '
                  '(${[for (var s = 5; s >= 1; s--) '$s★ ${(rating['distribution'] as Map)['$s'] ?? 0}'].join(', ')})',
                  style: body),
            if (design != null) ...[
              Text('Design (advisory) ${scoreText((design['score'] as num?)?.toDouble())}'
                  '${design['flagged'] == true ? '  ·  flagged for review' : ''}',
                  style: body),
              for (final h in (design['hints'] as List? ?? const []))
                Text('  · $h',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
            if (creativity != null)
              Text('Creativity ${(creativity['avg'] as num).toStringAsFixed(1)} / 10 '
                  'from ${creativity['judges']} judges',
                  style: body),
          ],
          const Divider(color: Colors.white12, height: 32),
          const Text('PLAYING', style: h),
          if (play != null) ...[
            Text('Cleared ${play['cleared_count']} of ${play['of']} levels',
                style: body),
            for (final r in (play['cleared'] as List? ?? const [])
                .cast<Map<String, dynamic>>())
              Text('  ${r['team']}  ${_secs(r['best_seconds'])}${_by(r)}',
                  style: body),
          ],
        ],
      ),
    );
  }
}
