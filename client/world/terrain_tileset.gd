class_name TerrainTileset
extends RefCounted

const ArenaCatalog = preload("res://content/arena_catalog.gd")
# Coordinates belong to presentation only. Sand reuses a ground tile with a lighter tint.
const VISUALS := {
	"grass": {"texture": "res://assets/kenney_tiny_town/tilemap_packed.png", "cells": [Vector2i(0, 0), Vector2i(1, 0)]},
	"ground": {"texture": "res://assets/kenney_tiny_town/tilemap_packed.png", "cells": [Vector2i(1, 2)]},
	"sand": {"texture": "res://assets/kenney_tiny_town/tilemap_packed.png", "cells": [Vector2i(1, 2)], "tint": Color(1.08, 1.18, 1.4)},
	"water": {"texture": "res://assets/kenney_tiny_battle/tilemap_packed.png", "cells": [Vector2i(1, 2)]},
	"stone": {"texture": "res://assets/kenney_tiny_town/tilemap_packed.png", "cells": [Vector2i(0, 4)]},
}
const NATIVE_TILE_SIZE := 16


static func validate(catalog: ArenaCatalog) -> String:
	for terrain in catalog.terrains:
		if not VISUALS.has(terrain.key):
			return "Missing terrain visual for '%s'." % terrain.key
		var visual: Dictionary = VISUALS[terrain.key]
		if not ResourceLoader.exists(visual.texture):
			return "Missing terrain texture: %s" % visual.texture
		var texture = load(visual.texture)
		if not texture is Texture2D:
			return "Invalid terrain texture: %s" % visual.texture
		for cell: Vector2i in visual.cells:
			if (cell.x + 1) * NATIVE_TILE_SIZE > texture.get_width() or (cell.y + 1) * NATIVE_TILE_SIZE > texture.get_height():
				return "Terrain tile is outside its source texture."
	return ""


static func build(catalog: ArenaCatalog) -> TileSet:
	var result := TileSet.new()
	result.tile_size = Vector2i(NATIVE_TILE_SIZE, NATIVE_TILE_SIZE)
	result.add_custom_data_layer()
	result.set_custom_data_layer_name(0, "terrain_id")
	result.set_custom_data_layer_type(0, TYPE_INT)
	result.add_custom_data_layer()
	result.set_custom_data_layer_name(1, "terrain_key")
	result.set_custom_data_layer_type(1, TYPE_STRING)
	result.add_custom_data_layer()
	result.set_custom_data_layer_name(2, "walkable")
	result.set_custom_data_layer_type(2, TYPE_BOOL)
	for terrain in catalog.terrains:
		var visual: Dictionary = VISUALS[terrain.key]
		var source := TileSetAtlasSource.new()
		source.texture = load(visual.texture)
		source.texture_region_size = Vector2i(NATIVE_TILE_SIZE, NATIVE_TILE_SIZE)
		result.add_source(source, terrain.id)
		for cell: Vector2i in visual.cells:
			source.create_tile(cell)
			var data := source.get_tile_data(cell, 0)
			data.set_custom_data("terrain_id", terrain.id)
			data.set_custom_data("terrain_key", terrain.key)
			data.set_custom_data("walkable", terrain.walkable)
			data.modulate = visual.get("tint", Color.WHITE)
	return result


static func atlas_cell(key: String, cell: Vector2i) -> Vector2i:
	var variants: Array = VISUALS[key].cells
	# Stable presentation variety; no gameplay randomness or per-frame mutation.
	return variants[absi(cell.x * 17 + cell.y * 31) % variants.size()]
