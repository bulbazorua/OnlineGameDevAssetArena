class_name GameArena
extends Node2D

const GameContent = preload("res://content/game_content.gd")
const GameConnection = preload("res://network/game_connection.gd")
const GameProtocol = preload("res://network/protocol.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")
const CharacterView = preload("res://characters/character_view.gd")
const CharacterMovement = preload("res://world/character_movement.gd")
const ArenaWorld = preload("res://world/arena_world.gd")
const INTERPOLATION_SECONDS := 0.05
const MAX_PENDING_INPUTS := 120
const STALE_WORLD_MS := 500
const ArenaCamera = preload("res://world/arena_camera.gd")

@onready var world: ArenaWorld = $ArenaWorld
@onready var camera: ArenaCamera = $Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var countdown_label: Label = %Countdown
@onready var phase_label: Label = %Phase
@onready var title_label: Label = %Title
@onready var controls_label: Label = %Controls
@onready var return_button: Button = %ReturnButton
var content: GameContent
var network: GameConnection
var snapshot: SessionSnapshot
var character_views: Dictionary = {}
var predicted_position := Vector2.ZERO
var _local_entity := 0
var _sequence := 0
var _pending: Array[Vector2i] = []
var _pressed_keys: Dictionary = {}
var _correction := Vector2.ZERO
var _remote_from: Dictionary = {}
var _remote_target: Dictionary = {}
var _interpolation_time := 0.0
var _last_tick := -1
var _last_world_ms := 0
var _last_local_position := Vector2.ZERO
var debug_actions := false
var camera_owner: int:
	get: return camera.follow_owner


func configure(game_content: GameContent, connection: GameConnection) -> void:
	content = game_content
	network = connection
	debug_actions = OS.is_debug_build() and "--dev" in OS.get_cmdline_user_args()
	world.show_spawn_markers = false
	return_button.pressed.connect(network.request_return_to_lobby)
	%DisconnectButton.pressed.connect(network.disconnect_from_host)
	camera.view_changed.connect(_update_camera_controls)
	%OverviewButton.pressed.connect(set_camera_owner.bind(0))
	%FollowOneButton.pressed.connect(set_camera_owner.bind(1))
	%FollowTwoButton.pressed.connect(set_camera_owner.bind(2))
	%ZoomInButton.pressed.connect(camera.zoom_by.bind(1.0))
	%ZoomOutButton.pressed.connect(camera.zoom_by.bind(-1.0))


func display_session(state: SessionSnapshot) -> void:
	var active := state != null and state.phase in [SessionSnapshot.Phase.COUNTDOWN, SessionSnapshot.Phase.IN_ARENA]
	var was_active := visible
	visible = active
	hud.visible = active
	camera.enabled = active
	if not active:
		snapshot = null
		_clear_characters()
		return
	var new_round := snapshot == null or state.round_id != snapshot.round_id
	if new_round:
		_clear_characters()
		world.load_arena(content, content.arena_catalog.arenas_by_id[state.map_id])
		camera.configure_role(Vector2(world.definition.width, world.definition.height) * world.definition.tile_size, network.player_id)
	if not was_active:
		get_viewport().gui_release_focus()
		camera.make_current()
		camera.force_update_scroll()
	snapshot = state
	_update_camera()
	var role := "Audience" if network.player_id == 0 else "Player %d" % network.player_id
	title_label.text = "%s  ·  %s  ·  %d watching" % [world.definition.display_name, role, state.audience_count]
	return_button.visible = network.player_id != 0
	%AudienceControls.visible = network.player_id == 0
	controls_label.text = "Wheel / + −: zoom · Right / middle drag or WASD: pan · 0: reset · 1 / 2: follow" if network.player_id == 0 else "WASD / Arrows to move · Your character stays centered"
	var names: Array[String] = []
	for index in 2:
		names.append("P%d · %s" % [index + 1, content.by_id[state.players[index].character_id].display_name])
	%PlayerOne.text = names[0]
	%PlayerTwo.text = names[1]
	countdown_label.visible = state.phase == SessionSnapshot.Phase.COUNTDOWN
	countdown_label.text = str(state.countdown_seconds)
	phase_label.text = "Get ready" if state.phase == SessionSnapshot.Phase.COUNTDOWN else "Arena sandbox"
	if network.player_id == 0:
		phase_label.text += " · " + network.audience_timeline_label()
	if state.phase == SessionSnapshot.Phase.IN_ARENA:
		apply_world(state)


