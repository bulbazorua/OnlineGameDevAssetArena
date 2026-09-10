extends "./host_check.gd"

# Each client gets a real, independent viewport, so screen centering and input
# routing are checked as well as camera properties. Optional graphical captures.
const ArenaCamera = preload("res://world/arena_camera.gd")


func _host_arguments() -> PackedStringArray:
	var arguments := super._host_arguments()
	arguments.append_array(["--dev", "--dev-p1=triangle", "--dev-p2=diamond", "--dev-arena=meadow_crossing"])
	return arguments


func _new_client(audience := false) -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var client = load("res://main.tscn").instantiate()
	client.get_node("UI/Screens/LobbyScreen").get_node("%HostPort").value = port
	client.get_node("UI/Screens/LobbyScreen").get_node("%JoinAsAudience").button_pressed = audience
	clients.append(client)
	viewport.add_child(client)
	return client


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 did not connect."
	var second = _new_client()
	var audience = _new_client(true)
	var other_audience = _new_client(true)
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session != null and client.game_arena.character_views.size() == 2)): return "Four clients did not enter the arena."
	await create_timer(0.1).timeout
	for fighter in [first, second]:
		if fighter.game_arena.get_node("%AudienceControls").visible: return "Fighter has spectator camera buttons."
		fighter.game_arena.set_camera_owner(0)
		fighter.game_arena.set_camera_owner(3 - fighter.network.player_id)
		for key in [KEY_TAB, KEY_0, KEY_1, KEY_2, KEY_HOME, KEY_PLUS, KEY_MINUS]:
			_key(fighter, key, true)
			_key(fighter, key, false)
		_wheel(fighter, MOUSE_BUTTON_WHEEL_UP)
		_drag(fighter, Vector2(120, 80))
		if not _fighter_centered(fighter): return "Camera controls unlocked a fighter or moved them off center."

	var camera: ArenaCamera = audience.game_arena.camera
	var other_camera: ArenaCamera = other_audience.game_arena.camera
	var original_zoom := camera.zoom.x
	var original_other := other_camera.position
	var positions := _positions(first)
	var anchor := Vector2(520, 350)
	var world_under_pointer := camera.position + (anchor - Vector2(450, 400)) / camera.zoom
	_wheel(audience, MOUSE_BUTTON_WHEEL_UP, anchor)
	if camera.zoom.x <= original_zoom: return "Audience wheel zoom did not reach the camera through viewport input."
	if world_under_pointer.distance_to(camera.position + (anchor - Vector2(450, 400)) / camera.zoom) > 0.01: return "Wheel zoom lost its cursor anchor."
	var before_drag := camera.position
	_drag(audience, Vector2(40, -30))
	if camera.position.distance_to(before_drag - Vector2(40, -30) / camera.zoom) > 0.01: return "Audience drag did not pan at the current zoom: before=%s after=%s zoom=%s expected=%s" % [before_drag, camera.position, camera.zoom, before_drag - Vector2(40, -30) / camera.zoom]
	var after_drag := camera.position
	_motion(audience, Vector2(30, 30))
	if camera.position != after_drag: return "Mouse release over HUD left dragging active."
	_key(audience, KEY_D, true)
	await create_timer(0.15).timeout
	_key(audience, KEY_D, false)
	if camera.position.x <= after_drag.x: return "Audience keyboard did not pan."
	var stopped := camera.position
	await create_timer(0.1).timeout
	if camera.position != stopped: return "Released pan key kept moving the camera."
	_key(audience, KEY_W, true)
	audience.game_arena._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await create_timer(0.1).timeout
	if camera.position != stopped: return "Focus loss left audience pan held."
	if other_camera.position != original_other or other_camera.zoom.x != original_zoom: return "Spectator controls changed another spectator's view."
	if _positions(first) != positions or audience.game_arena._sequence != 0 or audience.game_arena.input_mask() != 0: return "Audience camera input changed gameplay."
	for fighter in [first, second]:
		if not _fighter_centered(fighter): return "Audience controls changed a fighter camera."

	# Follow is optional for viewers. Zoom keeps following; manual pan releases it.
	_key(audience, KEY_2, true)
	await create_timer(0.1).timeout
	_wheel(audience, MOUSE_BUTTON_WHEEL_UP)
	if camera.follow_owner != 2 or camera.zoom.x <= ArenaCamera.PLAYER_ZOOM: return "Audience could not zoom while following."
	_key(second, KEY_D, true)
	if not await _wait_for(func(): return second.game_arena.predicted_position.x >= 1841): return "P2 did not reach the forest boundary."
	_key(second, KEY_D, false)
	await create_timer(0.15).timeout
	if not _fighter_centered(second): return "Player moved off screen center at the map boundary."
	if camera.position.distance_to(second.game_arena.camera.position) > 1: return "Audience follow did not track the moving player."
	await _capture(first, "p1-centered")
	await _capture(second, "p2-map-edge")
	await _capture(audience, "audience-follow-zoom")
	_drag(audience, Vector2(120, 0))
	if camera.follow_owner != 0: return "Manual pan did not release audience follow."
	await _capture(audience, "audience-free")
	for index in 30: _wheel(audience, MOUSE_BUTTON_WHEEL_UP)
	if not is_equal_approx(camera.zoom.x, ArenaCamera.MAX_ZOOM): return "Audience zoom-in limit failed."
	for index in 60: _wheel(audience, MOUSE_BUTTON_WHEEL_DOWN)
	if not is_equal_approx(camera.zoom.x, camera.overview_zoom()): return "Audience zoom-out limit failed."
	_key(audience, KEY_HOME, true)
	if not camera.is_overview or camera.position != camera.arena_size * 0.5: return "Whole-map reset failed."
	# Resizing refits overview, preserves a free view, and keeps fighters centered.
	for client in clients:
		client.get_viewport().size = Vector2i(800, 760)
	await create_timer(0.1).timeout
	for fighter in [first, second]:
		if not _fighter_centered(fighter): return "Resize changed fighter zoom or screen center."
	if not is_equal_approx(camera.zoom.x, camera.overview_zoom()): return "Resize did not refit the map."
	var controls := ["%Controls", "%AudienceControls", "%DisconnectButton"]
	for path in controls:
		var rect: Rect2 = audience.game_arena.get_node(path).get_global_rect()
		if rect.end.x > 800 or rect.end.y > 760: return "Audience HUD overflows the minimum viewport: " + path
	await _capture(audience, "audience-overview-800")
	# UI buttons receive clicks rather than having the world swallow them.
	_click(audience, audience.game_arena.get_node("%ZoomInButton").get_global_rect().get_center())
	if camera.zoom.x <= camera.overview_zoom(): return "Audience Zoom In button did not receive the click."
	_click(audience, audience.game_arena.get_node("%ZoomInButton").get_global_rect().get_center())
	_click(audience, audience.game_arena.get_node("%ZoomInButton").get_global_rect().get_center())
	var free_position := camera.position
	var free_zoom := camera.zoom
	audience.get_viewport().size = Vector2i(1100, 850)
	await create_timer(0.1).timeout
	if camera.position != free_position or camera.zoom != free_zoom: return "Resizing discarded the spectator's free view."
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return not audience.game_arena.visible): return "Reset did not leave the arena."
	_wheel(audience, MOUSE_BUTTON_WHEEL_UP)
	if camera.zoom != free_zoom: return "Inactive camera consumed lobby input."
	return ""


