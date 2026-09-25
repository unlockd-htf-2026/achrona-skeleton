/// The globe's menus: the level dropdown, the card beside a level's
/// landmark, and the hero picker it opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show PerspectiveCamera, SceneView;

import '../hero_model.dart';
import '../kit.dart';
import 'palette.dart';

const _cyan = Color(kCyan);
const _neon = Color(kNeon);
const _panel = Color(0xE60A0818);

/// Who each hero is. Their weapon, hearts and ability are in the kit
/// (`HeroKind`); this is only who they are.
const Map<String, (String, String)> kHeroLore = {
  'RANGER': (
    'WAYSTONE WARDEN',
    'Walked the old roads before the world broke. Knows every gate the '
        'Desync sealed — and every way around one.',
  ),
  'HUNTRESS': (
    'SHARDTRACKER',
    'Follows the curse’s trail across the drifting shards. Quick on a '
        'ledge, quicker to be gone.',
  ),
  'SQUIRE': (
    'OATHBOUND',
    'Swore an oath to a knight who never came back from the breaking. '
        'Carries the oath — and the sword — anyway.',
  ),
  'WANDERER': (
    'VOIDWALKER',
    'Climbed up out of the dark between the shards. Nobody knows what she '
        'heard down there, and she isn’t telling.',
  ),
};

/// "LEVEL ▾": the level list, folded away until asked for.
class LevelDropdown extends StatelessWidget {
  const LevelDropdown({
    super.key,
    required this.levels,
    required this.level,
    required this.onLevel,
    this.cleared = const {},
  });

  final List<String> levels;

  /// Levels to tick. An icon, not a '✓' in the text: the bundled font has no
  /// such glyph, and web fetches a fallback font for it only on demand.
  final Set<int> cleared;
  final int level;
  final ValueChanged<int> onLevel;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        style: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(_panel),
          side: WidgetStatePropertyAll(BorderSide(color: _cyan, width: 0.6)),
        ),
        menuChildren: [
          for (final (i, name) in levels.indexed)
            MenuItemButton(
              onPressed: () => onLevel(i),
              leadingIcon: Icon(Icons.check,
                  size: 14,
                  color: cleared.contains(i) ? _cyan : Colors.transparent),
              style: MenuItemButton.styleFrom(
                foregroundColor: i == level ? _cyan : Colors.white70,
                textStyle: const TextStyle(fontSize: 12, letterSpacing: 2),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: Text(name),
            ),
        ],
        builder: (context, menu, _) => OutlinedButton.icon(
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.expand_more, size: 18),
          iconAlignment: IconAlignment.end,
          label: Text(levels[level]),
          style: OutlinedButton.styleFrom(
            foregroundColor: _cyan,
            backgroundColor: _panel,
            side: const BorderSide(color: _cyan),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            textStyle: const TextStyle(fontSize: 12, letterSpacing: 2),
          ),
        ),
      );
}

/// The card beside a level's landmark: its name, and the way in.
class LandmarkMenu extends StatelessWidget {
  const LandmarkMenu({super.key, required this.name, required this.onEnter});

