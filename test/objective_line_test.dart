// The one line at the top of a level. A playtest found two things it never
// said: which level you are in (II looks a lot like I), and that the core
// just gave you a double jump.
import 'package:achrona/level_one.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names the level in front of the objective', () {
    expect(objectiveLine(name: 'II · THE DESCENT', total: 3, found: 1),
        'II · THE DESCENT — FIND 3 DESYNC FRAGMENTS · 1 found');
  });

  test('without a name it is just the objective', () {
    expect(objectiveLine(total: 3, found: 0),
        'FIND 3 DESYNC FRAGMENTS · 0 found');
  });

  test('an open gate says so', () {
    expect(objectiveLine(name: 'I · THE SEALED GATE', total: 3, found: 3,
            gateLive: true),
        'I · THE SEALED GATE — THE GATE IS OPEN — reach it');
  });

  test('the core announces what it unlocked, then the objective returns', () {
    expect(objectiveLine(total: 3, found: 1, unlocked: true, dashIsNew: true),
        'DOUBLE JUMP + DASH UNLOCKED — jump again in mid-air · Shift to dash');
    // Void Step: she dashed from the start, so only the jump is news.
    expect(objectiveLine(total: 3, found: 1, unlocked: true, dashIsNew: false),
        'DOUBLE JUMP UNLOCKED — jump again in mid-air');
  });
}
