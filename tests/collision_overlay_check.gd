extends "./trainers_check.gd"

const Geometry = preload("res://dev/collision_geometry.gd")
const Catalog = preload("res://content/arena_catalog.gd")


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 did not connect."
	var second = _new_client()
	var audience = _new_client(true)
	if not await _wait_for(func(): return clients.all(func(client): return _entered(client))): return "Arena did not start."
	if "--dev" not in OS.get_cmdline_user_args():
		for client in clients:
			if client.has_node("DebugOverlay") or client.game_arena.has_node("CollisionOverlay"): return "Normal client instantiated collision debug nodes."
		return ""
	var ui = first.get_node("DebugOverlay")
	var overlay = ui.colliders
	var error := _check_geometry(first.content)
	if not error.is_empty(): return error
	if not await _wait_for(func(): return first.game_arena._summon_display_tick >= 40): return "Summon reveal did not arrive."
	await process_frame
	for circle in overlay.footprints:
		if circle.category == "characters" and circle.radius != 12.0: return "Summon visual scale resized collision."
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.summon_elapsed_ticks == 90)): return "Summon did not finish."
	await create_timer(0.1).timeout
	for client in clients:
		error = _check_footprints(client)
		if not error.is_empty(): return error
	# F3 retains filter choices and never changes another window.
	_push_key(first, KEY_F3)
	if overlay.enabled or overlay.visible: return "F3 failed to hide collision geometry."
	if not second.get_node("DebugOverlay").colliders.enabled: return "F3 changed another window."
	_push_key(first, KEY_F3)
	_push_key(first, KEY_F4)
	await process_frame
	if not ui.get_node("%Filters").visible: return "F4 failed to expand filters."
	ui.get_node("%NoColliders").pressed.emit()
	if overlay.visible or not overlay.footprints.is_empty(): return "None left collision geometry visible."
	# Real pointer event reaches a category checkbox; it does not capture WASD focus.
	var buildings: CheckBox = ui.category_buttons.buildings
	_click(first, buildings.get_global_rect().get_center())
	if not overlay.categories.buildings or overlay.categories.values().count(true) != 1: return "Buildings-only checkbox did not isolate its category."
	if first.get_viewport().gui_get_focus_owner() != null: return "Debug checkbox stole movement key focus."
	await _capture(first, "buildings-only")
	ui.category_buttons.buildings.button_pressed = false
	ui.category_buttons.players.button_pressed = true
	if overlay.footprints.size() != 2 or overlay.footprints.any(func(circle): return circle.category != "players"): return "Players-only filter included gladiators."
	await _capture(first, "players-only")
	ui.category_buttons.players.button_pressed = false
	ui.category_buttons.characters.button_pressed = true
	if overlay.footprints.size() != 2 or overlay.footprints.any(func(circle): return circle.category != "characters"): return "Characters-only filter included trainers."
	await _capture(first, "characters-only")
	ui.get_node("%AllColliders").pressed.emit()
	if not overlay.enabled or overlay.categories.grid or overlay.categories.values().count(true) != 6: return "All colliders did not restore the six collision categories."
	await _capture(first, "all-colliders")
	_push_key(first, KEY_F4)
	await process_frame
	await process_frame
	if ui.get_node("%Panel").size.y > 180 or not overlay.visible: return "Collapsing filters retained an oversized panel or hid the colliders."
	await _capture(first, "collapsed-panel")
	# Cached static geometry is reused while live footprints move. The audience
	# must use its own delayed presentation even if the local host keeps ticking.
	var geometry = overlay.geometry
	_key(first, KEY_D, true)
	await create_timer(0.6).timeout
	_key(first, KEY_D, false)
	for client in clients:
		error = _check_footprints(client)
		if not error.is_empty(): return error
	if overlay.geometry != geometry: return "Static collision geometry was rebuilt during movement."
	if first.game_arena.camera.position.distance_to(_trainer(first, 1).position) > 0.1: return "Debug controls displaced the centered player camera."
	var spectator = audience.get_node("DebugOverlay")
	audience.network.set_process(false)
	await create_timer(0.12).timeout
	var frozen: Vector2 = _trainer(audience, 1).position
	_key(first, KEY_D, true)
	await create_timer(0.45).timeout
	_key(first, KEY_D, false)
	error = _check_footprints(audience)
	if not error.is_empty(): return error
	if _trainer(audience, 1).position != frozen: return "Audience overlay advanced a frozen host feed."
	audience.network.set_process(true)
	# Pointer input over the panel must not zoom the audience camera.
	_push_key(audience, KEY_F4)
	await process_frame
	var camera = audience.game_arena.camera
	var zoom: Vector2 = camera.zoom
	_scroll(audience, spectator.get_node("%Panel").get_global_rect().get_center())
	if camera.zoom != zoom: return "Wheel over debug controls zoomed the audience camera."
	_scroll(audience, Vector2(350, 400))
	if camera.zoom == zoom: return "Debug overlay blocked wheel input outside its panel."
	audience.game_arena.set_camera_owner(0)
	spectator.category_buttons.grid.button_pressed = true
	await _capture(audience, "audience-overview")
	spectator.category_buttons.grid.button_pressed = false
	audience.get_viewport().size = Vector2i(800, 760)
	await process_frame
	await process_frame
	var panel_rect: Rect2 = spectator.get_node("%Panel").get_global_rect()
	if not Rect2(0, 0, 800, 640).encloses(panel_rect): return "Expanded filters overlap the bottom HUD at minimum window size."
	await _capture(audience, "minimum-window")
	# Round reset, map switch, and theme change must not retain village blockers.
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.phase == SessionSnapshot.Phase.LOBBY)): return "Lobby reset failed."
	await process_frame
	for client in clients:
		if client.get_node("DebugOverlay").colliders.is_visible_in_tree(): return "Collision overlay remained visible in lobby."
	first.network.request_start_selection()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.SELECTING): return "Replay selection failed."
	first.network.request_arena(1)
	first.network.request_character(5)
	second.network.request_character(6)
	if not await _wait_for(func(): return second.network.session.map_id == 1 and first.network.session.players[1].character_id == 6): return "Replay choices failed."
	first.network.request_set_ready(5, true)
	second.network.request_set_ready(6, true)
	if not await _wait_for(func(): return overlay.geometry != geometry and overlay.visible): return "New map did not rebuild debug geometry."
	if not overlay.geometry.buildings.is_empty(): return "New map retained village building collision."
	return ""


