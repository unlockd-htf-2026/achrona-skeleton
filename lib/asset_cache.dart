/// Asset bytes, fetched once per session and in parallel.
///
/// On the web every `rootBundle.load` is an HTTP round trip, and the level
/// used to make them one after another — each kit piece, each monster (per
/// monster, not per species), each hero part and texture. Deployed, that is
/// seconds of latency before any parsing. Everything now goes through
/// [assetBytes]: the first ask starts the fetch, every later ask (the next
/// level, the picker, a restart) gets the same bytes, and [prefetch] starts a
/// whole list at once so the waiting overlaps.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';

final Map<String, Future<Uint8List>> _bytes = {};

/// [path]'s bytes; fetched on the first ask, shared after.
Future<Uint8List> assetBytes(String path) =>
    _bytes[path] ??= rootBundle.load(path).then((b) => b.buffer.asUint8List());

/// A fresh node parsed from the `.glb` at [path].
Future<Node> glb(String path) async =>
    Node.fromGlbBytes(await assetBytes(path));

/// A fresh node parsed from the `.gltf` at [path], its buffers and textures
/// resolved beside it.
Future<Node> gltf(String path) async {
  final dir = path.substring(0, path.lastIndexOf('/') + 1);
  return Node.fromGltfBytes(
    await assetBytes(path),
    resolveUri: (uri) => assetBytes('$dir$uri'),
  );
}

/// Start fetching every one of [paths] at once. A `.gltf` also starts the
/// buffers and textures it names, so they do not wait for the parse.
Future<void> prefetch(Iterable<String> paths) => Future.wait([
  for (final p in paths)
    if (p.endsWith('.gltf')) _withDependencies(p) else assetBytes(p),
]);

Future<void> _withDependencies(String path) async {
  final dir = path.substring(0, path.lastIndexOf('/') + 1);
  final json = jsonDecode(utf8.decode(await assetBytes(path))) as Map;
  await Future.wait([
    for (final key in const ['buffers', 'images'])
      for (final e in (json[key] as List? ?? const []).cast<Map>())
        if (e['uri'] is String && !(e['uri'] as String).startsWith('data:'))
          assetBytes('$dir${e['uri']}'),
  ]);
}
