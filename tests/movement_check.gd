extends "./host_check.gd"

const Movement = preload("res://world/character_movement.gd")
var rejections: Array[int] = []
var countdowns: Dictionary = {}


func _check() -> String:
	var wire_error := _check_wire()
	if not wire_error.is_empty(): return wire_error
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 could not connect."
	var second = _new_client()
	var watcher = _new_client(true)
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.LOBBY) and first.network.session.audience_count == 1): return "Lobby did not converge."
	for client in clients:
		countdowns[client] = []
		client.network.session_changed.connect(func(state): _record_countdown(client, state))
		client.network.command_rejected.connect(func(reason): rejections.append(reason))
	first.network.request_start_selection()
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.SELECTING)): return "Selection did not start."
	first.network.request_character(3)
	second.network.request_character(4)
	if not await _wait_for(func(): return first.network.session.players[0].character_id == 3 and second.network.session.players[1].character_id == 4): return "Could not select Triangle and Diamond."
	first.network.request_set_ready(3, true)
	if not await _wait_for(func(): return watcher.network.session.players[0].ready): return "First Ready was not shared."
	await create_timer(0.12).timeout
	if not _all_phase(SessionSnapshot.Phase.SELECTING): return "Countdown started with only one Ready."
	var started := Time.get_ticks_msec()
	second.network.request_set_ready(4, true)
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.COUNTDOWN)): return "Both Ready did not enter Countdown."
	for client in clients:
		if not client.game_arena.visible or not client.game_arena.hud.visible or not client.game_arena.camera.enabled or client.game_arena.character_views.size() != 0 or client.selection.visible or client.arena_selection.visible or client.lobby.visible:
			return "Countdown screen/camera was wrong or characters spawned early."
	first.network.request_character(1)
	first.network.request_arena(2)
	first.network.send_input(1, 2)
	if not await _wait_for(func(): return rejections.count(GameProtocol.CommandRejectReason.WRONG_PHASE) == 3): return "Countdown did not lock choices and movement."
	if not await _wait_for(func(): return watcher.network.session.countdown_seconds == 4): return "Countdown did not advance to four."
	var late = _new_client(true)
	if not await _wait_for(func(): return late.network.session != null and late.network.session.phase == SessionSnapshot.Phase.COUNTDOWN): return "Late audience missed the countdown."
	if late.game_arena.countdown_label.text != str(late.network.session.countdown_seconds) or not late.game_arena.visible: return "Late audience countdown display was stale."
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.IN_ARENA)): return "Countdown did not spawn the characters."
	var elapsed := Time.get_ticks_msec() - started
	if elapsed < 4900 or elapsed > 5700: return "Countdown was not five seconds: %d ms." % elapsed
	for client in [first, second, watcher]:
		if countdowns[client] != [5, 4, 3, 2, 1]: return "A client skipped/repeated countdown numbers: " + str(countdowns[client])
	var initial: SessionSnapshot = first.network.session
	var map = first.game_arena.world.definition
	var spawn_one: Vector2 = map.cell_center(map.spawns[0])
	var spawn_two: Vector2 = map.cell_center(map.spawns[1])
	var first_id: int = initial.trainers[0].entity_id
	for client in clients:
		var game = client.game_arena
		if game.character_views.size() != 2 or game.world.show_spawn_markers or game.countdown_label.visible: return "Arena entry did not replace markers/countdown with two characters."
		if game.camera_owner != client.network.player_id: return "Camera did not default to player follow/audience overview."
		game.set_camera_owner(0)
		if client.network.player_id == 0:
			var dimensions: Vector2 = Vector2(map.width, map.height) * map.tile_size
			if not game.camera.position.is_equal_approx(dimensions * 0.5): return "Overview is not centered on the arena."
			var visible_size: Vector2 = dimensions * game.camera.zoom
			if visible_size.x > root.get_visible_rect().size.x - 48.0 + 1 or visible_size.y > root.get_visible_rect().size.y - 240.0 + 1: return "Overview cropped the arena or HUD."
		elif game.camera_owner != client.network.player_id:
			return "Player camera could be unlocked."
		for state in client.network.session.trainers:
			var view = game.trainer_views[state.entity_id]
			var expected := spawn_one if state.owner_id == 1 else spawn_two
			if state.position != expected or view.animation_set == null or view.player_id != state.owner_id or view.is_local != (state.owner_id == client.network.player_id): return "Spawn identity, selected visual, ownership color/ring, or position was wrong."
	if watcher.game_arena.return_button.visible: return "Audience can return fighters to lobby."

	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.summon_elapsed_ticks == 90)): return "Summoning did not finish."
	# Prediction works while this client's incoming snapshots are paused.
	first.network.set_process(false)
	_key(first, KEY_D, true)
	await create_timer(0.43).timeout
	if first.game_arena.predicted_position.x <= spawn_one.x + 9 or first.game_arena._pending.is_empty(): return "Local input waited for incoming host snapshots."
	first.network.set_process(true)
	_key(second, KEY_LEFT, true)
	await create_timer(0.65).timeout
	_key(first, KEY_D, false)
	_key(second, KEY_LEFT, false)
	await create_timer(0.18).timeout
	if not await _wait_for(_positions_converged): return "Player movement did not settle to the same positions on every client."
	if _position(first, 1).x <= spawn_one.x + 30 or _position(first, 2).x >= spawn_two.x - 21 or _position(first, 1).y != spawn_one.y or _position(first, 2).y != spawn_two.y: return "WASD/arrows did not independently move the two selected characters."
	if first.game_arena.camera.position.distance_to(first.game_arena.predicted_position) > 1: return "Local camera did not follow movement."
	watcher.game_arena.set_camera_owner(2)
	await create_timer(0.05).timeout
	if watcher.game_arena.camera.position.distance_to(_position(watcher, 2)) > 1: return "Audience could not follow P2."
	watcher.game_arena.set_camera_owner(0)
	for client in clients:
		for state in client.network.session.trainers:
			if client.game_arena.trainer_views[state.entity_id].position.distance_to(state.position) > 1.0: return "A rendered character did not converge to the shared position."

	var mid_match = _new_client(true)
	if not await _wait_for(func(): return mid_match.network.session != null and mid_match.game_arena.character_views.size() == 2 and _positions_converged()): return "Mid-match audience did not receive current characters and positions."
	mid_match.network.command_rejected.connect(func(reason): rejections.append(reason))
	mid_match.network.send_input(1, 2)
	mid_match.network.request_return_to_lobby()
	if not await _wait_for(func(): return rejections.count(GameProtocol.CommandRejectReason.AUDIENCE_READ_ONLY) == 2): return "Audience could issue movement/reset commands."
	var old_world := GameProtocol.DecodedMessage.new()
	old_world.kind = GameProtocol.MessageKind.WORLD_STATE
	old_world.session = initial
	first.network._receive_message(old_world)
	if _position(first, 1).x == spawn_one.x: return "An old world packet teleported a character back to spawn."
	# Reliable membership and unreliable positions can cross in transit.
	var current_position := _position(first, 1)
	var delayed_session := GameProtocol.DecodedMessage.new()
	delayed_session.kind = GameProtocol.MessageKind.SESSION_STATE
	delayed_session.session = first.network.session.with_world(initial)
	first.network._receive_message(delayed_session)
	if _position(first, 1) != current_position: return "A delayed reliable session overwrote a newer world position."

	# Focus loss releases held keys, including overlapping WASD/arrow aliases.
	_key(first, KEY_D, true)
	_key(first, KEY_RIGHT, true)
	_key(first, KEY_D, false)
	if first.game_arena.input_mask() != Movement.RIGHT: return "Releasing one alias cancelled the other held key."
	first.game_arena._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	if first.game_arena.input_mask() != 0: return "Focus loss left movement held."
	await create_timer(0.18).timeout
	var before: Vector2 = _position(first, 1)
	await create_timer(0.18).timeout
	if _position(first, 1) != before: return "Host kept moving after focus loss."

	# Lost heartbeats must stop the character even while the connection is alive.
	_key(first, KEY_D, true)
	await create_timer(0.45).timeout # Complete the planted step before losing heartbeats.
	before = _position(first, 1)
	first.game_arena.set_physics_process(false)
	_key(first, KEY_D, false)
	first.network.send_input(first.game_arena._sequence + 1, Movement.RIGHT)
	await create_timer(0.36).timeout
	var stopped: Vector2 = _position(first, 1)
	await create_timer(0.18).timeout
	if _position(first, 1) != stopped or stopped.x <= before.x: return "Input heartbeat timeout did not stop host movement."
	first.game_arena._sequence += 1
	first.game_arena.set_physics_process(true)

	first.game_arena.return_button.pressed.emit()
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.LOBBY)): return "Return to lobby did not reset everyone."
	for client in clients:
		if client.game_arena.visible or client.game_arena.hud.visible or client.game_arena.camera.enabled or not client.game_arena.character_views.is_empty() or not client.lobby.visible: return "Reset left a camera, HUD, or character active."
	# Replay selects Circle and Square; test collision on the same authoritative map.
	first.network.request_start_selection()
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.SELECTING)): return "Could not start a second match."
	first.network.request_character(1)
	second.network.request_character(2)
	if not await _wait_for(func(): return first.network.session.players[0].character_id == 1 and second.network.session.players[1].character_id == 2): return "Second match picks failed."
	first.network.request_set_ready(1, true)
	second.network.request_set_ready(2, true)
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.IN_ARENA)): return "Second match did not spawn."
	if first.network.session.trainers[0].entity_id <= first_id: return "Runtime entity IDs were reused."
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.summon_elapsed_ticks == 90)): return "Second summon did not finish."
	_key(first, KEY_W, true)
	_key(second, KEY_RIGHT, true)
	if not await _wait_for(func(): return _position(first, 1).y < 364.6 and _position(first, 2).x > 1843.4): return "Players did not reach the cliff/forest collision edges after preparation."
	_key(first, KEY_W, false)
	_key(second, KEY_RIGHT, false)
	await create_timer(0.18).timeout
	if not await _wait_for(_positions_converged): return "Collision positions did not converge."
	if _position(first, 1).y < 361.6 or _position(first, 1).y >= 364.6 or _position(first, 2).x > 1846.4 or _position(first, 2).x <= 1843.4: return "The host allowed crossing cliffs/forest or blocked movement too early."
	var arena = first.game_arena.world.definition
	var diagonal := Movement.move(spawn_one, 10, 12, arena, first.content.arena_catalog)
	if absf(diagonal.distance_to(spawn_one) - 2.0) > 0.001: return "Client diagonal movement is faster than cardinal movement."
	var cliff_stop := Vector2(spawn_one.x, 364)
	if Movement.move(cliff_stop, 4, 12, arena, first.content.arena_catalog) != cliff_stop: return "Client prediction disagrees with host cliff collision."
	second.network.disconnect_from_host()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.LOBBY and watcher.lobby.visible): return "Fighter departure did not clear live characters and return the audience to lobby."
	print("Countdown elapsed: %d ms; two independently controlled characters converged across five clients." % elapsed)
	return ""


