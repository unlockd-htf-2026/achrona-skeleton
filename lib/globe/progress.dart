/// What this device remembers between visits: the levels it has cleared (by
/// name — team levels come and go, so an index would tick the wrong one) and
/// whether it has seen the opening.
///
/// ponytail: per device. A team's clears that count for the event are the
/// server's (the backend spec's `level_clears`); this only paints this
/// player's globe.
library;

import 'package:shared_preferences/shared_preferences.dart';

class Progress {
  Progress._(this._prefs)
      : cleared = {...?_prefs.getStringList(_clearedKey)},
        seenOpening = _prefs.getBool(_openingKey) ?? false;

  static Future<Progress> load() async =>
      Progress._(await SharedPreferences.getInstance());

  static const _clearedKey = 'achrona.cleared', _openingKey = 'achrona.opening';

  final SharedPreferences _prefs;

  /// Names of the levels this device has cleared.
  final Set<String> cleared;

  bool seenOpening;

  Future<void> clear(String level) async {
    if (cleared.add(level)) {
      await _prefs.setStringList(_clearedKey, cleared.toList());
    }
  }

  Future<void> sawOpening() async {
    seenOpening = true;
    await _prefs.setBool(_openingKey, true);
  }

  /// Which of [names] (the globe's level list, in order) are cleared.
  Set<int> clearedIndices(List<String> names) => {
        for (final (i, n) in names.indexed)
          if (cleared.contains(n)) i,
      };
}
