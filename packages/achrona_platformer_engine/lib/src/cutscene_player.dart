/// One stage of a cutscene: hold for [duration] seconds, optionally show
/// [caption] text and fire [onEnter] when the stage begins. This mirrors MZM's
/// cutscene model (`src/cutscenes/*`): a `switch (stage)` that waits on a timer,
/// performs an action, then advances. Here [onEnter] is where you pan a parallax
/// layer, fade a sprite, shake, etc. — the engine stays render-agnostic.
class CutsceneStep {
  const CutsceneStep({required this.duration, this.caption, this.onEnter});

  final double duration;
  final String? caption;
  final void Function()? onEnter;
}

/// Pure-Dart timed-stage runner. Drive it from a game loop with [update]; read
/// [caption] for on-screen text and [isDone] to hand control back to gameplay.
/// No Flame import → unit-testable and identical on native/web.
class CutscenePlayer {
  CutscenePlayer(this.steps);

  final List<CutsceneStep> steps;

  int _index = 0;
  double _elapsed = 0;
  bool _started = false;
  bool _done = false;

  bool get isDone => _done;
  int get currentIndex => _index;

  /// Caption for the active stage (null when done or none set).
  String? get caption => _done || steps.isEmpty ? null : steps[_index].caption;

  void _enter(int i) => steps[i].onEnter?.call();

  /// Advance by [dt] seconds. Fires the first step's [onEnter] on first call.
  void update(double dt) {
    if (_done || steps.isEmpty) {
      _done = true;
      return;
    }
    if (!_started) {
      _started = true;
      _enter(0);
    }
    _elapsed += dt;
    // while-loop so a long dt can cross several short stages in one frame.
    while (!_done && _elapsed >= steps[_index].duration) {
      _elapsed -= steps[_index].duration;
      _index++;
      if (_index >= steps.length) {
        _done = true;
      } else {
        _enter(_index);
      }
    }
  }

  /// Skip to the end, still firing each remaining [onEnter] in order so any side
  /// effects (final positions, unlocks) are applied. Set [runRemaining] false to
  /// jump straight to done without firing them.
  void skip({bool runRemaining = true}) {
    if (_done) return;
    if (!_started) {
      _started = true;
      if (steps.isNotEmpty) _enter(0);
    }
    if (runRemaining) {
      for (var i = _index + 1; i < steps.length; i++) {
        _enter(i);
      }
    }
    _index = steps.length;
    _done = true;
  }
}