func _fighter_centered(client: Node) -> bool:
	var game = client.game_arena
	var character: Node2D = game.character_views[game._local_entity]
	game.camera.force_update_scroll()
	var screen_position := character.get_global_transform_with_canvas().origin
	return game.camera_owner == client.network.player_id and game.camera.zoom == Vector2.ONE * ArenaCamera.PLAYER_ZOOM and screen_position.distance_to(client.get_viewport().get_visible_rect().size * 0.5) < 0.1


func _positions(client: Node) -> Array:
	return client.network.session.characters.map(func(character): return character.position)


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	client.get_viewport().push_input(event, true)


func _wheel(client: Node, button: int, point := Vector2(450, 400)) -> void:
	_button(client, button, point, true)
	_button(client, button, point, false)


func _button(client: Node, button: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = pressed
	client.get_viewport().push_input(event, true)


func _drag(client: Node, relative: Vector2) -> void:
	_button(client, MOUSE_BUTTON_RIGHT, Vector2(450, 400), true)
	_motion(client, relative)
	# Release on top of a HUD button to exercise the early release handler.
	_button(client, MOUSE_BUTTON_RIGHT, client.game_arena.get_node("%DisconnectButton").get_global_rect().get_center(), false)


func _motion(client: Node, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(450, 400) + relative
	event.relative = relative
	client.get_viewport().push_input(event, true)


func _click(client: Node, point: Vector2) -> void:
	_button(client, MOUSE_BUTTON_LEFT, point, true)
	_button(client, MOUSE_BUTTON_LEFT, point, false)


func _capture(client: Node, title: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../build/verification/cameras")
	DirAccess.make_dir_recursive_absolute(directory)
	client.get_viewport().get_texture().get_image().save_png(directory.path_join(title + ".png"))
