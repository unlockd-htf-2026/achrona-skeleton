// web_gl_shader_view_stub.dart — Non-web stub for WebGlShaderView.
//
// Selected by the conditional import in web_gl_shader_view.dart on any
// platform that is NOT Flutter web (iOS, Android, macOS, Windows, Linux).
//
// All symbols match the web interface so ShaderController can reference
// WebGlShaderView uniformly on all platforms — but on native builds these
// are no-ops that never get invoked (ShaderController only enters
// _WebMode.webgl on kIsWeb builds).

import 'package:flutter/widgets.dart';

/// Synchronous WebGL2 capability probe — always `false` on non-web builds.
///
/// ShaderController never calls this on native (it checks `kIsWeb` first),
/// but the symbol must exist so the conditional import type-checks.
bool probeWebGl2Supported() => false;

/// No-op stub of the WebGL2 shader overlay for non-web builds.
///
/// ShaderController on native never reaches the webgl branch so this
/// widget's [build] is never called.  It satisfies the type system.
class WebGlShaderView extends StatelessWidget {
  const WebGlShaderView({
    required this.intensity,
    super.key,
  });

  /// Effect intensity — accepted but ignored on non-web.
  final double intensity;

  /// Always false on non-web builds.
  static bool failed = false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
