extends "res://characters/import/character_module_exporter.gd"

const Importer = preload("./importer.gd")


func export_character(context: Dictionary) -> CharacterExports:
	var result := CharacterExports.new()
	result.module_key = "reference16"
	result.contract_id = "character.basic_combat"
	result.contract_version = "1.0.0-draft.1"
	result.export_api_version = "0.1.0"
	result.gameplay_definition = {"gameplay_size": 1.0, "footprint_radius_units": 0.375}
	result.ai = {"mode": "player_only"}
	result.art = Importer.new().import_assets(context)
	if result.art == null: return result
	# This module owns this mapping. The coordinator never reads these names.
	var mapping := {"idle": "rest", "walk": "stride", "hurt": "flinch", "attack": "swing", "death": "fallen"}
	for role: String in mapping:
		for facing in ["north", "north_east", "east", "south_east", "south", "south_west", "west", "north_west"]:
			result.art.bindings.append({"role": role, "facing": facing, "variant": "primary" if role == "attack" else "default", "kind": "clip", "clip": mapping[role], "flip_h": "west" in facing})
	return result
