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

@onready var world: ArenaWorld = $ArenaWorld
@onready var camera: Camera2D = $Camera2D
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


func configure(game_content: GameContent, connection: GameConnection) -> void:
	content = game_content
	network = connection
	world.show_spawn_markers = false
	return_button.pressed.connect(network.request_return_to_lobby)
	%DisconnectButton.pressed.connect(network.disconnect_from_host)
	get_viewport().size_changed.connect(_fit_camera)


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
		_fit_camera()
	if not was_active:
		get_viewport().gui_release_focus()
		camera.make_current()
		camera.force_update_scroll()
	snapshot = state
	var role := "Audience" if network.player_id == 0 else "Player %d" % network.player_id
	title_label.text = "%s  ·  %s  ·  %d watching" % [world.definition.display_name, role, state.audience_count]
	return_button.visible = network.player_id != 0
	controls_label.text = "Watching both players" if network.player_id == 0 else "WASD / Arrow keys to move  ·  Your character has a white ring"
	var names: Array[String] = []
	for index in 2:
		names.append("P%d · %s" % [index + 1, content.by_id[state.players[index].character_id].display_name])
	%PlayerOne.text = names[0]
	%PlayerTwo.text = names[1]
	countdown_label.visible = state.phase == SessionSnapshot.Phase.COUNTDOWN
	countdown_label.text = str(state.countdown_seconds)
	phase_label.text = "Get ready" if state.phase == SessionSnapshot.Phase.COUNTDOWN else "Arena sandbox"
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
			view.configure(content.visuals[character.definition_id], character.owner_id, content.by_id[character.definition_id].footprint_radius)
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
		return
	_pending.append(Vector2i(_sequence, mask))
	var view: CharacterView = character_views[_local_entity]
	predicted_position = CharacterMovement.move(predicted_position, mask, view.radius, world.definition, content.arena_catalog)


func _process(delta: float) -> void:
	if not visible:
		return
	_interpolation_time += delta
	var weight := minf(_interpolation_time / INTERPOLATION_SECONDS, 1.0)
	for id: int in _remote_target:
		character_views[id].position = _remote_from[id].lerp(_remote_target[id], weight)
	if _local_entity != 0:
		_correction *= exp(-20.0 * delta)
		character_views[_local_entity].position = predicted_position + _correction


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or network == null or network.player_id == 0 or not event is InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
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


func _fit_camera() -> void:
	if not is_node_ready() or world.definition == null:
		return
	var arena_size := Vector2(world.definition.width, world.definition.height) * world.definition.tile_size
	var available := get_viewport_rect().size - Vector2(48, 200)
	camera.position = arena_size * 0.5
	camera.zoom = Vector2.ONE * maxf(0.1, minf(available.x / arena_size.x, available.y / arena_size.y))
	camera.force_update_scroll()


func _clear_characters() -> void:
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
