/// Achrona — the globe's overlay chrome, ported from `globe/src/overlay.js`
/// and `globe/index.html`.
///
/// In the JS this was deliberately **DOM over the canvas**: all text lived in
/// the document, never in WebGL, so it stayed selectable, accessible and
/// screen-reader-visible. That constraint survives the port intact — here the
/// chrome is ordinary Flutter widgets over the `SceneView`, which is the same
/// separation and the same accessibility story.
///
/// Copy is verbatim from the reference, which treats it as a locked
/// copywriting contract.
library;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Connection state for the "SIGNAL LOST" banner.
enum GlobeLink { connecting, live, lost }

class GlobeChrome extends StatelessWidget {
  const GlobeChrome({
    required this.link,
    required this.corruptionPct,
    required this.hasNodes,
    this.showHint = true,
    super.key,
  });

  final GlobeLink link;

  /// Global rollup, or null before the first `world_state` row arrives.
  final double? corruptionPct;

  /// False until a non-empty node set arrives — drives the empty state.
  final bool hasNodes;

  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned(left: 28, top: 22, child: _Title()),
          if (link == GlobeLink.lost)
            const Positioned(top: 26, left: 0, right: 0, child: Center(child: _Banner())),
          if (!hasNodes)
            const Positioned.fill(child: Center(child: _EmptyState())),
          Positioned(
            left: 28,
            bottom: 26,
            child: _Legend(corruptionPct: corruptionPct),
          ),
          if (showHint)
            const Positioned(
              bottom: 26,
              left: 0,
              right: 0,
              child: Center(child: _Hint()),
            ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => Text(
        'ACHRONA',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.30),
          fontSize: 38,
          fontWeight: FontWeight.w800,
          letterSpacing: 6,
          height: 1,
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF17132E).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(kNeon).withValues(alpha: 0.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SIGNAL LOST',
              style: TextStyle(
                // Light text on a dark scrim — never magenta text (UI-SPEC).
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Lost the link to the shared world. Reconnecting automatically…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ACHRONA IS DARK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No signal from the shared world yet. Heal a node to light the map.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14,
            ),
          ),
        ],
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.corruptionPct});

  final double? corruptionPct;

  @override
  Widget build(BuildContext context) {
    final pct = corruptionPct;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF17132E).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LegendRow(color: kCorruptLand, label: 'CORRUPTED'),
          const _LegendRow(color: 0xFF7B6BD6, label: 'HEALING'),
          const _LegendRow(color: kHealedLand, label: 'CLEAN'),
          const SizedBox(height: 8),
          Text(
            'CORRUPTION ${pct == null ? "—" : "${pct.round()}%"}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});

  final int color;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) => Text(
        'DRAG TO EXPLORE · SCROLL TO ZOOM',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 11,
          letterSpacing: 2,
        ),
      );
}
