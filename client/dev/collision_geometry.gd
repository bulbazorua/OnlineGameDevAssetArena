class_name CollisionGeometry
extends RefCounted

const ArenaCatalog = preload("res://content/arena_catalog.gd")

var terrain: Array[Rect2] = []
var buildings: Array[Rect2] = []
var elevation_edges := PackedVector2Array()
var grid := PackedVector2Array()
var bounds := Rect2()


# Use the same catalog queries as movement prediction and the Odin host.
# Sprite bounds and TileSet art/physics are not gameplay collision geometry.
static func build(arena: ArenaCatalog.ArenaDefinition, catalog: ArenaCatalog) -> CollisionGeometry:
	var result := CollisionGeometry.new()
	var tile := arena.tile_size
	result.bounds = Rect2(Vector2.ZERO, Vector2(arena.width, arena.height) * tile)
	for y in arena.height:
		for x in arena.width:
			var cell := Vector2i(x, y)
			if catalog.is_blocked(arena, cell):
				var rectangle := Rect2(Vector2(cell) * tile, Vector2.ONE * tile)
				if catalog.terrains_by_id[arena.terrain_id_at(cell)].key == "building":
					result.buildings.append(rectangle)
				else:
					result.terrain.append(rectangle)
				continue
			# Elevation is a center-crossing rule, separate from solid tile collision.
			# Only inspect right/down so each shared edge appears once. Allowed
			# stairs are openings; blocked neighbors already have tile outlines.
			for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + offset
				if catalog.is_blocked(arena, neighbor) or catalog.step_is_allowed(arena, arena.cell_center(cell), arena.cell_center(neighbor)):
					continue
				var start := Vector2(cell + offset) * tile
				result.elevation_edges.append(start)
				result.elevation_edges.append(start + Vector2(offset.y, offset.x) * tile)
	for x in range(arena.width + 1):
		result.grid.append(Vector2(x * tile, 0))
		result.grid.append(Vector2(x * tile, result.bounds.end.y))
	for y in range(arena.height + 1):
		result.grid.append(Vector2(0, y * tile))
		result.grid.append(Vector2(result.bounds.end.x, y * tile))
	return result
