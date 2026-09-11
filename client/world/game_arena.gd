class_name GameArena
extends Node2D

const CharacterMotionPresenter = preload("res://characters/character_motion_presenter.gd")
const GameContent = preload("res://content/game_content.gd")
const GameConnection = preload("res://network/game_connection.gd")
const GameProtocol = preload("res://network/protocol.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")
const CharacterView = preload("res://characters/character_view.gd")
const PlayerView = preload("res://players/player_view.gd")
const TrainerMovement = preload("res://players/trainer_movement.gd")
const SummonEffect = preload("res://world/summon_effect.gd")
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
var character_presenters: Dictionary = {}
var trainer_views: Dictionary = {}
var trainer_presenters: Dictionary = {}
var summon_effects: Dictionary = {}
var _summon_from := 0.0
var _summon_display_tick := 0.0
var predicted_position := Vector2.ZERO
var _local_entity := 0
var _sequence := 0
var _pending: Array[Vector2i] = []
var _pressed_keys: Dictionary = {}
var _correction := Vector2.ZERO
var _predicted_trainer: SessionSnapshot.TrainerState
var _predicted_tick := 0
var _local_motion_elapsed := 0.0
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
	controls_label.text = "Wheel / + −: zoom · Right / middle drag or WASD: pan · 0: reset · 1 / 2: follow" if network.player_id == 0 else "WASD / Arrows: move · Hold Space: run · Characters search on their own"
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
	_summon_from = _summon_display_tick if not trainer_views.is_empty() else float(state.summon_elapsed_ticks)
	for character in state.characters:
		if not character_views.has(character.entity_id):
			var gladiator := CharacterView.new()
			content.configure_character(gladiator, character.definition_id, character.owner_id, content.by_id[character.definition_id].footprint_radius)
			gladiator.animator.facing = "east" if character.owner_id == 1 else "west"
			gladiator.observe_motion(Vector2.ZERO)
			gladiator.set_debug_actions(debug_actions)
			gladiator.position = character.position
			$Characters.add_child(gladiator)
			character_views[character.entity_id] = gladiator
			character_presenters[character.entity_id] = CharacterMotionPresenter.new(gladiator)
			var effect := SummonEffect.new()
			$Characters.add_child(effect)
			summon_effects[character.entity_id] = effect
		character_presenters[character.entity_id].push(character, state.server_tick)
	for character in state.trainers:
		var fresh := not trainer_views.has(character.entity_id)
		var view: PlayerView
		if fresh:
			view = PlayerView.new()
			view.is_local = character.owner_id == network.player_id
			content.player_content.configure_view(view, character.definition_id, character.owner_id)
			view.set_debug_actions(debug_actions)
			view.position = character.position
			$Characters.add_child(view)
			trainer_views[character.entity_id] = view
			if character.owner_id != network.player_id:
				trainer_presenters[character.entity_id] = CharacterMotionPresenter.new(view, GameProtocol.TRAINER_WALK_START_TICKS)
		else:
			view = trainer_views[character.entity_id]
		if character.owner_id == network.player_id:
			_local_entity = character.entity_id
			_last_local_position = character.position
			var old_visible := view.position
			_predicted_trainer = TrainerMovement.copy_state(character)
			_predicted_tick = state.server_tick
			_local_motion_elapsed = 0.0
			while not _pending.is_empty() and not GameProtocol.serial_is_newer(_pending[0].x, character.applied_input_sequence):
				_pending.pop_front()
			for sample in _pending:
				_predicted_tick = (_predicted_tick + 1) & 0xffffffff
				TrainerMovement.step(_predicted_trainer, sample.y, _predicted_tick, world.definition, content.arena_catalog)
			predicted_position = _predicted_trainer.position
			_correction = old_visible - predicted_position
			if fresh or _correction.length() > 64:
				_correction = Vector2.ZERO
			view.position = predicted_position + _correction
		else:
			trainer_presenters[character.entity_id].push(character, state.server_tick)

	_present_summon(0.0)

