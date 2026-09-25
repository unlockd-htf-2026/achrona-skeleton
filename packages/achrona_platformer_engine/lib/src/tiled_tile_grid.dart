import 'tile_grid.dart';

/// [TileGrid] backed by a Tiled JSON map (the format Phaser/Tiled export and
/// `flame_tiled` renders). Reads one tile layer as collision: any non-zero gid
/// is solid unless its gid is listed in [oneWayGids].
///
/// This lets the Warped City `assets/maps/map.json` drive the engine's collision
/// while `flame_tiled` handles the visuals from the same file — no level bytes
/// need to be extracted from any ROM.
class TiledTileGrid implements TileGrid {
  TiledTileGrid({
    required this.tileSize,
    required this.cols,
    required this.rows,
    required List<int> gids,
    Set<int> oneWayGids = const {},
  })  : _gids = gids,
        _oneWay = oneWayGids;

  /// Parse a decoded Tiled JSON map. [collisionLayer] is matched by name; if
  /// absent, the first tile layer is used. Flipped-tile flag bits in gids are
  /// masked off so solidity is read correctly.
  factory TiledTileGrid.fromTiledJson(
    Map<String, dynamic> json, {
    String? collisionLayer,
    Set<int> oneWayGids = const {},
  }) {
    final tileSize = (json['tilewidth'] as num).toInt();
    final layers = (json['layers'] as List).cast<Map<String, dynamic>>();
    final tileLayers =
        layers.where((l) => l['type'] == 'tilelayer').toList(growable: false);
    if (tileLayers.isEmpty) {
      throw ArgumentError('Tiled map has no tile layers');
    }
    final layer = collisionLayer == null
        ? tileLayers.first
        : tileLayers.firstWhere(
            (l) => l['name'] == collisionLayer,
            orElse: () => throw ArgumentError(
                'No tile layer named "$collisionLayer"'),
          );

    const flipFlags = 0x80000000 | 0x40000000 | 0x20000000;
    final raw = (layer['data'] as List).cast<num>();
    final gids = [for (final g in raw) g.toInt() & ~flipFlags];

    return TiledTileGrid(
      tileSize: tileSize,
      cols: (layer['width'] as num).toInt(),
      rows: (layer['height'] as num).toInt(),
      gids: gids,
      oneWayGids: oneWayGids,
    );
  }

  @override
  final int tileSize;
  final int cols;
  final int rows;
  final List<int> _gids;
  final Set<int> _oneWay;

  @override
  TileSolidity solidityAt(int col, int row) {
    if (row < 0 || row >= rows) return TileSolidity.empty; // fall off bottom/top
    if (col < 0 || col >= cols) return TileSolidity.solid; // walled sides
    final gid = _gids[row * cols + col];
    if (gid == 0) return TileSolidity.empty;
    if (_oneWay.contains(gid)) return TileSolidity.oneWayPlatform;
    return TileSolidity.solid;
  }
}