func _record_countdown(client: Node, state: SessionSnapshot) -> void:
	if state == null or state.phase != SessionSnapshot.Phase.COUNTDOWN: return
	var values: Array = countdowns[client]
	if values.is_empty() or values[-1] != state.countdown_seconds:
		values.append(state.countdown_seconds)


func _all_phase(phase: int) -> bool:
	for client in clients:
		if client.network.session == null or client.network.session.phase != phase: return false
	return true


func _position(client: Node, owner: int) -> Vector2:
	for character in client.network.session.trainers:
		if character.owner_id == owner: return character.position
	return Vector2.INF


func _positions_converged() -> bool:
	for owner in [1, 2]:
		var expected := _position(clients[0], owner)
		for client in clients:
			if client.network.session == null or _position(client, owner).distance_to(expected) > 0.01: return false
	return true


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	# These app instances share a test viewport; target independent window input.
	client.game_arena._unhandled_key_input(event)


func _check_wire() -> String:
	var bytes := PackedByteArray([79, 71, 65, 65, 9, 11, 1, 2, 3, 4, 5, 6, 7, 8, 2, 1, 0, 0, 0, 3,
		0, 1, 0, 144, 0, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 4,
		0, 2, 0, 240, 1, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1,
		0, 1, 0, 112, 0, 0, 0, 240, 0, 0, 9, 10, 11, 12, 6, 4, 0, 0, 0, 1,
		0, 2, 0, 16, 2, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 90, 0, 1, 2, 0, 6, 7, 8, 0, 6, 4, 5, 6, 7,
		1, 1, 0, 6, 7, 8, 0, 6, 4, 5, 6, 7])
	var decoded := GameProtocol.decode(bytes, 1)
	if not decoded.error_title.is_empty() or decoded.session.round_id != 0x04030201 or decoded.session.server_tick != 0x08070605 or decoded.session.characters[0].position != Vector2(144, 240) or decoded.session.characters[1].position != Vector2(496, 240) or decoded.session.trainers[0].applied_input_sequence != 0x0c0b0a09 or decoded.session.summon_elapsed_ticks != 90: return "World-state fixture differs from Odin."
	if decoded.session.characters[0].locomotion != 1 or decoded.session.characters[0].facing != 2 or decoded.session.characters[0].state_start_tick != 0x08070600 or decoded.session.characters[1].facing != 6: return "Character locomotion wire fields differ from Odin."
	if decoded.session.trainers[0].locomotion != 1 or decoded.session.trainers[0].facing != 1 or decoded.session.trainers[0].state_start_tick != 0x08070600 or decoded.session.trainers[1].facing != 6: return "Trainer action clock differs from Odin."
	var input := GameProtocol.encode_input(0x04030201, 0x0c0b0a09, 6)
	if input != PackedByteArray([79, 71, 65, 65, 9, 10, 1, 2, 3, 4, 9, 10, 11, 12, 6]): return "Input fixture differs from Odin."
	for length in bytes.size():
		if GameProtocol.decode(bytes.slice(0, length), 1).error_title.is_empty(): return "Truncated world packet was accepted."
	for edit in [[14, 1], [15, 0], [19, 0], [21, 0], [34, 16], [35, 1], [41, 1], [55, 1], [59, 2], [61, 0], [75, 3], [81, 1], [95, 91], [97, 2], [98, 8], [99, 255], [109, 2], [110, 8], [111, 255], [4, 8]]:
		var corrupt := bytes.duplicate()
		corrupt[edit[0]] = edit[1]
		if GameProtocol.decode(corrupt, 1).error_title.is_empty(): return "Invalid world state was accepted: " + str(edit)
	if GameProtocol.decode(bytes, 0).error_title.is_empty(): return "Wrong world channel was accepted."
	return ""
