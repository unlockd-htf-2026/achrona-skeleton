# Challenges

Run one with `./challenge <id>`; `./challenge all` runs them all.
Base is the floor every team reaches; Build and Online go further.
Needs Flutter 3.47 (`.fvmrc`): with fvm, `fvm flutter ...`.
Do them in any order.

| id | track | challenge |
|---|---|---|
| base-01 | Base | Design your own level |
| base-02 | Base | Put the camera on the right side |
| base-03 | Base | Make the models face where they walk |
| build-01 | Build | Stand everything on the floor |
| build-02 | Build | Show the sword arm |
| online-01 | Online | Send your run to the world |

## base-01 — Design your own level (Base)

Done when `./challenge base-01` is green.

1. Open `lib/my_level.dart`. `buildMyLevelRows` draws the level as rows of
   text: `#` solid ground, `=` a ledge you can jump up through, space is air.
2. Place things in `objects` as `(kind, column, row)` — the empty cell they
   stand in. Kinds: `spawn`, `fragment` (you need three), `ability` (the
   Desync core: it gives the double jump), `gate`, `spikes`,
   `enemy:<Species>` (Birb, Cactoro, Ghost, GhostSkull, Goleling, Mushnub,
   OrcEnemy, Armabee).
3. Set `kMyConcept` to your team's concept card (all twelve are in
   `lib/concepts.dart`): a place to theme your level on, and one mechanic it
   must be built around — a descent, a rift, a horde, a tower…
4. The rules the test checks: the level can be finished; the core can be
   reached with single jumps; the gate can NOT be reached without the core;
   and it meets your card's rule.
Concept — measured off the real physics: a single jump clears a 3-tile gap
and climbs 3 rows; a double jump clears 8 tiles. Play it from the globe:
LEVEL ▾ → IV · YOUR LEVEL.

## base-02 — Put the camera on the right side (Base)

Done when `./challenge base-02` is green.

1. Run the game and press right: the hero walks left, and every level is
   drawn back to front.
2. Open `lib/kit.dart` and find `cameraEye`. It places the eye
   `kCameraDistance` from the target, tilted up by `kCameraPitch`.
3. Work out which side of the play plane (the z = 0 plane the game is played
   on) the eye must sit on for world +X to appear on the right of the
   screen, and fix it.
Concept: a camera's "right" is cross(up, forward). Flip forward and right
flips with it — which mirrors the whole picture.

## base-03 — Make the models face where they walk (Base)

Done when `./challenge base-03` is green.

1. Run the game: the hero and the monsters walk sideways, like crabs.
2. In `lib/kit.dart`, `kHeroFacing` and `kFoeFacing` turn the models by
   quarter turns (90° each) about the up axis.
3. The hero's model pack was drawn looking down +Z; the monsters' pack looking
   down −Z. Screen-right is +X. How many quarter turns bring each onto +X?
Concept: every artist picks their own "forward". That is why one constant
cannot serve both packs.

## build-01 — Stand everything on the floor (Build)

Done when `./challenge build-01` is green.

Goal: every monster, fragment, spike and the gate stands on the ground, in
the middle of its tile — where the physics thinks it is.
Hints: objects are named by the empty cell they occupy; `tileToWorld` gives
a cell's top-left corner; the models are centred on their own origin.
Graded by a render of your level compared with the reference render.

## build-02 — Show the sword arm (Build)

Done when `./challenge build-02` is green.

Goal: see the swing. The attack is right-handed and the right arm is the
far one, so a pure side view hides it.
Hints: turn him a little toward the camera — which sign is "toward"? Every
3D side-scroller cheats like this; too far and he stops reading as side-on.

## online-01 — Send your run to the world (Online)

Done when `./challenge online-01` is green.

Goal: a finished run heals Achrona. `RunLink.submit` in
`lib/globe/run_link.dart` must ask the AI server for today's seed
(`GET /daily-seed`), then post the run (`POST /submit-score`, your team key
as a Bearer token, `mode: race`) and turn the answer into a `RunHeal`.
Hints: `runScore` already scores the run; `test/run_link_test.dart` shows
exactly what the server sends and expects.
