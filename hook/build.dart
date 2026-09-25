import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles the app's own shaders (the Desync post effect) into a shader bundle
/// under `flutter_scene_generated/`, trimmed to the backends the target uses.
/// Deliberately not `flutter_scene:init`'s hook: that also converts every .glb
/// under assets/, and the game loads its models as plain .glb.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildTargetShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/desync.shaderbundle.json',
    );
  });
}
