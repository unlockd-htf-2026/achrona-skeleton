/// Achrona palette, ported verbatim from `globe/src/main.js` + `regions.js`.
///
/// One conversion the JS never needed: flutter_scene's color factors are
/// **linear** RGBA, while the JS constants are sRGB hex. [srgb] does that
/// conversion — skipping it is why ported colors come out washed and pale.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

const int kBgVoid = 0xFF050410;

/// Desync corruption — the FX accent (emissive/atmosphere rollup), never a base fill.
const int kNeon = 0xFFB14DFF;

/// Clean / Purist — reserved for the heal flare and drained residual.
const int kCyan = 0xFF2BE2FF;

/// The pack's muddy warm-dark ground tone (sampled from `bg_far.png`).
const int kPackDark = 0xFF1C1218;

/// The rock the continents hang from: cold dark stone that the core's violet
/// light picks out. Knob.
const int kRock = 0xFF3A3346;

/// Unlocked but still corrupted land: a muted, bruised violet. Full neon
/// read as a glaring plate up close (the land is unlit). Knob.
const int kCorruptLand = 0xFF6B4A86;

/// Healed land: warm living earth, a little richer than [kDormant] (locked
/// land also carries a padlock). Knob.
const int kHealedLand = 0xFF8A6A4C;

/// Inert locked-land: dormant, but present enough for the neon padlock to read.
///
/// **Lifted from the JS `#372E30`.** globe.gl renders its hex polygons with a
/// LIT material, so that hex arrives on screen carrying the scene's light. Ours
/// are [UnlitMaterial] — chosen so a region's state colour is exact from every
/// angle instead of half the world state being swallowed by the planet's
/// terminator — which means the raw value goes straight through, linearises to
/// ~0.03, and ACES crushes it to black against a lit planet. This is that same
/// dormant warm-dark tone at the luminance the lit original actually lands on.
///
/// Art-direction knob: raise it if locked land should read more present, lower
/// it if it competes with the neon states.
const int kDormant = 0xFF574A4D;

/// sRGB 0xAARRGGBB → linear RGBA, with [alpha] overriding the packed alpha.
vm.Vector4 srgb(int argb, {double? alpha}) {
  double lin(int c) {
    final s = c / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return vm.Vector4(
    lin((argb >> 16) & 0xFF),
    lin((argb >> 8) & 0xFF),
    lin(argb & 0xFF),
    alpha ?? ((argb >> 24) & 0xFF) / 255.0,
  );
}

/// sRGB → linear with the RGB scaled by [gain], alpha left alone.
///
/// For anything meant to read as *light* rather than as a lit surface. The
/// colour constants carried over from the JS assume three.js's basic materials
/// with no tone mapping, where an `rgba()` reaches the screen at face value.
/// Here every colour passes through linear conversion and then ACES, which
/// compresses it — so a thin neon line over a lit globe washes out to a grey
/// wire. Gain above 1 puts it back where the original landed.
vm.Vector4 emissive(int argb, {required double alpha, double gain = 1}) {
  final c = srgb(argb);
  return vm.Vector4(c.x * gain, c.y * gain, c.z * gain, alpha);
}

/// Linear interpolate two packed sRGB colors, in sRGB space, as `lerpHex` did.
int lerpSrgb(int a, int b, double t) {
  final k = t.clamp(0.0, 1.0);
  int ch(int shift) {
    final ca = (a >> shift) & 0xFF;
    final cb = (b >> shift) & 0xFF;
    return (ca + (cb - ca) * k).round().clamp(0, 255);
  }

  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
