extends "./host_check.gd"

func _host_arguments() -> PackedStringArray:
	var arguments := super._host_arguments()
	arguments.append_array(["--dev", "--dev-p1=triangle", "--dev-p2=diamond", "--dev-arena=meadow_crossing"])
	return arguments


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 could not connect."
	_new_client()
	var audience = _new_client(true)
	if not await _wait_for(func(): return audience.network.session != null and audience.network.session.phase == SessionSnapshot.Phase.IN_ARENA): return "Large arena did not start."
	var arena = first.game_arena.world.definition
	_key(first, KEY_D, true)
	if not await _wait_for(func(): return _position(first).x >= 462): return "Could not approach stairs."
	_key(first, KEY_D, false)
	await create_timer(0.15).timeout
	_key(first, KEY_W, true)
	if not await _wait_for(func(): return _position(first).y <= 270): return "Host blocked stair ascent."
	_key(first, KEY_W, false)
	await create_timer(0.2).timeout
	for client in clients:
		if arena.elevation_at(arena.world_to_cell(_position(client))) != 1 or _position(client).distance_to(_position(first)) > 0.01:
			return "High-ground position did not replicate to every client."
		if client.game_arena.trainer_views[client.network.session.trainers[0].entity_id].position.distance_to(_position(first)) > 1:
			return "Prediction/rendering disagreed with stair ascent."
	_key(first, KEY_S, true)
	if not await _wait_for(func(): return _position(first).y >= 400): return "Host blocked stair descent."
	_key(first, KEY_S, false)
	await create_timer(0.2).timeout
	for client in clients:
		if arena.elevation_at(arena.world_to_cell(_position(client))) != 0 or _position(client).distance_to(_position(first)) > 0.01:
			return "Ground-level position did not replicate after descending."
	# Camera switches are presentation-only, including audience follow controls.
	var before := _position(audience)
	_key(audience, KEY_1, true)
	if audience.game_arena.camera_owner != 1: return "Audience follow shortcut failed."
	_key(audience, KEY_0, true)
	if audience.game_arena.camera_owner != 0 or _position(audience) != before: return "Overview changed gameplay state."
	_key(first, KEY_TAB, true)
	if first.game_arena.camera_owner != 1: return "Tab unlocked the player camera."
	return ""


func _position(client: Node) -> Vector2:
	return client.network.session.trainers[0].position


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	client.game_arena._unhandled_key_input(event)
