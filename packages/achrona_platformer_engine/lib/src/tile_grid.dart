/// Tile solidity model, adapted in spirit from MZM `clipdata` — instead of the
/// GBA's packed clip values we expose a small enum the sim queries per tile.
enum TileSolidity {
  /// Passable.
  empty,

  /// Blocks from every direction.
  solid,

  /// Blocks only when falling onto its top edge (jump-through platform).
  oneWayPlatform,
}

/// A grid of [TileSolidity]. Coordinates are in pixels; [tileSize] px per cell.
abstract class TileGrid {
  int get tileSize;

  /// Solidity at a tile cell. Out-of-bounds is the caller's choice; the default
  /// demo grid treats out-of-range columns as solid walls and below-floor as
  /// empty (so the player can fall off the bottom, but not the sides).
  TileSolidity solidityAt(int col, int row);
}

/// String-map grid for tests/prototyping. `'#'` solid, `'='` one-way, else empty.
/// Rows are equal length. Out-of-bounds left/right is solid; top/bottom empty.
class StringTileGrid implements TileGrid {
  StringTileGrid(this.rows, {this.tileSize = 16});

  final List<String> rows;
  @override
  final int tileSize;

  int get cols => rows.isEmpty ? 0 : rows.first.length;

  @override
  TileSolidity solidityAt(int col, int row) {
    if (row < 0 || row >= rows.length) return TileSolidity.empty;
    if (col < 0 || col >= cols) return TileSolidity.solid;
    switch (rows[row][col]) {
      case '#':
        return TileSolidity.solid;
      case '=':
        return TileSolidity.oneWayPlatform;
      default:
        return TileSolidity.empty;
    }
  }
}
