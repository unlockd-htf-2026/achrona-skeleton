/// Achrona — live world data (GLOBE-03), ported from `globe/src/world.js`.
///
/// One Supabase client with the **publishable/anon key only** — never a
/// service-role key. One Realtime channel listening to Postgres Changes on
/// exactly the two published tables (`nodes`, `world_state`), with the current
/// rows seeded by a SELECT *inside* the subscribed callback so there is no load
/// gap. `regions` is not in the publication, so it is SELECTed once and never
/// subscribed.
///
/// Every payload is treated as untrusted: numeric pools are coerced and
/// clamped before they reach the render layer.
library;

import 'package:supabase/supabase.dart';

import 'territories.dart';

/// Coerce an untrusted payload value to a finite number ≥ 0.
double clampNum(Object? v) {
  final n = switch (v) {
    num() => v.toDouble(),
    String() => double.tryParse(v) ?? 0,
    _ => 0.0,
  };
  return n.isFinite && n > 0 ? n : 0;
}

GlobeNode _normalize(Map<String, dynamic> row) => GlobeNode(
      challengeId: '${row['challenge_id'] ?? ''}',
      regionId: clampNum(row['region_id']).round(),
      structuralRemaining: clampNum(row['structural_remaining']),
      residualRemaining: clampNum(row['residual_remaining']),
      structuralMax: clampNum(row['structural_max']),
      residualMax: clampNum(row['residual_max']),
    );

/// Live connection to the shared world.
class World {
  World._(this._client);

  final SupabaseClient _client;
  final Map<String, GlobeNode> _nodes = {};

  void Function(List<GlobeNode> nodes)? onNodes;
  void Function(double corruptionPct)? onRollup;
  void Function(bool connected)? onConnectionChange;

  /// Connect, seed and subscribe. Returns null when no config was supplied, so
  /// the globe degrades to the reference's dark state rather than throwing.
  static World? connect({required String url, required String anonKey}) {
    if (url.isEmpty || anonKey.isEmpty) return null;
    return World._(SupabaseClient(url, anonKey));
  }

  void start() {
    _client
        .channel('achrona-world')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nodes',
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            final node = _normalize(payload.newRecord);
            if (node.challengeId.isEmpty) return;
            _nodes[node.challengeId] = node;
            onNodes?.call(_nodes.values.toList());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'world_state',
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            onRollup?.call(clampNum(payload.newRecord['corruption_pct']));
          },
        )
        .subscribe((status, _) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            onConnectionChange?.call(true);
            await _seed();
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            onConnectionChange?.call(false);
          }
        });
  }

  /// No-gap seed: SELECT the current state now that the channel is live, so
  /// nothing that changed while connecting is missed.
  Future<void> _seed() async {
    final rows = await _client.from('nodes').select();
    _nodes
      ..clear()
      ..addEntries(
        rows.map(_normalize).map((n) => MapEntry(n.challengeId, n)),
      );
    onNodes?.call(_nodes.values.toList());

    final world = await _client
        .from('world_state')
        .select('corruption_pct,total_runs')
        .limit(1)
        .maybeSingle();
    if (world != null) {
      onRollup?.call(clampNum(world['corruption_pct']));
    }

    // regions is NOT in the Realtime publication — read once, never subscribe.
    await _client.from('regions').select();
  }
}
