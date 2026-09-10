class_name ArenaPreview
extends Control

const GameContent = preload("res://content/game_content.gd")
const ArenaCatalog = preload("res://content/arena_catalog.gd")
const ArenaWorld = preload("res://world/arena_world.gd")
const WORLD_SCENE = preload("res://world/arena_world.tscn")

signal terrain_inspected(cell: Vector2i, terrain: ArenaCatalog.TerrainDefinition)
var world: ArenaWorld
var _content: GameContent


func _ready() -> void:
	clip_contents = true
	world = WORLD_SCENE.instantiate()
	# Lift the world's two ground layers above the surrounding UI backdrop.
	world.z_index = 2
	add_child(world)
	resized.connect(_fit_map)
	mouse_exited.connect(func(): world.highlight_cell(Vector2i(-1, -1)))


func display_map(content: GameContent, map_id: int) -> void:
	_content = content
	var arena: ArenaCatalog.ArenaDefinition = content.arena_catalog.arenas_by_id.get(map_id)
	if arena == null:
		return
	if world.definition != arena:
		world.load_arena(content, arena)
	_fit_map()


func _fit_map() -> void:
	if world == null or world.definition == null:
		return
	var dimensions := Vector2(world.definition.width, world.definition.height) * world.definition.tile_size
	var zoom := minf(maxf(size.x - 8, 1) / dimensions.x, maxf(size.y - 8, 1) / dimensions.y)
	world.scale = Vector2.ONE * zoom
	world.position = ((size - dimensions * zoom) * 0.5).floor()


func cell_at_position(local_position: Vector2) -> Vector2i:
	if world == null or world.definition == null:
		return Vector2i(-1, -1)
	return world.definition.world_to_cell((local_position - world.position) / world.scale)


func _gui_input(event: InputEvent) -> void:
	if world.definition == null or not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	var cell := cell_at_position(event.position)
	var terrain: ArenaCatalog.TerrainDefinition = _content.arena_catalog.terrains_by_id.get(world.definition.terrain_id_at(cell))
	world.highlight_cell(cell)
	if terrain != null:
		terrain_inspected.emit(cell, terrain)
