// "Rate this level" on the clear screen: one tap on a star rates (a refusal
// is quiet), a later tap changes it, and skip makes it go away.

import 'package:achrona/level_one.dart' show RateLevel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host() => const MaterialApp(
    home: Scaffold(body: Center(child: RateLevel(levelTeamId: 'team-b'))));

void main() {
  testWidgets('one tap rates, and the stars can change', (t) async {
    await t.pumpWidget(_host());
    expect(find.text('RATE THIS LEVEL'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);

    await t.tap(find.byTooltip('4'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.text('THANKS — tap to change'), findsOneWidget);
    expect(find.text('skip'), findsNothing);

    await t.tap(find.byTooltip('2'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsNWidgets(2));
  });

  testWidgets('skip hides it', (t) async {
    await t.pumpWidget(_host());
    await t.tap(find.text('skip'));
    await t.pump();
    expect(find.text('RATE THIS LEVEL'), findsNothing);
  });
}
