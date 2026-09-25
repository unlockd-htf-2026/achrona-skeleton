// What a device remembers between visits: which levels it has cleared, and
// that it has already seen the opening.

import 'package:achrona/globe/progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a first visit has cleared nothing and not seen the opening', () async {
    final p = await Progress.load();
    expect(p.cleared, isEmpty);
    expect(p.seenOpening, isFalse);
  });

  test('clears and the opening survive to the next visit', () async {
    final p = await Progress.load();
    await p.clear('I · THE SEALED GATE');
    await p.clear('Example · The Rift Bridge');
    await p.sawOpening();

    final next = await Progress.load();
    expect(next.cleared,
        {'I · THE SEALED GATE', 'Example · The Rift Bridge'});
    expect(next.seenOpening, isTrue);
  });

  test('levels are remembered by name, not by their place in the list', () async {
    // Team levels come and go on the day; an index would tick the wrong one.
    final p = await Progress.load();
    await p.clear('Example · The Needle');
    final names = ['I · THE SEALED GATE', 'Example · The Needle'];
    expect(p.clearedIndices(names), {1});
    expect(p.clearedIndices(names.reversed.toList()), {0});
  });
}
