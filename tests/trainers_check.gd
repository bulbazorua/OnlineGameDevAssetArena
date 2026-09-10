extends "./host_check.gd"


func _host_arguments() -> PackedStringArray:
	return PackedStringArray(["--bind=127.0.0.1", "--port=%d" % port, "--content-dir=" + ProjectSettings.globalize_path("res://content/data"), "--audience-delay=0.35", "--dev", "--dev-p1=archer", "--dev-p2=orc", "--dev-arena=tiny_swords_village"])


func _new_client(audience := false) -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 800)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var client = load("res://main.tscn").instantiate()
	client.get_node("UI/Screens/LobbyScreen").get_node("%HostPort").value = port
	client.get_node("UI/Screens/LobbyScreen").get_node("%JoinAsAudience").button_pressed = audience
	clients.append(client)
	viewport.add_child(client)
	client.game_arena.debug_actions = true
	return client


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 did not connect."
	var second = _new_client()
	var audience = _new_client(true)
	if not await _wait_for(func(): return _entered(first) and _entered(second)): return "Trainers did not enter."
	var spawn: Vector2 = first.network.session.trainers[0].position
	for client in [first, second]:
		var game = client.game_arena
		if game.character_views.size() != 2 or game.trainer_views.size() != 2: return "Arena does not have two trainers and two gladiators."
		for view in game.character_views.values():
			if view.visible: return "Gladiator appeared before summon reveal."
		if game.trainer_views[game._local_entity].animation_set == null: return "Trainer did not use processed art."
		if game.trainer_views[game._local_entity].animator.action != "advise": return "Trainer did not perform its summon gesture."
	_key(first, KEY_D, true)
	await create_timer(0.12).timeout
	if first.network.session.trainers[0].position != spawn or first.game_arena.predicted_position != spawn: return "Movement bypassed the summon lock."
	_key(first, KEY_D, false)
	await _capture(first, "p1-summoning")
	# Presentation must not finish summoning using an independent local timer.
	first.network.set_process(false)
	await create_timer(0.55).timeout
	for view in first.game_arena.character_views.values():
		if view.visible: return "Paused host feed revealed a gladiator using local elapsed time."
	first.network.set_process(true)
	if not await _wait_for(func(): return _entered(audience)): return "Delayed viewer did not enter."
	if audience.network.session.summon_elapsed_ticks >= second.network.session.summon_elapsed_ticks: return "Audience summon timer leaked live time."
	if not await _wait_for(func(): return first.game_arena._summon_display_tick >= 40): return "Materialization did not advance."
	await _capture(first, "p1-materializing")
	if not await _wait_for(func(): return clients.all(func(client): return _entered(client) and client.network.session.summon_elapsed_ticks == 90)): return "Summoning did not finish everywhere."
	await create_timer(0.08).timeout
	for client in clients:
		for character in client.network.session.characters:
			var view = client.game_arena.character_views[character.entity_id]
			if not view.visible or view.modulate.a != 1 or not view.scale.is_equal_approx(Vector2.ONE) or view.animation_set == null: return "Selected gladiator did not fully materialize."
		for effect in client.game_arena.summon_effects.values():
			if effect.visible: return "Completed summon effect remained visible."
	await _capture(first, "p1-ready")
	await _capture(second, "p2-ready")
	_key(first, KEY_D, true)
	_key(second, KEY_A, true)
	await create_timer(0.08).timeout
	if _trainer(first, 1).animator.action != "walk" or _trainer(second, 2).animator.action != "walk": return "Local trainer movement waited for host snapshots."
	if first.game_arena.predicted_position != spawn or first.network.session.trainers[0].position != spawn: return "Trainer translated before its lift and plant poses."
	if _trainer(audience, 1).animator.action != "idle": return "Audience saw trainer movement early."
	await create_timer(0.6).timeout
	_key(first, KEY_D, false)
	_key(second, KEY_A, false)
	if first.game_arena.camera.position.distance_to(_trainer(first, 1).position) > 0.1: return "Trainer was not centered."
	await create_timer(0.6).timeout
	for client in clients:
		if client.network.session.trainers[0].position.x <= spawn.x + 20: return "Trainer movement did not replicate."
		if client.network.session.characters.any(func(entity): return entity.applied_input_sequence != 0): return "Gladiator consumed trainer input."
	var late = _new_client(true)
	if not await _wait_for(func(): return _entered(late)): return "Late audience missed active entities."
	await create_timer(0.08).timeout
	if late.network.session.summon_elapsed_ticks != 90 or late.game_arena.summon_effects.values().any(func(effect): return effect.visible): return "Late audience replayed an old summon."
	audience.game_arena.set_camera_owner(1)
	audience.game_arena.camera.zoom_by(2)
	await _capture(audience, "audience-follow")
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.phase == SessionSnapshot.Phase.LOBBY)): return "Reset did not propagate."
	for client in clients:
		if not client.game_arena.trainer_views.is_empty() or not client.game_arena.character_views.is_empty() or not client.game_arena.summon_effects.is_empty(): return "Reset retained trainer, gladiator or effect."
	# Replay and cancel during the next summon; no delayed callback may respawn art.
	first.network.request_start_selection()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.SELECTING): return "Replay selection failed."
	first.network.request_character(5)
	second.network.request_character(6)
	if not await _wait_for(func(): return first.network.session.players[0].character_id == 5 and second.network.session.players[1].character_id == 6): return "Replay picks failed."
	first.network.request_set_ready(5, true)
	second.network.request_set_ready(6, true)
	if not await _wait_for(func(): return _entered(first), 7000): return "Replay did not summon."
	if first.network.session.summon_elapsed_ticks >= 36: return "New round retained the old summon clock."
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.phase == SessionSnapshot.Phase.LOBBY)): return "Summon cancellation did not reach audience."
	await create_timer(1.6).timeout
	for client in clients:
		if not client.game_arena.character_views.is_empty() or not client.game_arena.trainer_views.is_empty() or not client.game_arena.summon_effects.is_empty(): return "Cancelled summon recreated an entity."
	return ""


func _entered(client: Node) -> bool:
	return client.network.session != null and client.network.session.phase == SessionSnapshot.Phase.IN_ARENA


func _trainer(client: Node, owner: int):
	for view in client.game_arena.trainer_views.values():
		if view.player_id == owner: return view
	return null


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	client.game_arena._unhandled_key_input(event)


func _capture(client: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../build/verification/trainers")
	DirAccess.make_dir_recursive_absolute(folder)
	client.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))
