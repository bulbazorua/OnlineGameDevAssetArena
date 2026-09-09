class_name ArenaWorld
extends Node2D

const ArenaCatalog = preload("res://content/arena_catalog.gd")
const TerrainTileset = preload("res://world/terrain_tileset.gd")
const GameContent = preload("res://content/game_content.gd")
const PLAYER_COLORS := [Color("58a6ff"), Color("ffac62")]
@onready var terrain_layer: TileMapLayer = $Terrain
var definition: ArenaCatalog.ArenaDefinition
var show_spawn_markers := true
var selected_cell := Vector2i(-1, -1)


func load_arena(content: GameContent, arena: ArenaCatalog.ArenaDefinition) -> void:
	definition = arena
	selected_cell = Vector2i(-1, -1)
	terrain_layer.clear()
	terrain_layer.tile_set = content.tile_set
	# Keep original 16px art; the layer scale maps it to shared world units.
	terrain_layer.scale = Vector2.ONE * (float(arena.tile_size) / TerrainTileset.NATIVE_TILE_SIZE)
	for y in arena.height:
		for x in arena.width:
			var cell := Vector2i(x, y)
			var id := arena.terrain_id_at(cell)
			var terrain: ArenaCatalog.TerrainDefinition = content.arena_catalog.terrains_by_id[id]
			terrain_layer.set_cell(cell, id, TerrainTileset.atlas_cell(terrain.key, cell))
	queue_redraw()


func highlight_cell(cell: Vector2i) -> void:
	selected_cell = cell
	queue_redraw()


func _draw() -> void:
	if definition == null:
		return
	# Previews show markers; the playable world owns actual CharacterViews.
	for index in (2 if show_spawn_markers else 0):
		var center := definition.cell_center(definition.spawns[index])
		draw_circle(center, 13, Color("152033"))
		draw_arc(center, 13, 0, TAU, 32, PLAYER_COLORS[index], 2, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-5, 5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PLAYER_COLORS[index])
	if definition.terrain_id_at(selected_cell) != 0:
		draw_rect(Rect2(Vector2(selected_cell) * definition.tile_size, Vector2.ONE * definition.tile_size), Color.WHITE, false, 2.0)
