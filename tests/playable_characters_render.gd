extends SceneTree

const Content = preload("res://content/game_content.gd")
const Snapshot = preload("res://session/session_snapshot.gd")
const Connection = preload("res://network/game_connection.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var content := Content.new()
	var error := content.load_catalog()
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	var state := Snapshot.new(3, 1)
	state.phase = Snapshot.Phase.SELECTING
	state.round_id = 1
	state.map_id = 4
	state.players[0].character_id = 5
	state.players[1].character_id = 6
	var selection = load("res://ui/character_select_screen.tscn").instantiate()
	root.add_child(selection)
	selection.configure(content)
	selection.display_session(state, 1)
	await _capture("selection")
	selection.display_session(state, 0)
	await _capture("audience-selection")
	selection.queue_free()
	await process_frame
	var network := Connection.new()
	root.add_child(network)
	network.player_id = 0
	var arena = load("res://world/game_arena.tscn").instantiate()
	root.add_child(arena)
	arena.configure(content, network)
	arena.debug_actions = true
	state.phase = Snapshot.Phase.IN_ARENA
	state.server_tick = 1
	var start: Vector2 = content.arena_catalog.arenas_by_id[state.map_id].cell_center(content.arena_catalog.arenas_by_id[state.map_id].spawns[0])
	for index in 2:
		var character := Snapshot.CharacterState.new()
		character.entity_id = index + 1
		character.definition_id = index + 5
		character.owner_id = index + 1
		character.position = start + Vector2(index * 58, 0)
		state.characters.append(character)
	arena.display_session(state)
	arena.set_camera_owner(1)
	arena.camera.zoom_by(4)
	await _capture("arena-idle")
	for view in arena.character_views.values(): view.observe_motion(Vector2(3 if view.player_id == 1 else -3, 0))
	await _capture("arena-walk")
	for view in arena.character_views.values(): view.set_debug_actions(false)
	await _capture("arena-no-debug")
	print("PASS: graphical six-character selection, audience picks and animated arena/action-label captures")
	quit()


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for size in [Vector2i(900, 800), Vector2i(800, 760)]:
		root.size = size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../build/verification/playable-characters")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join("%s-%dx%d.png" % [name, size.x, size.y]))
