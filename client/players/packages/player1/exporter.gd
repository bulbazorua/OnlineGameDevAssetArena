extends "res://characters/import/character_module_exporter.gd"

const Importer = preload("./importer.gd")
const ROLE_CLIPS := {
	"idle": "trainer_idle", "walk": "trainer_walk", "run": "trainer_run",
	"advise": "trainer_advise", "hurt": "trainer_hurt", "cheer": "trainer_cheer",
	"surprised": "trainer_surprised", "disappointed": "trainer_disappointed",
}


func export_character(context: Dictionary) -> CharacterExports:
	var path: String = context.module_root.path_join("definition.json")
	var authored = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not authored is Dictionary or authored.get("key") != "player1" or not authored.get("display_name") is String:
		context.sources.fail("player1_definition", path, "Invalid Player1 identity")
		return null
	var result := CharacterExports.new()
	result.module_key = "player1"
	result.contract_id = "player.trainer"
	result.contract_version = "1.0.0-draft.1"
	result.export_api_version = "0.1.0"
	result.gameplay_definition = {"identity": {"key": "player1", "display_name": authored.display_name},
		"gameplay_size": authored.get("gameplay_size"), "footprint_radius_units": authored.get("footprint_radius_units")}
	result.ai = {"mode": "player_only"}
	result.art = Importer.new().import_assets(context)
	if result.art == null: return result
	# Front/three-quarter source poses reused explicitly; this pack has no back views.
	for role: String in ROLE_CLIPS:
		for facing in ["north", "north_east", "east", "south_east", "south", "south_west", "west", "north_west"]:
			result.art.bindings.append({"role": role, "facing": facing, "variant": "default",
				"kind": "clip", "clip": ROLE_CLIPS[role], "flip_h": "west" in facing})
	return result
