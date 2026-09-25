// The example team levels in assets/team_levels/, read straight off disk
// (tests run in the package root) so the level rules can run over them.

import 'dart:convert';
import 'dart:io';

import 'package:achrona/team_levels.dart';

List<TeamLevel> exampleTeamLevels() {
  const dir = 'assets/team_levels';
  final files = (jsonDecode(File('$dir/index.json').readAsStringSync()) as List)
      .cast<String>();
  return [
    for (final f in files)
      TeamLevel.fromJson(
          jsonDecode(File('$dir/$f').readAsStringSync()) as Map<String, dynamic>),
  ];
}
