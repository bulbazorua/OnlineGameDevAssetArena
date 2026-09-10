class_name CharacterModuleExporter
extends RefCounted

const CharacterExports = preload("res://characters/import/character_exports.gd")


# Required module entry point. Only the module interprets its private files.
func export_character(_context: Dictionary) -> CharacterExports:
	return null
