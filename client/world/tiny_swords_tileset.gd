class_name TinySwordsTileset
extends RefCounted

const TerrainTileset = preload("res://world/terrain_tileset.gd")
const ArenaCatalog = preload("res://content/arena_catalog.gd")
const ART := "res://assets/tiny_swords/"
const NATIVE_TILE_SIZE := 64
const GRASS := ART + "Terrain/Tileset/Tilemap_color2.png"
const VISUALS := {
	"grass": {"texture": GRASS, "origin": Vector2i(0, 0)},
	"ground": {"texture": ART + "Terrain/Tileset/Tilemap_color3.png", "cells": [Vector2i(1, 1)], "tint": Color(1.6, 0.85, 0.8)},
	"sand": {"texture": ART + "Terrain/Tileset/Tilemap_color5.png", "cells": [Vector2i(1, 1)], "tint": Color(2.4, 1.35, 0.82)},
	"water": {"texture": ART + "Terrain/Tileset/Water Background color.png", "cells": [Vector2i(0, 0)]},
	"stone": {"texture": ART + "Terrain/Decorations/Rocks/Rock1.png", "cells": [Vector2i(0, 0)]},
	"cliff": {"texture": GRASS, "cells": [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)]},
	"stairs": {"texture": ART + "Terrain/Tileset/Tilemap_color3.png", "cells": [Vector2i(1, 1)], "tint": Color(1.6, 0.85, 0.8)},
	"forest": {"texture": GRASS, "cells": [Vector2i(1, 1)]},
	"tall_grass": {"texture": GRASS, "cells": [Vector2i(1, 1)]},
	"building": {"texture": GRASS, "cells": [Vector2i(1, 1)]},
}


static func validate(catalog: ArenaCatalog) -> String:
	for name in ["Bushe1.png", "Bushe2.png"]:
		var path: String = ART + "Terrain/Decorations/Bushes/" + name
		if not ResourceLoader.exists(path): return "Missing Tiny Swords art. Run make import_tiny_swords."
		var texture = load(path)
		if not texture is Texture2D or texture.get_width() < 128 or texture.get_height() < 128:
			return "Invalid Tiny Swords decoration: %s" % path
	return TerrainTileset.validate(catalog, VISUALS, NATIVE_TILE_SIZE)


static func build(catalog: ArenaCatalog) -> TileSet:
	return TerrainTileset.build(catalog, VISUALS, NATIVE_TILE_SIZE)


static func atlas_cell(key: String, cell: Vector2i, arena: ArenaCatalog.ArenaDefinition, catalog: ArenaCatalog) -> Vector2i:
	if key == "grass":
		# Flat ground joins every land surface; paths/buildings are not shorelines.
		var left := _land(cell + Vector2i.LEFT, arena, catalog)
		var right := _land(cell + Vector2i.RIGHT, arena, catalog)
		var up := _land(cell + Vector2i.UP, arena, catalog)
		var down := _land(cell + Vector2i.DOWN, arena, catalog)
		return Vector2i(0 if not left else (2 if not right else 1), 0 if not up else (2 if not down else 1))
	if key == "cliff":
		var height := arena.elevation_at(cell)
		var left := arena.elevation_at(cell + Vector2i.LEFT) == height
		var right := arena.elevation_at(cell + Vector2i.RIGHT) == height
		var row := 1 # Vertical side of the raised grass surface.
		if arena.elevation_at(cell + Vector2i.UP) != height:
			row = 0
		elif arena.elevation_at(cell + Vector2i.DOWN) != height:
			row = 4 # Front rock wall.
		elif arena.elevation_at(cell + Vector2i.DOWN * 2) != height:
			row = 3 # Grass lip above the front wall.
		return Vector2i(5 if not left else (7 if not right else 6), row)
	return VISUALS[key].cells[0]


static func _land(cell: Vector2i, arena: ArenaCatalog.ArenaDefinition, catalog: ArenaCatalog) -> bool:
	var terrain: ArenaCatalog.TerrainDefinition = catalog.terrains_by_id.get(arena.terrain_id_at(cell))
	return terrain != null and terrain.key != "water"
