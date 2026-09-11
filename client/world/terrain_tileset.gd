class_name TerrainTileset
extends RefCounted

const ArenaCatalog = preload("res://content/arena_catalog.gd")
const ART := "res://assets/ninja_adventure/"
const NATIVE_TILE_SIZE := 16
const VISUALS := {
	"building": {"texture": ART + "TilesetFloor.png", "cells": [Vector2i(11, 12)]},
	"grass": {"texture": ART + "TilesetFloor.png", "cells": [Vector2i(11, 12), Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12), Vector2i(15, 12)]},
	"ground": {"texture": ART + "TilesetFloor.png", "origin": Vector2i(11, 7)},
	"sand": {"texture": ART + "TilesetFloor.png", "cells": [Vector2i(0, 5), Vector2i(4, 5)]},
	"water": {"texture": ART + "TilesetWater.png", "origin": Vector2i(0, 6)},
	"stone": {"texture": ART + "TilesetNature.png", "cells": [Vector2i(4, 12), Vector2i(6, 12), Vector2i(7, 12)]},
	"cliff": {"texture": ART + "TilesetRelief.png", "origin": Vector2i(4, 5)},
	"stairs": {"texture": ART + "TilesetReliefDetail.png", "cells": [Vector2i(5, 3)]},
	"forest": {"texture": ART + "TilesetNature.png", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
	"tall_grass": {"texture": ART + "TilesetNature.png", "cells": [Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(7, 10)]},
}


static func cells_for(visual: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if visual.has("origin"):
		for y in 3:
			for x in 3:
				cells.append(visual.origin + Vector2i(x, y))
	else:
		cells.assign(visual.cells)
	return cells


static func validate(catalog: ArenaCatalog, visuals: Dictionary = VISUALS, native_size: int = NATIVE_TILE_SIZE) -> String:
	for terrain in catalog.terrains:
		if not visuals.has(terrain.key):
			return "Missing terrain visual for '%s'." % terrain.key
		var visual: Dictionary = visuals[terrain.key]
		var texture = load(visual.texture)
		if not texture is Texture2D:
			return "Invalid terrain texture: %s" % visual.texture
		for cell in cells_for(visual):
			if (cell.x + 1) * native_size > texture.get_width() or (cell.y + 1) * native_size > texture.get_height():
				return "Terrain tile is outside its source texture."
	return ""


static func build(catalog: ArenaCatalog, visuals: Dictionary = VISUALS, native_size: int = NATIVE_TILE_SIZE) -> TileSet:
	var result := TileSet.new()
	result.tile_size = Vector2i(native_size, native_size)
	var metadata := {"terrain_id": TYPE_INT, "terrain_key": TYPE_STRING, "walkable": TYPE_BOOL, "blocks_vision": TYPE_BOOL, "scent": TYPE_STRING, "elevation": TYPE_INT}
	for key: String in metadata:
		var index := result.get_custom_data_layers_count()
		result.add_custom_data_layer()
		result.set_custom_data_layer_name(index, key)
		result.set_custom_data_layer_type(index, metadata[key])
	for terrain in catalog.terrains:
		var visual: Dictionary = visuals[terrain.key]
		var source := TileSetAtlasSource.new()
		source.texture = load(visual.texture)
		source.texture_region_size = Vector2i(native_size, native_size)
		result.add_source(source, terrain.id)
		for cell in cells_for(visual):
			source.create_tile(cell)
			for elevation in 4:
				if elevation > 0:
					source.create_alternative_tile(cell, elevation)
				var data := source.get_tile_data(cell, elevation)
				data.set_custom_data("terrain_id", terrain.id)
				data.set_custom_data("terrain_key", terrain.key)
				data.set_custom_data("walkable", terrain.walkable)
				data.set_custom_data("blocks_vision", terrain.blocks_vision)
				data.set_custom_data("scent", terrain.scent)
				data.set_custom_data("elevation", elevation)
				data.modulate = visual.get("tint", Color.WHITE)
				if elevation > 0 and terrain.key in ["grass", "ground", "tall_grass"]:
					data.modulate *= Color(1.08, 1.08, 1.0)
	return result


static func atlas_cell(key: String, cell: Vector2i, arena: ArenaCatalog.ArenaDefinition = null) -> Vector2i:
	var visual: Dictionary = VISUALS[key]
	if key == "forest":
		return Vector2i(posmod(cell.x, 2), posmod(cell.y, 2))
	if visual.has("origin"):
		if arena == null:
			return visual.origin + Vector2i.ONE
		var id := arena.terrain_id_at(cell)
		var left := arena.terrain_id_at(cell + Vector2i.LEFT) == id
		var right := arena.terrain_id_at(cell + Vector2i.RIGHT) == id
		var above := arena.terrain_id_at(cell + Vector2i.UP) == id
		var below := arena.terrain_id_at(cell + Vector2i.DOWN) == id
		if key == "cliff":
			var height := arena.elevation_at(cell)
			left = arena.elevation_at(cell + Vector2i.LEFT) == height
			right = arena.elevation_at(cell + Vector2i.RIGHT) == height
			below = arena.elevation_at(cell + Vector2i.DOWN) == height
		return visual.origin + Vector2i(0 if not left else (2 if not right else 1), 0 if not above else (2 if not below else 1))
	var variants: Array = visual.cells
	var value := absi(cell.x * 73856093 ^ cell.y * 19349663)
	# Most grass remains quiet; details form small patches rather than stripes.
	if key == "grass" and value % 11 > 1:
		return variants[0]
	return variants[value % variants.size()]
