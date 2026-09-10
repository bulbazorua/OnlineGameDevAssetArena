class_name ArenaWorld
extends Node2D

const ArenaCatalog = preload("res://content/arena_catalog.gd")
const AssetScale = preload("res://presentation/asset_scale.gd")
const TinySwordsTileset = preload("res://world/tiny_swords_tileset.gd")
const TerrainTileset = preload("res://world/terrain_tileset.gd")
const GameContent = preload("res://content/game_content.gd")
const PLAYER_COLORS := [Color("58a6ff"), Color("ffac62")]
const NATURE = preload("res://assets/ninja_adventure/TilesetNature.png")
const ROCK_DETAILS = preload("res://assets/ninja_adventure/TilesetReliefDetail.png")
@onready var terrain_layer: TileMapLayer = $Terrain
@onready var ground_layer: TileMapLayer = $Ground
var definition: ArenaCatalog.ArenaDefinition
var show_spawn_markers := true
var selected_cell := Vector2i(-1, -1)
var _catalog: ArenaCatalog
var _theme := "ninja_adventure"
var _bush: Texture2D
var _small_bush: Texture2D
var props: Array[Sprite2D] = []


func load_arena(content: GameContent, arena: ArenaCatalog.ArenaDefinition) -> void:
	definition = arena
	_catalog = content.arena_catalog
	selected_cell = Vector2i(-1, -1)
	terrain_layer.clear()
	ground_layer.clear()
	var presentation = content.presentations[arena.id]
	_theme = presentation.theme
	for prop in props:
		remove_child(prop)
		prop.queue_free()
	props.clear()
	for definition: Dictionary in presentation.props:
		var prop := Sprite2D.new()
		prop.name = definition.key
		prop.texture = definition.texture
		prop.centered = false
		prop.offset = -definition.anchor
		prop.position = definition.position
		prop.scale = Vector2.ONE * definition.scale
		add_child(prop)
		props.append(prop)
	_bush = null
	_small_bush = null
	if _theme == "tiny_swords":
		_bush = load(TinySwordsTileset.ART + "Terrain/Decorations/Bushes/Bushe1.png")
		_small_bush = load(TinySwordsTileset.ART + "Terrain/Decorations/Bushes/Bushe2.png")
	terrain_layer.tile_set = content.tile_sets[_theme]
	ground_layer.tile_set = terrain_layer.tile_set
	# Native 16px and 64px sheets occupy the same shared world grid.
	terrain_layer.scale = Vector2.ONE * AssetScale.for_grid(terrain_layer.tile_set.tile_size.x, arena.tile_size)
	ground_layer.scale = terrain_layer.scale
	var grass_id := 0
	for terrain in content.arena_catalog.terrains:
		if terrain.key == "grass":
			grass_id = terrain.id
	for y in arena.height:
		for x in arena.width:
			var cell := Vector2i(x, y)
			var id := arena.terrain_id_at(cell)
			var terrain: ArenaCatalog.TerrainDefinition = content.arena_catalog.terrains_by_id[id]
			if grass_id != 0:
				ground_layer.set_cell(cell, grass_id, _atlas_cell("grass", cell), arena.elevation_at(cell))
			terrain_layer.set_cell(cell, id, _atlas_cell(terrain.key, cell), arena.elevation_at(cell))
	queue_redraw()


func highlight_cell(cell: Vector2i) -> void:
	selected_cell = cell
	queue_redraw()


func _draw() -> void:
	if definition == null:
		return
	# Sparse flowers are presentation only; cliffs retain their blocked footprint.
	for y in definition.height:
		for x in definition.width:
			var cell := Vector2i(x, y)
			var terrain: ArenaCatalog.TerrainDefinition = _catalog.terrains_by_id[definition.terrain_id_at(cell)]
			var variation := absi(x * 73856093 ^ y * 19349663)
			var rectangle := Rect2(Vector2(cell) * definition.tile_size, Vector2.ONE * definition.tile_size)
			if _theme == "tiny_swords":
				if terrain.key in ["forest", "tall_grass"]:
					var texture := _bush if terrain.key == "forest" else _small_bush
					draw_texture_rect_region(texture, rectangle, Rect2(0, 0, 128, 128))
				elif terrain.key == "stairs":
					# Simple north/south treads; this pack's supplied slopes face sideways.
					for step in 4:
						var top := rectangle.position + Vector2(2, step * definition.tile_size / 4.0 + 1)
						draw_rect(Rect2(top, Vector2(definition.tile_size - 4, 5)), Color("c8bc8c"))
			elif terrain.key == "grass" and variation % 73 == 0:
				draw_texture_rect_region(NATURE, rectangle, Rect2(Vector2(variation % 2, 11) * 16, Vector2(16, 16)))
			elif terrain.key == "cliff" and variation % 4 == 0:
				draw_texture_rect_region(ROCK_DETAILS, rectangle, Rect2(0, 80, 16, 16))
	# Previews show markers; the playable world owns actual CharacterViews.
	for index in (2 if show_spawn_markers else 0):
		var center := definition.cell_center(definition.spawns[index])
		draw_circle(center, 13, Color("152033"))
		draw_arc(center, 13, 0, TAU, 32, PLAYER_COLORS[index], 2, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-5, 5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PLAYER_COLORS[index])
	if definition.terrain_id_at(selected_cell) != 0:
		draw_rect(Rect2(Vector2(selected_cell) * definition.tile_size, Vector2.ONE * definition.tile_size), Color.WHITE, false, 2.0)


func _atlas_cell(key: String, cell: Vector2i) -> Vector2i:
	if _theme == "tiny_swords":
		return TinySwordsTileset.atlas_cell(key, cell, definition, _catalog)
	return TerrainTileset.atlas_cell(key, cell, definition)