func _check_geometry(content: GameContent) -> String:
	var catalog = content.arena_catalog
	for arena in catalog.arenas:
		var geometry := Geometry.build(arena, catalog)
		var solid_count := 0
		for y in arena.height:
			for x in arena.width:
				var cell := Vector2i(x, y)
				var rectangle := Rect2(Vector2(cell) * arena.tile_size, Vector2.ONE * arena.tile_size)
				var blocked: bool = catalog.is_blocked(arena, cell)
				if blocked: solid_count += 1
				if geometry.terrain.has(rectangle) or geometry.buildings.has(rectangle):
					if not blocked: return "Overlay marks walkable land as a solid collider."
					if catalog.position_is_clear(arena, arena.cell_center(cell), 1.0): return "Drawn solid does not block movement."
					var building: bool = catalog.terrains_by_id[arena.terrain_id_at(cell)].key == "building"
					if building != geometry.buildings.has(rectangle): return "Building and terrain filters disagree with the shared map."
		if geometry.terrain.size() + geometry.buildings.size() != solid_count: return "Overlay omitted or duplicated a blocked tile."
		if geometry.bounds != Rect2(0, 0, arena.width * arena.tile_size, arena.height * arena.tile_size): return "Map bounds disagree with movement bounds."
		for prop in content.presentations[arena.id].props:
			if not geometry.buildings.has(Rect2(Vector2(prop.footprint.position) * arena.tile_size, Vector2.ONE * arena.tile_size)): return "Building overlay used art bounds instead of its terrain footprint."
	# Top crossing is a valid stair; bottom crossing is a forbidden rise.
	var fixture := Catalog.ArenaDefinition.new()
	fixture.width = 2
	fixture.height = 2
	fixture.tile_size = 32
	fixture.cells = PackedInt32Array([1, 7, 1, 1])
	fixture.elevations = PackedByteArray([0, 1, 0, 1])
	var geometry := Geometry.build(fixture, catalog)
	if geometry.elevation_edges != PackedVector2Array([Vector2(32, 32), Vector2(32, 64)]): return "Elevation overlay closed valid stairs or missed an impassable rise."
	return ""


func _check_footprints(client: Node) -> String:
	var overlay = client.get_node("DebugOverlay").colliders
	if overlay.footprints.size() != 4: return "Expected two trainers and two character footprints."
	for circle in overlay.footprints:
		var views: Dictionary = client.game_arena.trainer_views if circle.category == "players" else client.game_arena.character_views
		var view = views[circle.entity_id]
		if overlay.to_global(circle.center).distance_to(view.global_position) > 0.01: return "Collision circle is detached from its displayed entity."
		var radius := GameProtocol.TRAINER_RADIUS if circle.category == "players" else 12.0
		if not is_equal_approx(circle.radius, radius): return "Collision circle uses visual size instead of gameplay radius."
	return ""


func _push_key(client: Node, key: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		client.get_viewport().push_input(event, true)


func _click(client: Node, position: Vector2) -> void:
	_pointer(client, position, MOUSE_BUTTON_LEFT)


func _scroll(client: Node, position: Vector2) -> void:
	_pointer(client, position, MOUSE_BUTTON_WHEEL_UP)


func _pointer(client: Node, position: Vector2, button: int) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		client.get_viewport().push_input(event, true)


func _capture(client: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../build/verification/collision-overlay")
	DirAccess.make_dir_recursive_absolute(folder)
	client.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))
