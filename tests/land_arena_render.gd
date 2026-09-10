extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var content = load("res://content/game_content.gd").new()
	var error: String = content.load_catalog()
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://../build/verification/land-previews")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 896)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://world/arena_world.tscn").instantiate()
	viewport.add_child(world)
	for arena in content.arena_catalog.arenas:
		world.load_arena(content, arena)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(arena.key + ".png"))
	viewport.remove_child(world)
	world.queue_free()
	error = await _check_building_occlusion(content, viewport, output)
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	viewport.queue_free()
	var selection = load("res://ui/arena_select_screen.tscn").instantiate()
	root.add_child(selection)
	selection.configure(content)
	var snapshot = load("res://session/session_snapshot.gd").new(3, 1)
	snapshot.phase = 1
	snapshot.map_id = 4
	snapshot.players[0].character_id = 3
	snapshot.players[1].character_id = 4
	selection.display_session(snapshot, 0)
	selection._show_terrain(Vector2i(8, 8), content.arena_catalog.terrains_by_id[10])
	for size in [Vector2i(900,800), Vector2i(800,760)]:
		root.size = size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		rendered.save_png(output.path_join("selection-%dx%d.png" % [size.x, size.y]))
		var preview_world = selection.preview.world
		var grass_pixel: Vector2 = preview_world.get_global_transform_with_canvas() * preview_world.definition.cell_center(Vector2i(20, 17))
		if rendered.get_pixelv(Vector2i(grass_pixel)).g < 0.3:
			push_error("Selection backdrop hides the map's ground layers.")
			quit(1)
			return
		var button: Control = selection.get_node("%DisconnectButton")
		if not root.get_visible_rect().encloses(button.get_global_rect()):
			push_error("Arena selection controls overflow the window.")
			quit(1)
			return
	print("PASS: rendered four land previews, building occlusion, and visible selection terrain at default/minimum size in ", output)
	quit(0)


func _check_building_occlusion(content, viewport: SubViewport, output: String) -> String:
	# Use the actual playable scene hierarchy; equal z values must interleave
	# characters and buildings by their feet, despite separate parent nodes.
	var arena = load("res://world/game_arena.tscn").instantiate()
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	arena.visible = true
	viewport.add_child(arena)
	arena.world.show_spawn_markers = false
	arena.world.load_arena(content, content.arena_catalog.arenas_by_id[4])
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := viewport.get_texture().get_image()
	var actor = load("res://characters/character_view.tscn").instantiate()
	actor.configure(content.visuals[1], 1, 12.0)
	arena.get_node("Characters").add_child(actor)
	actor.position = Vector2(272, 250) # Behind the west castle's opaque roof.
	await process_frame
	await RenderingServer.frame_post_draw
	var behind := viewport.get_texture().get_image()
	behind.save_png(output.path_join("village-character-behind.png"))
	if not behind.get_pixel(272, 250).is_equal_approx(baseline.get_pixel(272, 250)):
		return "A character behind the castle draws over its roof."
	actor.position = Vector2(272, 330) # Feet below the castle anchor at y=320.
	await process_frame
	await RenderingServer.frame_post_draw
	var front := viewport.get_texture().get_image()
	front.save_png(output.path_join("village-character-in-front.png"))
	var player_color := Color("58a6ff")
	var actual := front.get_pixel(272, 322)
	if absf(actual.r - player_color.r) > 0.02 or absf(actual.g - player_color.g) > 0.02 or absf(actual.b - player_color.b) > 0.02:
		return "A character in front of the castle is hidden by its art."
	viewport.remove_child(arena)
	arena.queue_free()
	return ""
