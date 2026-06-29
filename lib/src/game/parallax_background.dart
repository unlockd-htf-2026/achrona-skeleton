import 'package:achrona_engine/src/game/achrona_game.dart';
import 'package:flame/components.dart';
import 'package:flame/parallax.dart';
import 'package:flutter/painting.dart' show Alignment;

/// A scrolling parallax background using real CC-BY sprite layers.
///
/// Loads three image layers from the app's asset bundle:
///   - bg_far.png  — opaque sky (slowest)
///   - bg_mid.png  — mid layer with spires (alpha)
///   - bg_near.png — near ground strip (alpha, fastest)
///
/// Rendered at [priority] -1 so it sits behind all game objects.
///
/// FIXED-SIZE WORLD COMPONENT (do not make this fullscreen):
/// [ParallaxComponent] defaults to `isFullscreen = true` whenever it is
/// constructed without a `size`. When fullscreen, its [onGameResize] override
/// snaps the component's size (and the inner [Parallax]) to the RAW CANVAS
/// size in pixels every frame the window changes — decoupling the city from
/// the camera zoom that scales the player/hazards, and (because the band is
/// bottom-anchored at the world origin while the layers fill the now-canvas-
/// tall band) pushing the buildings far BELOW the visible region so only a
/// thin sliver of rooftops shows on tall/portrait windows.
///
/// We pass an explicit fixed [size] to the super constructor, which sets
/// `isFullscreen = false`, so the band stays a fixed world rect that scales
/// uniformly with every other world object under the single camera zoom.
/// The band is bottom-anchored at the ground line (`y = groundLine`) and
/// extends UPWARD, so on tall/portrait windows the (taller-than-360) band
/// fills more of the revealed world height with skyline instead of sky.
///
/// Scroll speed is read from [AchronaGame.currentScrollSpeed] each frame so the
/// background naturally accelerates with the world (D-02).
class ParallaxBackground extends ParallaxComponent<AchronaGame> {
  ParallaxBackground({required this.bandSize, required this.groundLine})
      : super(
          priority: -1,
          // Explicit size → isFullscreen=false → onGameResize will NOT clobber
          // this to the canvas size. The band is a FIXED world rect.
          size: bandSize.clone(),
          // Bottom-anchored at the ground line so the city sits on the ground
          // and the band extends upward into the revealed sky on tall windows.
          position: Vector2(0, groundLine),
          anchor: Anchor.bottomLeft,
        );

  /// Fixed world-space size of the parallax band (px). Taller than the 360
  /// gameplay band so the skyline reaches up into tall/portrait viewports.
  final Vector2 bandSize;

  /// World-y of the ground line the band's bottom is pinned to.
  final double groundLine;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    parallax = await game.loadParallax(
      [
        ParallaxImageData('bg_far.png'),
        ParallaxImageData('bg_mid.png'),
        ParallaxImageData('bg_near.png'),
      ],
      baseVelocity: Vector2(game.currentScrollSpeed * 0.3, 0),
      velocityMultiplierDelta: Vector2(1.8, 0),
      // Bottom-anchor each layer so the city silhouette sits on the band's
      // bottom edge (the ground line) and the transparent sky tops face up.
      alignment: Alignment.bottomCenter,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Dynamically adjust base velocity as the game speeds up (D-02).
    parallax?.baseVelocity.x = game.currentScrollSpeed * 0.3;
  }
}
