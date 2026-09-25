/// **The Achrona kit API** — the one surface a team codes against.
///
/// Everything a hackathon challenge asks a student to write or change lives
/// behind these names, and the game reads only these. That is what lets the
/// challenges be carved and graded while the reference game keeps changing:
/// the game may move; this file may not, without a version bump of the kit.
///
/// Four tracks, four kinds of grading (`.planning/KIT-API.md` has the table):
///
/// * **Level design** — [LevelSpec]: graded as provably finishable.
/// * **3D world** — [kPx], [engineToWorld], [tileToWorld], [cameraEye],
///   [kHeroFacing], [kFoeFacing], [kHeroLean], [dressLevelLighting]: pure
///   maths graded by the sealed oracle, looks graded by scene snapshots.
/// * **Arsenal** — [WeaponKind]: data, graded by snapshot (does it sit in the
///   fist) and by the combat tests (does it reach).
/// * **Simulation** — not here: it is the frozen `achrona_platformer_engine`.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// ---------------------------------------------------------------------------
// Level design
// ---------------------------------------------------------------------------

/// Glyphs a row may contain: solid ground, a one-way (jump-through) ledge, air.
const String kSolid = '#', kOneWay = '=', kAir = ' ';

/// Object kinds a [LevelSpec.objects] entry may name. `enemy:<Species>` takes a
/// monster-pack species (`enemy:GhostSkull`, `enemy:Birb`, …).
const List<String> kObjectKinds = [
  'spawn', 'fragment', 'ability', 'gate', 'spikes', 'enemy:<Species>',
];

/// One level, as data.
///
/// The renderer, the physics, the dressing and the whole 1,600 lines below it
/// do not know which level they are drawing — they read this. A new level is a
/// row builder, a list of objects and two lines of script, which is what makes
/// level two a day's design work rather than a second game.
class LevelSpec {
  const LevelSpec({
    required this.title,
    required this.width,
    required this.height,
    required this.rows,
    required this.objects,
    required this.intro,
    this.next,
  });

  /// Shown on the completion screen.
  final String title;
  final int width;
  final int height;

  /// Built rather than stored, so a level can be written as the sequence it is
  /// (ground, pit, climb, chasm, vault) instead of a wall of glyphs.
  final List<String> Function() rows;

  /// `(kind, col, row)` — the empty cell the thing occupies; it stands on
  /// that cell's floor ([objectFeet]), i.e. on the ground at `row + 1`.
  final List<(String, int, int)> objects;

  /// The opening's two lines, in order.
  final (String, String) intro;

  /// Where the gate leads. Null ends the game.
  final LevelSpec? next;

  /// A level as it travels: a team publishes its level as this, and every
  /// game fetches it. [next] does not travel — a team level stands alone.
  Map<String, dynamic> toJson() => {
        'title': title,
        'width': width,
        'height': height,
        'rows': rows(),
        'objects': [
          for (final (kind, col, row) in objects) [kind, col, row],
        ],
        'intro': [intro.$1, intro.$2],
      };

