extends SubViewportContainer

const WorldScene = preload("res://world/arena_world.tscn")
const Character = preload("res://characters/character_view.gd")
const Trainer = preload("res://players/player_view.gd")
const Effect = preload("res://world/summon_effect.gd")
const Protocol = preload("res://network/protocol.gd")
var content: GameContent
var snapshot: SessionSnapshot
var views: Dictionary = {}
var effects: Dictionary = {}
var viewport := SubViewport.new()
var camera := Camera2D.new()
var world: Node2D
var actors := Node2D.new()
var _identity := ""
var _dragging := false

func _ready() -> void:
	stretch = true
	viewport.size = Vector2i(size)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = WorldScene.instantiate()
	viewport.add_child(world)
	world.show_spawn_markers = false
	actors.y_sort_enabled = true
	viewport.add_child(actors)
	viewport.add_child(camera)
	camera.enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func present(value: SessionSnapshot) -> void:
	var identity := "%d/%d" % [value.round_id, value.map_id]
	if identity != _identity:
		for view: Node in views.values() + effects.values():
			actors.remove_child(view)
			view.queue_free()
		views.clear()
		effects.clear()
		_identity = identity
		if value.map_id > 0:
			world.load_arena(content, content.arena_catalog.arenas_by_id[value.map_id])
			overview()
	snapshot = value
	world.visible = value.map_id > 0
	actors.visible = value.phase == SessionSnapshot.Phase.IN_ARENA
	if not actors.visible: return
	for state in value.trainers:
		var view: CharacterView = _view(state, true)
		_pose(view, state)
		if value.summon_elapsed_ticks < Protocol.SUMMON_DURATION_TICKS:
			var subject = value.characters.filter(func(character): return character.owner_id == state.owner_id)[0]
			view.present_summon(value.summon_elapsed_ticks / 60.0, "east" if subject.position.x >= state.position.x else "west")
	for state in value.characters:
		var view: CharacterView = _view(state, false)
		_pose(view, state)
		var reveal := clampf((value.summon_elapsed_ticks - Protocol.SUMMON_REVEAL_TICKS) / 24.0, 0, 1)
		view.visible = value.summon_elapsed_ticks >= Protocol.SUMMON_REVEAL_TICKS
		view.modulate = Color(1, 1, 1, reveal)
		view.scale = Vector2.ONE * lerpf(0.2, 1, ease(reveal, 0.5))
		if not effects.has(state.entity_id):
			var effect := Effect.new()
			actors.add_child(effect)
			effects[state.entity_id] = effect
		var trainer = value.trainers.filter(func(entity): return entity.owner_id == state.owner_id)[0]
		effects[state.entity_id].present(trainer.position, state.position, state.owner_id, float(value.summon_elapsed_ticks))

func _view(state: SessionSnapshot.CharacterState, trainer: bool) -> CharacterView:
	if not views.has(state.entity_id):
		var view: CharacterView = Trainer.new() if trainer else Character.new()
		if trainer: content.player_content.configure_view(view, state.definition_id, state.owner_id)
		else: content.configure_character(view, state.definition_id, state.owner_id, content.by_id[state.definition_id].footprint_radius)
		actors.add_child(view)
		views[state.entity_id] = view
	return views[state.entity_id]

func _pose(view: CharacterView, state: SessionSnapshot.CharacterState) -> void:
	view.position = state.position
	var age := (snapshot.server_tick - state.state_start_tick) & 0xffffffff
	view.present_locomotion(Protocol.LOCOMOTION_NAMES[state.locomotion], Protocol.FACING_NAMES[state.facing], float(age) / 60.0)

func overview() -> void:
	if world == null or world.definition == null: return
	var extent: Vector2 = Vector2(world.definition.width, world.definition.height) * world.definition.tile_size
	camera.position = extent / 2.0
	camera.zoom = Vector2.ONE * minf(size.x / extent.x, size.y / extent.y) * 0.92

func focus_owner(owner: int) -> void:
	if snapshot == null: return
	for state in snapshot.characters:
		if state.owner_id == owner:
			camera.position = state.position
			camera.zoom = Vector2.ONE * 2

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]: _dragging = event.pressed; accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.05, 6)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= event.relative / camera.zoom
		accept_event()
