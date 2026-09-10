extends "res://characters/import/character_module_exporter.gd"

const Importer = preload("./importer.gd")


func export_character(context: Dictionary) -> CharacterExports:
	var path: String = context.module_root.path_join("definition.json")
	var authored = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not authored is Dictionary or authored.get("key") != "orc" or not authored.get("display_name") is String:
		context.sources.fail("orc_definition", path, "Invalid Orc identity")
		return null
	var result := CharacterExports.new()
	result.module_key = "orc"
	result.contract_id = "character.basic_combat"
	result.contract_version = "1.0.0-draft.1"
	result.export_api_version = "0.1.0"
	result.gameplay_definition = {"identity": {"key": "orc", "display_name": authored.display_name},
		"gameplay_size": authored.get("gameplay_size"), "footprint_radius_units": authored.get("footprint_radius_units")}
	result.ai = {"mode": "player_only"}
	result.art = Importer.new().import_assets(context)
	if result.art == null: return result
	var roles := {"idle": "orc_rest", "walk": "orc_walk", "hurt": "orc_hurt", "attack": "orc_axe", "death": "orc_fall"}
	for role: String in roles:
		for facing in ["north", "north_east", "east", "south_east", "south", "south_west", "west", "north_west"]:
			result.art.bindings.append({"role": role, "facing": facing, "variant": "primary" if role == "attack" else "default",
				"kind": "clip", "clip": roles[role], "flip_h": "west" in facing})
	return result