  /// The inverse of [toJson]. Throws on a malformed level.
  factory LevelSpec.fromJson(Map<String, dynamic> json) {
    final rows = List<String>.unmodifiable(json['rows'] as List);
    final intro = (json['intro'] as List).cast<String>();
    return LevelSpec(
      title: json['title'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      rows: () => rows,
      objects: [
        for (final o in (json['objects'] as List).cast<List>())
          (o[0] as String, o[1] as int, o[2] as int),
      ],
      intro: (intro[0], intro[1]),
    );
  }
}

// ---------------------------------------------------------------------------
// 3D world — where the 2D simulation lands in the 3D scene
// ---------------------------------------------------------------------------

/// World units per engine pixel. One 16-px tile is one world unit.
const double kPx = 1 / 16;

/// An engine point (pixels, **y down**, origin top-left) in world space
/// (units, **y up**, origin bottom-left). [rows] is the level's height in
/// tiles; the flip is why it is needed.
vm.Vector2 engineToWorld(double x, double y, int rows) =>
    vm.Vector2(x * kPx, (rows * 16 - y) * kPx);

/// The world position of tile ([col], [row])'s top-left corner. The kit's
/// models are centred on their origin: a model *of* a tile goes at the tile's
/// centre, half a unit right of this.
vm.Vector2 tileToWorld(int col, int row, int rows) =>
    engineToWorld(col * 16.0, row * 16.0, rows);

/// Where an object named at cell ([col], [row]) in [LevelSpec.objects] puts
/// its feet.
///
/// CHALLENGE build-01: monsters, pickups and the gate hover, and sit beside
/// their hitboxes.
vm.Vector2 objectFeet(int col, int row, int rows) =>
    tileToWorld(col, row, rows);

/// The side-on camera rig: fixed pitch and distance, no orbit.
const double kCameraPitch = 0.10;
const double kCameraDistance = 11;

/// Where the eye sits for a camera looking at [target].
///
/// CHALLENGE base-02: the eye is on the wrong side of the play plane.
vm.Vector3 cameraEye(vm.Vector3 target) =>
    target +
    vm.Vector3(
      0,
      math.sin(kCameraPitch) * kCameraDistance,
      math.cos(kCameraPitch) * kCameraDistance,
    );

/// Yaw that points a model along screen-right, in quarter turns.
///
/// CHALLENGE base-03: nobody has set these yet.
const int kHeroFacing = 0;
const int kFoeFacing = 0;

/// How far the hero turns toward the lens, in degrees.
///
/// CHALLENGE build-02: in pure profile his sword arm is on the far side.
const double kHeroLean = 0;

/// Quarter turns to radians.
double quarterTurns(int q) => q * math.pi / 2;

/// The level's key light and post stack. Emissive dressing must stay under
/// [EnvironmentSettings.bloomThreshold] or every ledge becomes a strip light.
void dressLevelLighting(Scene scene) {
  scene.directionalLight = DirectionalLight(
    direction: vm.Vector3(-0.35, -1.0, -0.55),
    color: vm.Vector3(0.55, 0.62, 1.0),
    intensity: 0.85,
    // Shadows ground the hero and the monsters on the stone. The level is
    // flagged `shadowStatic` by its builder, so only what moves is re-drawn.
    castsShadow: true,
    // One cascade to just past the fog. The side-on camera sees nothing
    // nearer than ~9 units or past ~18, so the default four cascades spent
    // two on empty air in front of the lens — and the small near ones are
    // what re-render most: the static shadow cache only reuses a cascade
    // while the camera stays inside 15% of its radius, so a running camera
    // was redrawing the whole level into the shadow map every few frames.
    shadowCascadeCount: 1,
    shadowMaxDistance: 20,
  );
  scene.environmentSettings = EnvironmentSettings(
    toneMapping: ToneMappingMode.aces,
    exposure: 0.85,
    colorGradingEnabled: true,
    saturation: 1.12,
    contrast: 1.16,
    temperature: -0.1,
    bloomEnabled: true,
    bloomThreshold: 0.45,
    bloomIntensity: 0.55,
    bloomScatter: 0.85,
    vignetteEnabled: true,
    vignetteIntensity: 0.45,
    // Contact darkening where kit pieces meet — floor into wall, prop onto
    // ground — which flat kit lighting otherwise leaves looking pasted on.
    ambientOcclusionEnabled: true,
    ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
    ambientOcclusionRadius: 0.5,
    ambientOcclusionIntensity: 1.0,
    // Depth: the play plane sits ~11 units from the eye and the backdrop
    // runs to ~14, so fog that starts just behind the plane fades only the
    // back walls — separation, without dimming what you are playing on.
    fogEnabled: true,
    fogMode: FogMode.linear,
    fogColor: vm.Vector3(0.025, 0.025, 0.045),
    fogStart: 11.5,
    fogEnd: 18,
    fogMaxOpacity: 0.6,
  );
}

// ---------------------------------------------------------------------------
// Heroes
// ---------------------------------------------------------------------------

/// What sets a hero apart in play, beyond their weapon and hearts.
///
/// Movement is the same for every hero, on purpose: each level is proven
/// finishable (`level_reach_test`) with one jump and one run speed, and a
/// hero who ran slower or jumped lower could strand a player in a level that
/// is "proven" finishable.
enum HeroAbility {
  heavyBlade('HEAVY BLADE',
      'Every swing lands two damage — most foes fall to one — and reaches further.'),
  quickDraw('QUICK DRAW', 'Fires half again as fast.'),
  piercingCharge(
      'PIERCING CHARGE', 'Her charge passes through every foe in its path.'),
  voidStep('VOID STEP', 'Has the dash from the very first step.');

