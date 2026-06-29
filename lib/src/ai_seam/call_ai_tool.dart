import 'dart:convert';
import 'dart:math';

import 'package:achrona_engine/src/ai_seam/local_fallback_dataset.dart';
import 'package:achrona_engine/src/fragments/augment_perk.dart';
import 'package:http/http.dart' as http;

// AI_SERVER_URL injected via --dart-define-from-file=env.dev.json (SCAF-04).
// Phase 1: stub — no network call. AI_SERVER_URL and TEAM_API_KEY are blank.
// Phase 2: reads AI_SERVER_URL + TEAM_API_KEY, POSTs to Worker endpoint with
//   Authorization: Bearer _teamKey. Nothing outside ai_seam/ calls this
//   function — it is the single swap point (D-13).
//
// Two-layer offline fallback (D-28):
//   (a) Worker-side: fallbacks.ts withFallback returns canned JSON if AI fails
//   (b) Client-side: if Worker is unreachable, falls back to
//       kLocalAugmentFallbacks

// Environment values baked in at compile time via --dart-define-from-file.
// Empty strings when not configured (development / test without env file).
const _serverUrl = String.fromEnvironment('AI_SERVER_URL');
const _teamKey = String.fromEnvironment('TEAM_API_KEY');

/// Trigger an augment action and receive an [AugmentResult] describing which
/// perk to apply and for how long.
///
/// Phase 2 body: POSTs to the AI content server and parses the response.
/// Falls back to [kLocalAugmentFallbacks] when:
///   - `AI_SERVER_URL` is not configured (empty), or
///   - the Worker is unreachable (network error, timeout), or
///   - the Worker returns a non-200 response.
///
/// Optional [httpClient], [serverUrl], and [teamKey] parameters allow
/// dependency injection for testing (default values use the compile-time
/// --dart-define constants).
Future<AugmentResult> callAITool(
  String tool,
  Map<String, dynamic> args, {
  http.Client? httpClient,
  String? serverUrl,
  String? teamKey,
}) async {
  final resolvedUrl = serverUrl ?? _serverUrl;
  final resolvedKey = teamKey ?? _teamKey;

  if (resolvedUrl.isEmpty) {
    // Offline / not configured: return from local fallback immediately (D-28).
    return _localFallback();
  }

  final client = httpClient ?? http.Client();
  try {
    final uri = Uri.parse('$resolvedUrl/$tool');
    final response = await client
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $resolvedKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(args),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Parse perk: must be one of the three enum values. Worker Zod schema
      // enforces this server-side; orElse handles unexpected values (T-02-26).
      final perkStr = data['perk'] as String? ?? 'laneShield';
      final perk = AugmentPerk.values.firstWhere(
        (p) => p.name == perkStr,
        orElse: () => AugmentPerk.laneShield,
      );
      final durationSec = (data['duration'] as num?)?.toInt() ?? 6;
      return AugmentResult(perk, Duration(seconds: durationSec));
    }
    // Non-200 → fall through to local fallback below.
  } on Exception {
    // Network error, timeout, or unexpected response — fall through (T-02-28).
  } finally {
    // Only close the client if we created it (do not close injected clients).
    if (httpClient == null) {
      client.close();
    }
  }

  // D-28 client-side fallback: Worker unreachable → local dataset keeps
  // Rung 2 playable offline.
  return _localFallback();
}

AugmentResult _localFallback() {
  return kLocalAugmentFallbacks[
    Random().nextInt(kLocalAugmentFallbacks.length)
  ];
}