func apply_world(state: SessionSnapshot) -> void:
	if snapshot == null or state.round_id != snapshot.round_id or state.phase != SessionSnapshot.Phase.IN_ARENA:
		return
	if _last_tick >= 0 and not GameProtocol.serial_is_newer(state.server_tick, _last_tick):
		return
	snapshot = state
	_last_tick = state.server_tick
	_last_world_ms = Time.get_ticks_msec()
	_interpolation_time = 0.0
	for character in state.characters:
		var fresh := not character_views.has(character.entity_id)
		var view: CharacterView
		if fresh:
			view = CharacterView.new()
			view.is_local = character.owner_id == network.player_id
			content.configure_character(view, character.definition_id, character.owner_id, content.by_id[character.definition_id].footprint_radius)
			view.set_debug_actions(debug_actions)
			view.position = character.position
			$Characters.add_child(view)
			character_views[character.entity_id] = view
		else:
			view = character_views[character.entity_id]
		if character.owner_id == network.player_id:
			_local_entity = character.entity_id
			_last_local_position = character.position
			var old_visible := view.position
			predicted_position = character.position
			while not _pending.is_empty() and not GameProtocol.serial_is_newer(_pending[0].x, character.applied_input_sequence):
				_pending.pop_front()
			for sample in _pending:
				predicted_position = CharacterMovement.move(predicted_position, sample.y, view.radius, world.definition, content.arena_catalog)
			_correction = old_visible - predicted_position
			if fresh or _correction.length() > 64:
				_correction = Vector2.ZERO
			view.position = predicted_position + _correction
		else:
			var previous: Vector2 = _remote_target.get(character.entity_id, character.position)
			var movement := character.position - previous
			if fresh:
				movement = CharacterMovement.move(character.position, character.input_mask, view.radius, world.definition, content.arena_catalog) - character.position
			view.observe_motion(movement)
			_remote_from[character.entity_id] = view.position
			_remote_target[character.entity_id] = character.position


func _physics_process(_delta: float) -> void:
	if not visible or snapshot == null or snapshot.phase != SessionSnapshot.Phase.IN_ARENA or network.player_id == 0 or _local_entity == 0:
		return
	_sequence = (_sequence + 1) & 0xffffffff
	var mask := input_mask()
	network.send_input(_sequence, mask)
	# A disconnect signal may synchronously clear this world during send.
	if _local_entity == 0:
		return
	if Time.get_ticks_msec() - _last_world_ms > STALE_WORLD_MS or _pending.size() >= MAX_PENDING_INPUTS:
		_pending.clear()
		predicted_position = _last_local_position
		_correction = Vector2.ZERO
		character_views[_local_entity].observe_motion(Vector2.ZERO)
		return
	_pending.append(Vector2i(_sequence, mask))
	var view: CharacterView = character_views[_local_entity]
	var previous := predicted_position
	predicted_position = CharacterMovement.move(predicted_position, mask, view.radius, world.definition, content.arena_catalog)
	view.observe_motion(predicted_position - previous)


func _process(delta: float) -> void:
	if not visible:
		return
	_interpolation_time += delta
	var weight := minf(_interpolation_time / INTERPOLATION_SECONDS, 1.0)
	for id: int in _remote_target:
		character_views[id].position = _remote_from[id].lerp(_remote_target[id], weight)
		if Time.get_ticks_msec() - _last_world_ms > STALE_WORLD_MS:
			character_views[id].observe_motion(Vector2.ZERO)
	if _local_entity != 0:
		_correction *= exp(-20.0 * delta)
		character_views[_local_entity].position = predicted_position + _correction
	_update_camera(delta)


func _input(event: InputEvent) -> void:
	if visible and camera.continue_input(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and camera.handle_pointer(event):
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or network == null or not event is InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if network.player_id == 0:
		if camera.handle_key(event):
			_update_camera()
			get_viewport().set_input_as_handled()
		return
	if key not in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return
	if event.pressed:
		_pressed_keys[key] = true
	else:
		_pressed_keys.erase(key)
	get_viewport().set_input_as_handled()


func input_mask() -> int:
	var mask := 0
	if _pressed_keys.has(KEY_A) or _pressed_keys.has(KEY_LEFT): mask |= CharacterMovement.LEFT
	if _pressed_keys.has(KEY_D) or _pressed_keys.has(KEY_RIGHT): mask |= CharacterMovement.RIGHT
	if _pressed_keys.has(KEY_W) or _pressed_keys.has(KEY_UP): mask |= CharacterMovement.UP
	if _pressed_keys.has(KEY_S) or _pressed_keys.has(KEY_DOWN): mask |= CharacterMovement.DOWN
	return mask


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_pressed_keys.clear()
		if is_node_ready(): camera.reset_input()


func _update_camera_controls() -> void:
	%OverviewButton.set_pressed_no_signal(camera.is_overview)
	%FollowOneButton.set_pressed_no_signal(camera_owner == 1)
	%FollowTwoButton.set_pressed_no_signal(camera_owner == 2)
	%ZoomLabel.text = "%d%%" % roundi(camera.zoom.x * 100)
	%ZoomOutButton.disabled = camera.zoom.x <= camera.overview_zoom() + 0.001
	%ZoomInButton.disabled = camera.zoom.x >= ArenaCamera.MAX_ZOOM - 0.001


func set_camera_owner(owner: int) -> void:
	camera.select_view(owner)
	_update_camera()


func _update_camera(delta := 0.0) -> void:
	if world.definition == null:
		return
	var target := camera.position
	if camera_owner > 0:
		target = world.definition.cell_center(world.definition.spawns[camera_owner - 1])
		if snapshot != null:
			for character in snapshot.characters:
				if character.owner_id == camera_owner and character_views.has(character.entity_id):
					target = character_views[character.entity_id].position
	camera.update_view(target, delta)


func _clear_characters() -> void:
	camera.reset_input()
	for view: CharacterView in character_views.values():
		view.queue_free()
	character_views.clear()
	_remote_from.clear()
	_remote_target.clear()
	_pressed_keys.clear()
	_pending.clear()
	_local_entity = 0
	_sequence = 0
	_last_tick = -1
	_correction = Vector2.ZERO
