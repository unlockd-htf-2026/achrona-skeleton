// ⛔ DO NOT EDIT — engine public API
// This barrel file exposes the engine's public surface to the app layer.

export 'src/ai_seam/call_ai_tool.dart';
export 'src/fragments/augment_perk.dart';
export 'src/fragments/fragment_component.dart';
export 'src/fragments/fragment_manager.dart';
export 'src/fx/shader_controller.dart' show ShaderController;
export 'src/game/achrona_game.dart';
export 'src/hazards/hazard_component.dart';
export 'src/hazards/hazard_model.dart';
// Host-agnostic manifest surface (ARCD-03 / D-42). Deliberate, reviewed
// engine-API extension — NOT a student edit. Lets the Arcade and the Rung-4
// reference game share one source of truth for the team-game contract and the
// scripted-spawn renderer.
export 'src/hazards/scheduled_spawn.dart';
export 'src/manifest/team_game_manifest.dart';
export 'src/scoring/run_result.dart';