  final String name;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _cyan.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(color: _cyan.withValues(alpha: 0.25), blurRadius: 18),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, letterSpacing: 2)),
            const SizedBox(width: 14),
            FilledButton.icon(
              onPressed: onEnter,
              icon: const Icon(Icons.login, size: 16),
              label: const Text('ENTER'),
              style: FilledButton.styleFrom(
                backgroundColor: _cyan,
                foregroundColor: const Color(kBgVoid),
                textStyle: const TextStyle(
                    fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

/// Choose who enters [level]: a live 3D preview beside their details.
/// Resolves to the chosen hero's index, or null if dismissed.
Future<int?> showHeroPicker(BuildContext context,
        {required String level, required int initial}) =>
    showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0xAA02010A),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, t, _, child) => FadeTransition(
        opacity: t,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0)
              .animate(CurvedAnimation(parent: t, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      pageBuilder: (context, _, _) =>
          _HeroPicker(level: level, initial: initial),
    );

/// What a hero fights with: hearts, weapon, and their ability.
class _Stats extends StatelessWidget {
  const _Stats(this.hero);

  final HeroKind hero;

  static const _weapons = {
    'sword': 'SWORD',
    'focus': 'FOCUS STAFF',
    'bow': 'BOW',
    'fists': 'BARE FISTS',
  };

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
        color: Colors.white54, fontSize: 10, letterSpacing: 3, height: 1.8);
    const value =
        TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 78, child: Text('HEARTS', style: label)),
            Text('♥' * hero.hearts,
                style: const TextStyle(
                    color: Color(0xFFFF5C8A), fontSize: 15, letterSpacing: 3)),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 78, child: Text('WEAPON', style: label)),
            Text(_weapons[hero.weapon] ?? hero.weapon.toUpperCase(),
                style: value),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 78, child: Text('ABILITY', style: label)),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '${hero.ability.label}  ',
                      style: value.copyWith(color: _cyan)),
                  TextSpan(
                      text: hero.ability.description,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.4)),
                ]),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroPicker extends StatefulWidget {
  const _HeroPicker({required this.level, required this.initial});

  final String level;
  final int initial;

  @override
  State<_HeroPicker> createState() => _HeroPickerState();
}

class _HeroPickerState extends State<_HeroPicker> {
  late int _hero = widget.initial;
  HeroStage? _stage;

  @override
  void initState() {
    super.initState();
    HeroStage.shared().then((s) {
      if (mounted) setState(() => _stage = s..show(_hero));
    });
  }

  void _pick(int i) {
    setState(() => _hero = i);
    _stage?.show(i);
  }

  @override
  Widget build(BuildContext context) {
    final hero = kHeroes[_hero];
    final (title, bio) = kHeroLore[hero.name] ?? ('', '');
    final stage = _stage;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 780,
          height: 500,
          decoration: BoxDecoration(
            color: const Color(0xF20A0818),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _neon.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(color: _neon.withValues(alpha: 0.3), blurRadius: 30),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // The preview: the hero idling on a turntable.
              SizedBox(
                width: 330,
                child: stage == null
                    ? const Center(child: CircularProgressIndicator())
                    : SceneView(
                        stage.scene,
                        camera: PerspectiveCamera(
                          position: HeroStage.eye,
                          target: HeroStage.target,
                          fovNear: 0.1,
                          fovFar: 30,
                        ),
                        onTick: (elapsed, dt) => stage.turn(dt),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 30, 34, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ENTERING  ${widget.level}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                              letterSpacing: 3)),
                      const SizedBox(height: 16),
                      Text(hero.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w300)),
                      const SizedBox(height: 6),
                      Text(title,
                          style: const TextStyle(
                              color: _neon, fontSize: 12, letterSpacing: 4)),
                      const SizedBox(height: 18),
                      Text(bio,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                              height: 1.55)),
                      const SizedBox(height: 16),
                      _Stats(hero),
                      const Spacer(),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (i, h) in kHeroes.indexed)
                            OutlinedButton(
                              onPressed: () => _pick(i),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    i == _hero ? const Color(kBgVoid) : _cyan,
                                backgroundColor:
                                    i == _hero ? _cyan : Colors.transparent,
                                side: const BorderSide(color: _cyan),
                                textStyle: const TextStyle(
                                    fontSize: 11, letterSpacing: 2),
                              ),
                              child: Text(h.name),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('BACK',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    letterSpacing: 3)),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(_hero),
                            style: FilledButton.styleFrom(
                              backgroundColor: _cyan,
                              foregroundColor: const Color(kBgVoid),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 34, vertical: 18),
                              textStyle: const TextStyle(
                                  fontSize: 15,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w600),
                            ),
                            child: const Text('BEGIN'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
