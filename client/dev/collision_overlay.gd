class_name CollisionOverlay
extends Node2D

const Geometry = preload("res://dev/collision_geometry.gd")
const Protocol = preload("res://network/protocol.gd")
const CATEGORIES := [
	{"key": "buildings", "label": "Buildings", "color": Color("ffad42"), "hint": "Solid building cells, including the footprint behind the artwork."},
	{"key": "terrain", "label": "Blocked terrain", "color": Color("ff596d"), "hint": "Solid water, stone, forest and cliff cells."},
	{"key": "elevation", "label": "Elevation barriers", "color": Color("dc88ff"), "hint": "Edges the entity center cannot cross. Valid stairs remain open."},
	{"key": "bounds", "label": "Map boundary", "color": Color("f5f5a4"), "hint": "The entire movement circle must stay inside this rectangle."},
	{"key": "players", "label": "Players / trainers", "color": Color("54dbff"), "hint": "Trainer movement circles, centered on the displayed ground position."},
	{"key": "characters", "label": "Characters / gladiators", "color": Color("75ff97"), "hint": "Selected character movement circles, using each definition's gameplay radius."},
	{"key": "grid", "label": "Tile grid (reference)", "color": Color("a3b4c7"), "hint": "All tile boundaries, including walkable land. This grid is not a collider."},
]

var enabled := true
var categories := {"buildings": true, "terrain": true, "elevation": true, "bounds": true, "players": true, "characters": true, "grid": false}
var geometry: Geometry
var footprints: Array[Dictionary] = []
var _arena: Node2D
var _definition: RefCounted
var _static := Node2D.new()


func configure(arena: Node2D) -> void:
	_arena = arena
	name = "CollisionOverlay"
	z_index = 100
	# Run after movement presentation, so the outlines follow the same pose
	# as the camera and sprites, including the audience's delayed timeline.
	process_priority = 100
	_static.draw.connect(_draw_static)
	add_child(_static)
	arena.add_child(self)
	visible = false


func set_enabled(value: bool) -> void:
	enabled = value
	_process(0.0)


func set_category(key: String, value: bool) -> void:
	if not categories.has(key): return
	categories[key] = value
	_static.queue_redraw()
	_process(0.0)


func _process(_delta: float) -> void:
	visible = enabled and _arena.visible and _arena.snapshot != null and categories.values().has(true)
	footprints.clear()
	if not visible: return
	if _definition != _arena.world.definition:
		_definition = _arena.world.definition
		geometry = Geometry.build(_arena.world.definition, _arena.content.arena_catalog)
		_static.queue_redraw()
	if categories.players:
		_collect_footprints(_arena.snapshot.trainers, _arena.trainer_views, "players")
	if categories.characters:
		_collect_footprints(_arena.snapshot.characters, _arena.character_views, "characters")
	queue_redraw()


func _collect_footprints(states: Array, views: Dictionary, category: String) -> void:
	for state in states:
		var view: Node2D = views.get(state.entity_id)
		if view == null or not view.is_visible_in_tree(): continue
		var radius: float = Protocol.TRAINER_RADIUS if category == "players" else _arena.content.by_id[state.definition_id].footprint_radius
		# Summon sprite scaling and source image dimensions never resize physics.
		footprints.append({"category": category, "entity_id": state.entity_id,
			"center": to_local(view.global_position), "radius": radius})


func _draw_static() -> void:
	if geometry == null: return
	if categories.grid:
		_static.draw_multiline(geometry.grid, Color(_color("grid"), 0.25), -1.0)
	if categories.terrain:
		_draw_cells(geometry.terrain, _color("terrain"))
	if categories.buildings:
		_draw_cells(geometry.buildings, _color("buildings"))
	if categories.elevation and not geometry.elevation_edges.is_empty():
		_static.draw_multiline(geometry.elevation_edges, _color("elevation"), 2.5, true)
	if categories.bounds:
		_static.draw_rect(geometry.bounds, _color("bounds"), false, 2.5)


func _draw_cells(cells: Array[Rect2], color: Color) -> void:
	for rectangle in cells:
		_static.draw_rect(rectangle, Color(color, 0.18))
		_static.draw_rect(rectangle, color, false, 1.0)


func _draw() -> void:
	for footprint in footprints:
		var color := _color(footprint.category)
		var center: Vector2 = footprint.center
		var radius: float = footprint.radius
		draw_circle(center, radius, Color(color, 0.2))
		draw_arc(center, radius, 0, TAU, 48, Color(0, 0, 0, 0.85), 3.5, true)
		draw_arc(center, radius, 0, TAU, 48, color, 1.5, true)
		draw_line(center - Vector2(3, 0), center + Vector2(3, 0), color, 1.0)
		draw_line(center - Vector2(0, 3), center + Vector2(0, 3), color, 1.0)


func _color(key: String) -> Color:
	for category in CATEGORIES:
		if category.key == key: return category.color
	return Color.WHITE