  const HeroAbility(this.label, this.description);

  /// Shown in the hero picker.
  final String label, description;
}

/// A playable character: a Quaternius Modular Character Outfit worn over a
/// Universal Base Character (both CC0), all on the Universal Animation Library
/// rig — so every one plays every clip the game drives and holds every weapon
/// by the same bones. The outfits carry no head: the base body supplies the
/// face (and eyes, eyebrows), and [hair] tops it where no hood does.
///
/// Each fights their own way: their own [weapon], [hearts] and [ability].
class HeroKind {
  const HeroKind(
    this.name,
    this.outfit,
    this.body, {
    this.hair,
    required this.weapon,
    required this.hearts,
    required this.ability,
  });

  /// Shown on the selector.
  final String name;

  /// `.gltf` files under `assets/models/ranger/`, worn together and animated
  /// by the same clip.
  final String outfit;
  final String body;
  final String? hair;

  /// The [WeaponKind.label] this hero fights with — theirs alone.
  final String weapon;

  /// Hit points: the engine's `maxHp`.
  final int hearts;

  final HeroAbility ability;

  List<String> get parts => [body, outfit, ?hair];

  /// Damage per hit landed on a foe.
  int get damage => ability == HeroAbility.heavyBlade ? 2 : 1;

  /// How far [w] reaches in this hero's hands, in engine px.
  double reach(WeaponKind w) =>
      ability == HeroAbility.heavyBlade ? w.reach * 1.2 : w.reach;

  /// How fast this hero plays [w]'s attack clip.
  double attackSpeed(WeaponKind w) =>
      ability == HeroAbility.quickDraw ? w.attackSpeed * 1.5 : w.attackSpeed;

  /// Whether this hero's bolts carry on through every foe they hit.
  bool get pierces => ability == HeroAbility.piercingCharge;

  /// Whether this hero has the dash before the Desync core grants it.
  bool get dashesFromStart => ability == HeroAbility.voidStep;
}

const String _male = 'Superhero_Male_Head.gltf';
const String _female = 'Superhero_Female_Head.gltf';

/// Squishy, at range: the fewest hearts, the fastest bow.
const HeroKind kRanger = HeroKind('RANGER', 'Male_Ranger.gltf', _male,
    weapon: 'bow', hearts: 2, ability: HeroAbility.quickDraw);

const List<HeroKind> kHeroes = [
  kRanger,
  HeroKind('HUNTRESS', 'Female_Ranger.gltf', _female,
      weapon: 'focus', hearts: 3, ability: HeroAbility.piercingCharge),
  // Beefy: the sword, and the most hearts to stand in reach with.
  HeroKind('SQUIRE', 'Male_Peasant.gltf', _male,
      hair: 'Hair_SimpleParted.gltf',
      weapon: 'sword',
      hearts: 5,
      ability: HeroAbility.heavyBlade),
  HeroKind('WANDERER', 'Female_Peasant.gltf', _female,
      hair: 'Hair_Long.gltf',
      weapon: 'fists',
      hearts: 3,
      ability: HeroAbility.voidStep),
];

// ---------------------------------------------------------------------------
// Arsenal
// ---------------------------------------------------------------------------

/// What the hero is holding, and what that changes.
///
/// The animation library already ships four complete verbs — sword, spell,
/// pistol and fists — so a weapon is a prop, a pair of clips and a rule, not a
/// new animation. The props are Quaternius' CC0 Medieval Weapons Pack
/// (`assets/weapons/LICENSE.txt`): a sword, a spear carried as the focus
/// staff, and a bow held in the pistol clips' outstretched arm.
class WeaponKind {
  const WeaponKind({
    required this.label,
    required this.asset,
    required this.idle,
    required this.attack,
    required this.reach,
    this.ranged = false,
    this.boltColour,
    this.modelAxis = (0.0, 1.0, 0.0),
    this.holdPoint = (0.0, 0.0, 0.0),
    this.pointAxis,
    this.hand = 'hand_r',
    this.upright = false,
    this.scale = (1.0, 1.0, 1.0),
    this.boltSpeed = 4.4,
    this.boltHits = 1,
    this.boltRadius = 0.14,
    this.attackSpeed = 1,
    this.offhand,
  });