func _physics_process(_delta: float) -> void:
	if not visible or snapshot == null or snapshot.phase != SessionSnapshot.Phase.IN_ARENA or network.player_id == 0 or _local_entity == 0:
		return
	_sequence = (_sequence + 1) & 0xffffffff
	var summoning: bool = snapshot.summon_elapsed_ticks < GameProtocol.SUMMON_DURATION_TICKS
	var mask := 0 if summoning else input_mask()
	network.send_input(_sequence, mask)
	# A disconnect signal may synchronously clear this world during send.
	if _local_entity == 0:
		return
	if summoning:
		_pending.clear()
		return
	if Time.get_ticks_msec() - _last_world_ms > STALE_WORLD_MS or _pending.size() >= MAX_PENDING_INPUTS:
		_pending.clear()
		predicted_position = _last_local_position
		_correction = Vector2.ZERO
		_predicted_trainer.position = predicted_position
		_predicted_trainer.locomotion = 0
		_local_motion_elapsed = 0.0
		return
	_pending.append(Vector2i(_sequence, mask))
	_predicted_tick = (_predicted_tick + 1) & 0xffffffff
	TrainerMovement.step(_predicted_trainer, mask, _predicted_tick, world.definition, content.arena_catalog)
	predicted_position = _predicted_trainer.position
	_local_motion_elapsed = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	for presenter in character_presenters.values(): presenter.advance(delta)
	for presenter in trainer_presenters.values(): presenter.advance(delta)
	_interpolation_time += delta
	var weight := minf(_interpolation_time / INTERPOLATION_SECONDS, 1.0)
	if _local_entity != 0:
		_correction *= exp(-20.0 * delta)
		trainer_views[_local_entity].position = predicted_position + _correction
		_local_motion_elapsed = minf(_local_motion_elapsed + delta, CharacterMovement.STEP)
		var age := float((_predicted_tick - _predicted_trainer.state_start_tick) & 0xffffffff) / 60.0 + _local_motion_elapsed
		trainer_views[_local_entity].present_locomotion(GameProtocol.LOCOMOTION_NAMES[_predicted_trainer.locomotion], GameProtocol.FACING_NAMES[_predicted_trainer.facing], age)
	_present_summon(weight)
	%TrainerEnergy.present(_predicted_trainer, network.player_id, snapshot != null and snapshot.summon_elapsed_ticks < GameProtocol.SUMMON_DURATION_TICKS)
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
	if key not in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE]:
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
	if _pressed_keys.has(KEY_SPACE): mask |= GameProtocol.TRAINER_RUN_INPUT
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
			for character in snapshot.trainers:
				if character.owner_id == camera_owner and trainer_views.has(character.entity_id):
					target = trainer_views[character.entity_id].position
	camera.update_view(target, delta)


func _clear_characters() -> void:
	camera.reset_input()
	for view in character_views.values() + trainer_views.values() + summon_effects.values():
		view.queue_free()
	character_views.clear()
	character_presenters.clear()
	trainer_views.clear()
	trainer_presenters.clear()
	summon_effects.clear()
	_summon_from = 0.0
	_summon_display_tick = 0.0
	_predicted_trainer = null
	if is_node_ready(): %TrainerEnergy.hide()
	_predicted_tick = 0
	_local_motion_elapsed = 0.0
	_pressed_keys.clear()
	_pending.clear()
	_local_entity = 0
	_sequence = 0
	_last_tick = -1
	_correction = Vector2.ZERO


func _present_summon(weight: float) -> void:
	if snapshot == null or snapshot.phase != SessionSnapshot.Phase.IN_ARENA: return
	_summon_display_tick = float(GameProtocol.SUMMON_DURATION_TICKS) if snapshot.summon_elapsed_ticks == GameProtocol.SUMMON_DURATION_TICKS else lerpf(_summon_from, float(snapshot.summon_elapsed_ticks), weight)
	var summoning := snapshot.summon_elapsed_ticks < GameProtocol.SUMMON_DURATION_TICKS
	phase_label.text = "Summoning gladiators…" if summoning else "Arena sandbox"
	if network.player_id == 0: phase_label.text += " · " + network.audience_timeline_label()
	for character in snapshot.characters:
		var view: CharacterView = character_views[character.entity_id]
		var trainer_state = snapshot.trainers.filter(func(trainer): return trainer.owner_id == character.owner_id)[0]
		var trainer: PlayerView = trainer_views[trainer_state.entity_id]
		if summoning:
			var facing := "east" if character.position.x >= trainer.position.x else "west"
			trainer.present_summon(_summon_display_tick / 60.0, facing)
		var reveal := clampf((_summon_display_tick - GameProtocol.SUMMON_REVEAL_TICKS) / 24.0, 0.0, 1.0)
		view.visible = _summon_display_tick >= GameProtocol.SUMMON_REVEAL_TICKS
		view.modulate = Color(1, 1, 1, reveal)
		view.scale = Vector2.ONE * lerpf(0.2, 1.0, ease(reveal, 0.5))
		summon_effects[character.entity_id].present(trainer.position, character.position, character.owner_id, _summon_display_tick)
