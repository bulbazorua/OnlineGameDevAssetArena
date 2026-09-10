extends "res://characters/import/character_module_exporter.gd"

const Importer = preload("./importer.gd")


func export_character(context: Dictionary) -> CharacterExports:
	var result := CharacterExports.new()
	result.module_key = "reference32"
	result.contract_id = "character.basic_combat"
	result.contract_version = "1.0.0-draft.1"
	result.export_api_version = "0.1.0"
	result.gameplay_definition = {"gameplay_size": 1.0, "footprint_radius_units": 0.375}
	result.ai = {"mode": "player_only"}
	result.art = Importer.new().import_assets(context)
	if result.art == null: return result
	var roles := ["idle", "walk", "hurt", "attack", "death"]
	for index in roles.size():
		var role: String = roles[index]
		for facing in ["north", "north_east", "east", "south_east", "south", "south_west", "west", "north_west"]:
			result.art.bindings.append({"role": role, "facing": facing, "variant": "primary" if role == "attack" else "default", "kind": "clip", "clip": "sheet_%d" % index, "flip_h": "west" in facing})
	return result
