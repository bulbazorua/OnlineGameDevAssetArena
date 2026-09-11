extends "./search_client_driver.gd"

# Integration-only driver: lays a real trainer trail with synthetic keys, toggles
# the host scent heatmap and reports what the arena actually drew.
var scent_command := 0
var trail_phase := "idle"
var trail_target_owner := 0
var trail_started_ms := 0
var _held: Dictionary = {}
var _retreat_until_ms := 0
var _origin := Vector2.ZERO


func _start() -> void:
	super._start()
	var timer := Timer.new()
	app.add_child(timer)
	timer.wait_time = 0.05
	timer.timeout.connect(_inspect_scent)
	timer.start()


func _inspect_scent() -> void:
	var state = app.network.session
	if state == null: return
	var ui = app.get_node("DebugOverlay")
	var path := directory.path_join("scent-command.json")
	if FileAccess.file_exists(path):
		var command = JSON.parse_string(FileAccess.get_file_as_string(path))
		if command is Dictionary and int(command.sequence) > scent_command:
			scent_command = int(command.sequence)
			if slot in command.get("slots", []):
				match command.get("action", ""):
					"lay_trail":
						trail_target_owner = int(command.get("target_owner", 2))
						trail_phase = "approach"
						trail_started_ms = Time.get_ticks_msec()
						_origin = app.game_arena.predicted_position
					"toggle_scent": _push_key(KEY_F8)
					"capture": _capture_search(command.get("label", "scent"))
	_steer_trail(state)
	var evidence := {}
	for owner in ui.search.readings:
		var search: Dictionary = ui.search.readings[owner].search
		evidence[str(owner)] = {"evidence": search.evidence, "transition": search.transition, "state": search.state, "scent": search.scent, "episodes": search.scent_episodes, "cue_from_scent": search.cue_from_scent}
	var output := {"sequence": scent_command, "trail_phase": trail_phase, "scent": ui.scent.diagnostics(),
		"scent_preferences": {"path": ui.scent_preferences.path, "flags": ui.scent_preferences.flags, "error": ui.scent_preferences.error},
		"search_evidence": evidence, "tick": state.server_tick, "round": state.round_id,
		"trainer": [app.game_arena.predicted_position.x, app.game_arena.predicted_position.y],
		"creatures": state.characters.map(func(character): return {"owner": character.owner_id, "position": [character.position.x, character.position.y]})}
	var status_path := directory.path_join("scent-%s.json" % slot)
	var file := FileAccess.open(status_path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(output))
	file.close()
	DirAccess.rename_absolute(status_path + ".tmp", status_path)


# Run the trainer to the other creature, then walk back toward the start for five
# seconds (a slow walk leaves the strongest trail), then stop. Every key is a real
# synthetic key event.
func _steer_trail(state) -> void:
	if trail_phase == "idle" or trail_phase == "done": return
	if Time.get_ticks_msec() - trail_started_ms > 45000:
		_release_all()
		trail_phase = "done"
		return
	var here: Vector2 = app.game_arena.predicted_position
	var goal := _origin
	if trail_phase == "approach":
		for character in state.characters:
			if character.owner_id == trail_target_owner: goal = character.position
		if here.distance_to(goal) < 72:
			trail_phase = "retreat"
			_retreat_until_ms = Time.get_ticks_msec() + 5000
	elif trail_phase == "retreat" and Time.get_ticks_msec() >= _retreat_until_ms:
		_release_all()
		trail_phase = "done"
		return
	var delta := goal - here
	var wanted := {}
	if trail_phase == "approach": wanted[KEY_SPACE] = true
	if absf(delta.x) > 6: wanted[KEY_D if delta.x > 0 else KEY_A] = true
	if absf(delta.y) > 6: wanted[KEY_S if delta.y > 0 else KEY_W] = true
	for key in _held.keys():
		if not wanted.has(key): _set_key(key, false)
	for key in wanted: _set_key(key, true)


func _set_key(key: int, pressed: bool) -> void:
	if _held.get(key, false) == pressed: return
	if pressed: _held[key] = true
	else: _held.erase(key)
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	root.push_input(event, true)


func _release_all() -> void:
	for key in _held.keys(): _set_key(key, false)


func _push_key(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event, true)
