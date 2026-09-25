/// The jury's screen: every team, its level (to open and play), and this
/// judge's own creativity score — 0 to 10, big buttons, an optional note.
/// Phone-first: judges walk the room. `GET /judge/teams`, `POST
/// /judge/creativity`, signed `Judge <code>`; a judge never sees another
/// judge's scores.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'globe/palette.dart';
import 'session.dart';

const _server = String.fromEnvironment('AI_SERVER_URL');

class JudgeTeam {
  JudgeTeam.fromJson(Map<String, dynamic> j)
      : id = j['team_id'] as String,
        name = j['team'] as String,
        levelTitle = (j['level'] as Map?)?['title'] as String?,
        levelConcept = (j['level'] as Map?)?['concept'] as String?,
        levelCounts = (j['level'] as Map?)?['counts'] == true,
        designHints = [
          for (final h in (j['level'] as Map?)?['design_hints'] as List? ?? const [])
            '$h',
        ],
        designFlagged = (j['level'] as Map?)?['design_flagged'] == true,
        myScore = ((j['mine'] as Map?)?['score'] as num?)?.toDouble(),
        myNote = (j['mine'] as Map?)?['note'] as String?;

  final String id;
  final String name;
  final String? levelTitle;
  final String? levelConcept;
  final bool levelCounts;

  /// Jev's design notes on the level (the judge's assistant, advisory).
  final List<String> designHints;
  final bool designFlagged;
  final double? myScore;
  final String? myNote;
}

Map<String, String> _judged(String code) =>
    {'Authorization': 'Judge $code', 'Content-Type': 'application/json'};

/// The teams, with this judge's own earlier score and note.
Future<List<JudgeTeam>> judgeTeams(
    {required String code, String server = _server, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(Uri.parse('$server/judge/teams'), headers: _judged(code))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw Exception('judge teams: ${r.statusCode}');
    return [
      for (final t in (jsonDecode(r.body) as Map<String, dynamic>)['teams'] as List)
        JudgeTeam.fromJson(t as Map<String, dynamic>),
    ];
  } finally {
    if (client == null) c.close();
  }
}

/// Saves this judge's creativity score for [teamId] (re-scoring overwrites).
Future<void> scoreCreativity(String teamId, double score, String note,
    {required String code, String server = _server, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .post(Uri.parse('$server/judge/creativity'),
            headers: _judged(code),
            body: jsonEncode({
              'team_id': teamId,
              'score': (score * 10).round() / 10,
              if (note.trim().isNotEmpty) 'note': note.trim(),
            }))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      throw Exception(
          (jsonDecode(r.body) as Map<String, dynamic>)['error'] ?? 'not saved');
    }
  } finally {
    if (client == null) c.close();
  }
}

// ---------------------------------------------------------------------------

const _bg = Color(kBgVoid);
const _cyan = Color(kCyan);
const _panel = Color(0xFF14102A);

class JudgePage extends StatefulWidget {
  const JudgePage({super.key, this.onPlay});

  /// Opens a team's level on the globe (the judge then plays it).
  final ValueChanged<String>? onPlay;

  @override
  State<JudgePage> createState() => _JudgePageState();
}

class _JudgePageState extends State<JudgePage> {
  List<JudgeTeam>? _teams;
  Object? _error;

  String get _code => Session.current!.code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await judgeTeams(code: _code);
      if (mounted) setState(() => _teams = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teams = _teams;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: Text('JUDGE · ${Session.current?.judge ?? ''}',
            style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w300)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: teams == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: _cyan)
                  : Text('Could not load the teams: $_error',
                      style: const TextStyle(color: Colors.white54)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: teams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = teams[i];
                return Material(
                  color: _panel,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(t.name,
                        style: const TextStyle(color: Colors.white, fontSize: 18)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            t.levelTitle == null
                                ? 'no level yet'
                                : '${t.levelTitle} · ${t.levelConcept}'
                                    '${t.levelCounts ? '' : ' · not counting yet'}',
                            style: const TextStyle(color: Colors.white54)),
                        if (t.designFlagged)
                          const Text('flagged for review',
                              style: TextStyle(color: Color(0xFFFFC94D), fontSize: 12)),
                        for (final h in t.designHints)
                          Text('· $h',
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (t.levelTitle != null && widget.onPlay != null)
                        IconButton(
                          tooltip: 'Play this level',
                          icon: const Icon(Icons.play_arrow, color: _cyan),
                          onPressed: () => widget.onPlay!(t.id),
                        ),
                      Text(t.myScore == null ? '—' : t.myScore!.toStringAsFixed(1),
                          style: const TextStyle(color: _cyan, fontSize: 22)),
                    ]),
                    onTap: () => _score(t),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _score(JudgeTeam t) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _panel,
      isScrollControlled: true,
      builder: (_) => _ScoreSheet(team: t, code: _code),
    );
    if (saved == true) _load();
  }
}

class _ScoreSheet extends StatefulWidget {
  const _ScoreSheet({required this.team, required this.code});
  final JudgeTeam team;
  final String code;

  @override
  State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  late double? _score = widget.team.myScore;
  late final _note = TextEditingController(text: widget.team.myNote ?? '');
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await scoreCreativity(widget.team.id, _score!, _note.text, code: widget.code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.team.name} — creativity',
                style: const TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 16),
            // Big buttons for the whole points: judges score standing up.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var n = 0; n <= 10; n++)
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor:
                            _score?.round() == n ? _cyan : const Color(0xFF241D44),
                        foregroundColor:
                            _score?.round() == n ? _bg : Colors.white,
                      ),
                      onPressed: () => setState(() => _score = n.toDouble()),
                      child: Text('$n', style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            // And a slider for the half points in between.
            Slider(
              value: _score ?? 5,
              min: 0,
              max: 10,
              divisions: 20,
              activeColor: _cyan,
              label: (_score ?? 5).toStringAsFixed(1),
              onChanged: (v) => setState(() => _score = v),
            ),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'note (optional, only you see it)',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6B8A))),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _score == null || _busy ? null : _save,
              style: FilledButton.styleFrom(
                  backgroundColor: _cyan,
                  foregroundColor: _bg,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_score == null
                  ? 'PICK A SCORE'
                  : 'SAVE ${_score!.toStringAsFixed(1)}'),
            ),
          ],
        ),
      );
}