  final String label;

  /// The prop in his hand. Null is bare hands, which is a real option: the
  /// library has Punch_Jab and Punch_Cross and they need nothing.
  final String? asset;
  final String idle;
  final String attack;

  /// Melee reach in engine pixels, or how far in front a bolt is born.
  final double reach;
  final bool ranged;
  final int? boltColour;

  /// Which way the prop points in **its own** space — the blade, the shaft,
  /// the limbs. Read off each model's bounding box: the Quaternius sword,
  /// spear and bow all run along their own +Y. The mount rotates this onto
  /// the hand's own grip axis, so nothing here is a quarter-turn guess.
  final (double, double, double) modelAxis;

  /// The point of the prop that goes **in the fist**, in its own space —
  /// which is the answer to "where does the holding start". Measured off each
  /// model by profiling its cross-section along its length:
  ///
  /// * **sword** (−0.82…+4.63): pommel at −0.82, grip up to ~+0.5,
  ///   cross-guard at +0.54…+0.82 (the widest ring), blade to the tip. The
  ///   hand goes on the grip at **+0.2**, just under the guard.
  /// * **spear** (−2.16…+7.56): thin shaft to ~+4.2, head from +4.6. Held
  ///   low on the shaft at **+0.6**, not by the butt cap.
  /// * **bow** (±2.72 tall): the riser is at the origin, so the fist takes it
  ///   there, at **(0.03, 0, 0)**.
  final (double, double, double) holdPoint;

  /// Scale per model axis, against the hero's 1.869 units. Not uniform,
  /// because a kit shaft is modelled thick enough to read on its own: scaling
  /// it long enough to be a staff also makes it thick enough to swallow his
  /// fist, so the length and the girth get different numbers.
  final (double, double, double) scale;

  /// Which way the prop's business end points, in its own space — where a
  /// bow's arrow flies. When set, the mount rolls the prop about the handle until this
  /// aims where the fist points, instead of leaving it to the `roll` control.
  final (double, double, double)? pointAxis;

  /// Which fist holds it. Measured off the clips, not assumed: `Sword_Attack`
  /// moves the right arm three to ten times more than the left, but
  /// `Idle_Torch_Loop` poses **only the left** (`upperarm_l` 0.64,
  /// `lowerarm_l` 0.57, right arm byte-identical to the plain idle) and the
  /// spell idle leans the same way (0.71 left against 0.09 right). A prop in
  /// the hand the clip does not animate is a prop beside a slack arm — which
  /// is exactly what a staff in the right hand looked like.
  final String hand;

  /// Pose it in the **world**, whatever the arm is doing: the handle straight
  /// up, and — if it has a [pointAxis] — that pointing the way the hero faces.
  /// A sword follows the fist because a swing *is* the fist; a staff is
  /// carried and a carried staff stands up; a bow is aimed and an aimed bow
  /// points where you are going, not wherever a knuckle happens to face.
  /// Costs a per-frame counter-rotation against the animated hand.
  final bool upright;

  /// Bolt behaviour, for the ranged pair. Speed in engine px/frame, hits is
  /// how much of an enemy's two-hit health one shot takes.
  final double boltSpeed;
  final int boltHits;
  final double boltRadius;

  /// How fast the attack clip plays, and so how long the swing takes: the
  /// swing lasts the clip's length divided by this. A tuning knob, set by
  /// playing — `Sword_Attack` at real speed is ~92 frames, which felt slow.
  final double attackSpeed;

  /// A second prop for the other hand — the squire's shield. Only its mount
  /// fields ([asset], [hand], [modelAxis], [holdPoint], [pointAxis],
  /// [upright], [scale]) are read; it has no clips or rules of its own.
  final WeaponKind? offhand;
}
