extends "./dev_client_driver.gd"

var search_command := 0
var captured_alert := false
var capturing := false
var acquisitions: Dictionary = {}
var body_hops: Dictionary = {}
var body_landings: Dictionary = {}
var rounds: Dictionary = {}


func _start() -> void:
	super._start()
	app.network.session_changed.connect(_record_search_round)
	var timer := Timer.new()
	app.add_child(timer)
	timer.wait_time = 0.05
	timer.timeout.connect(_inspect_search)
	timer.start()


func _record_search_round(state) -> void:
	if state == null or state.characters.size() != 2 or rounds.has(str(state.round_id)): return
	var ui = app.get_node("DebugOverlay")
	assert(ui.search.readings.values().all(func(record): return int(record.round_id) == state.round_id), "New round displayed old search beliefs")
	var characters := []
	for character in state.characters:
		characters.append({"id": character.entity_id, "position": [character.position.x, character.position.y], "alert": character.target_alert})
	rounds[str(state.round_id)] = {"tick": state.server_tick, "summon": state.summon_elapsed_ticks, "characters": characters}
	if rounds.size() > 1: _capture_search("search-reset")


func _inspect_search() -> void:
	var state = app.network.session
	if state == null: return
	var ui = app.get_node("DebugOverlay")
	var path := directory.path_join("search-command.json")
	if FileAccess.file_exists(path):
		var command = JSON.parse_string(FileAccess.get_file_as_string(path))
		if command is Dictionary and int(command.sequence) > search_command:
			search_command = int(command.sequence)
			if slot in command.slots:
				if command.get("action", "toggle") == "reset":
					_click_search_reset(ui)
				else:
					var event := InputEventKey.new()
					event.physical_keycode = KEY_F6
					event.pressed = true
					root.push_input(event, true)
					_capture_search("search-debug-%d" % search_command)
	for character in state.characters:
		if not app.game_arena.character_views.has(character.entity_id): continue
		var view = app.game_arena.character_views[character.entity_id]
		if character.target_alert:
			assert(view.target_alert != null and view.target_alert.visible)
			if not acquisitions.has(str(character.owner_id)):
				acquisitions[str(character.owner_id)] = character.target_acquired_tick
		if view.body_sprite != null and view.body_sprite.position.y < -8:
			assert(view.surprise_hop.visible and view.surprise_hop.global_position.is_equal_approx(view.global_position), "The creature's shadow left its ground position")
			body_hops[str(character.owner_id)] = view.body_sprite.position.y
			if not captured_alert:
				captured_alert = true
				_capture_search("target-found")
		elif body_hops.has(str(character.owner_id)) and view.body_sprite.position == Vector2.ZERO:
			body_landings[str(character.owner_id)] = true
	var output := {"sequence": search_command, "enabled": ui.search.enabled, "preference": ui.search_preferences.enabled,
		"preference_path": ui.search_preferences.path, "preference_error": ui.search_preferences.error,
		"status": ui.search.status, "readings": ui.search.readings.size(), "panel": ui.search_panel.visible,
		"acquisitions": acquisitions, "body_hops": body_hops, "body_landings": body_landings,
		"tick": state.server_tick, "phase": state.phase,
		"round": state.round_id, "rounds": rounds, "reset_status": ui.search_reset.status.text,
		"positions": state.characters.map(func(character): return [character.position.x, character.position.y]),
		"brain_rounds": ui.search.readings.values().map(func(record): return record.round_id),
		"text": ui.search_labels[0].get_parsed_text() if ui.search_labels.size() > 0 else ""}
	var status_path := directory.path_join("search-%s.json" % slot)
	var file := FileAccess.open(status_path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(output))
	file.close()
	DirAccess.rename_absolute(status_path + ".tmp", status_path)


func _click_search_reset(ui) -> void:
	ui.get_node("%FiltersToggle").button_pressed = true
	ui.get_node("%Filters").scroll_vertical = 0
	await process_frame
	await process_frame
	var point: Vector2 = ui.search_reset.button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)


func _capture_search(label: String) -> void:
	if capturing or DisplayServer.get_name() == "headless": return
	capturing = true
	if label.begins_with("search-debug"): await create_timer(0.6).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("%s-%s.png" % [slot, label]))
	capturing = false
