// The strobe cap is a locked accessibility requirement (≤3 flashes/sec), and
// the JS it was ported from had its own unit test. This is that test.
import 'package:achrona/globe/flare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first heal fires immediately, with no artificial latency', () {
    final started = <String>[];
    FlareQueue<String>(onStart: (item, _) => started.add(item))
      ..enqueue('a')
      ..pump(Duration.zero);
    expect(started, ['a']);
  });

  test('never exceeds 3 flashes/sec, and never drops a heal', () {
    final started = <String>[];
    final q = FlareQueue<String>(onStart: (item, _) => started.add(item));
    for (final id in ['a', 'b', 'c']) {
      q.enqueue(id);
    }

    q.pump(Duration.zero);
    expect(started, ['a'], reason: 'one flare starts per pump at most');

    // 333ms is inside the cap: nothing new may start.
    q.pump(const Duration(milliseconds: 333));
    expect(started, ['a']);
    expect(q.pending, 2, reason: 'queued heals are spaced, never dropped');

    q.pump(const Duration(milliseconds: 334));
    q.pump(const Duration(milliseconds: 668));
    expect(started, ['a', 'b', 'c']);
    expect(q.pending, 0);
  });

  test('envelope peaks at the end of the attack and decays to zero', () {
    expect(flareEnvelope(Duration.zero), 0.0);
    expect(flareEnvelope(const Duration(milliseconds: 120)), closeTo(1.0, 1e-9));
    expect(flareEnvelope(const Duration(milliseconds: 60)), closeTo(0.5, 1e-9));
    expect(flareEnvelope(const Duration(milliseconds: 1300)), 0.0);
    expect(flareEnvelope(const Duration(milliseconds: 700)), lessThan(1.0));
  });
}
