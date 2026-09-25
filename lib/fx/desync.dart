/// The Desync glitch (`shaders/desync.frag`) as a flutter_scene `PostEffect`,
/// shared by the level and the globe so both show the same curse.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as gpu
    show loadShaderLibraryAsync, resolveShaderBundleKey;
import 'package:flutter_scene/scene.dart';

/// Adds the glitch to [scene], off until [setDesync] turns it up. Null when
/// the shader bundle did not load: callers play on without it.
Future<PostEffect?> addDesyncEffect(Scene scene) async {
  try {
    final lib = await gpu.loadShaderLibraryAsync(
      await gpu.resolveShaderBundleKey('desync',
          package: 'achrona'),
    );
    final shader = lib?['DesyncFragment'];
    if (shader == null) return null;
    final fx = PostEffect(
      fragmentShader: shader,
      insertion: PostInsertion.afterTonemap,
      useFrameInfo: true,
      enabled: false,
    );
    scene.postProcess.customEffects.add(fx);
    return fx;
  } catch (e) {
    debugPrint('desync effect unavailable: $e');
    return null;
  }
}

/// Glitch intensity, 0–1. Disabled outright at ~0 so a clean frame costs
/// nothing.
void setDesync(PostEffect? fx, double intensity) => fx
  ?..enabled = intensity > 0.001
  ..setUniformBlockFromFloats('DesyncInfo', [intensity, 0, 0, 0]);
