extends "./trainers_check.gd"

const Model = preload("./trainer_run_model.gd")
const Stage = preload("res://dev/ai/replay_stage.gd")
const ReplayReader = preload("res://dev/ai/replay_reader.gd")
var recording_directory := ""


func _host_arguments() -> PackedStringArray:
	var arguments := super._host_arguments()
	arguments[arguments.find("--dev-arena=tiny_swords_village")] = "--dev-arena=meadow_crossing"
	recording_directory = ProjectSettings.globalize_path("res://../build/verification/trainers/run-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(recording_directory)
	arguments.append_array(["--dev-ai-dir=" + recording_directory, "--dev-ai-run=trainer-run-qa"])
	return arguments


func _check() -> String:
	var content := GameContent.new()
	var failure := content.load_catalog()
	if not failure.is_empty(): return failure
	failure = Model.check(content)
	if not failure.is_empty(): return failure
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 did not connect."
	var second = _new_client()
	var audience = _new_client(true)
	if not await _wait_for(func(): return clients.all(func(client): return _entered(client) and client.network.session.summon_elapsed_ticks == 90)): return "Run QA arena did not finish summoning."
	var origin: Vector2 = first.network.session.trainers[0].position
	_key(first, KEY_SPACE, true)
	await create_timer(0.12).timeout
	if first.network.session.trainers[0].energy != 600: return "Space without movement spent energy."
	_key(first, KEY_D, true)
	if not await _wait_for(func(): return first.network.session.trainers[0].locomotion == 2): return "Space plus movement did not run on the host."
	var start_tick: int = first.network.session.trainers[0].movement_start_tick
	if not await _wait_for(func(): return clients.all(func(client): return _trainer(client, 1).animator.action == "run")): return "Run animation did not reach local, remote and delayed audience views."
	var recorded: SessionSnapshot = second.network.session
	if not first.game_arena.get_node("%TrainerEnergy").visible or audience.game_arena.get_node("%TrainerEnergy").visible: return "Energy HUD is missing or shown to an audience."
	await _capture(first, "trainer-running")
	await _capture(audience, "audience-running")
	if not await _wait_for(func(): return first.network.session.trainers[0].run_exhausted, 7000): return "Continuous run never depleted its energy."
	var spent = first.network.session.trainers[0]
	if ((first.network.session.server_tick - start_tick) & 0xffffffff) < 307 or spent.position.x - origin.x < 1199: return "Networked run depleted before five seconds."
	if first.network.session.trainers[1].energy != 600: return "P1 used P2's energy."
	_key(first, KEY_D, false)
	_key(first, KEY_A, true)
	await create_timer(0.25).timeout
	if _trainer(first, 1).animator.action != "walk": return "Empty energy kept the local run animation."
	await _capture(first, "trainer-exhausted")
	if not await _wait_for(func(): return first.network.session.trainers[0].energy >= 120, 4000): return "Walking did not restore energy."
	if not first.network.session.trainers[0].run_exhausted: return "Holding Space restarted running automatically."
	_key(first, KEY_SPACE, false)
	if not await _wait_for(func(): return not first.network.session.trainers[0].run_exhausted): return "Releasing Space did not clear recovered exhaustion."
	_key(first, KEY_SPACE, true)
	if not await _wait_for(func(): return first.network.session.trainers[0].locomotion == 2): return "Recovered trainer could not run again."
	first.game_arena._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	if not await _wait_for(func(): return first.network.session.trainers[0].input_mask == 0 and first.network.session.trainers[0].locomotion == 0): return "Losing focus left Space held."
	failure = await _check_replay_and_hop(content, recorded)
	if not failure.is_empty(): return failure
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return clients.all(func(client): return client.network.session.phase == SessionSnapshot.Phase.LOBBY)): return "Run QA reset did not reach all clients."
	if first.game_arena.get_node("%TrainerEnergy").visible: return "Old energy remained visible after leaving the round."
	return ""


func _check_replay_and_hop(content: GameContent, recorded: SessionSnapshot) -> String:
	var reader := ReplayReader.new()
	if not reader.scan(recording_directory.path_join("match.replay.jsonl"), content.fingerprint.hex_encode()): return reader.error
	var found := false
	for index in reader.entries.size():
		if reader.entries[index].tick != recorded.server_tick: continue
		var frame: Dictionary = reader.read_frame(index)
		if not frame.error.is_empty(): return frame.error
		var trainer = frame.snapshot.trainers[0]
		if trainer.energy != recorded.trainers[0].energy or trainer.movement_start_tick != recorded.trainers[0].movement_start_tick or trainer.position != recorded.trainers[0].position: return "Recorded trainer energy or movement differs from the received host tick."
		recorded = frame.snapshot
		found = true
		break
	if not found: return "The host did not record the trainer's running sample."
	var stage := Stage.new()
	stage.content = content
	stage.size = Vector2(900, 700)
	root.add_child(stage)
	stage.present(recorded)
	var entity: int = recorded.trainers[0].entity_id
	if stage.views[entity].animator.action != "run": stage.queue_free(); return "Replay stage lost trainer running."
	var pose: int = stage.views[entity].presented_frame
	stage.present(recorded)
	if stage.views[entity].presented_frame != pose: stage.queue_free(); return "Paused replay restarted the run animation."
	stage.queue_free()
	if DisplayServer.get_name() == "headless": return ""
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 800)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1000, 800)
	background.color = Color("334456")
	viewport.add_child(background)
	for row in 2:
		var ground := Line2D.new()
		ground.points = PackedVector2Array([Vector2(20, 370 + row * 400), Vector2(980, 370 + row * 400)])
		ground.default_color = Color("708399")
		ground.width = 1
		viewport.add_child(ground)
		for index in 4:
			var view := Stage.Character.new()
			var definition_id := 5 + row
			content.configure_character(view, definition_id, row + 1, content.by_id[definition_id].footprint_radius)
			viewport.add_child(view)
			view.position = Vector2(125 + index * 250, 370 + row * 400)
			view.scale = Vector2.ONE * 3
			view.present_locomotion("idle", "east", 0)
			view.present_target_alert(true, [0.0, 0.09, 0.18, 0.36][index])
			var label := Label.new()
			label.position = Vector2(index * 250 + 45, 15 + row * 400)
			label.text = content.by_id[definition_id].display_name + " · " + ["start", "rising", "peak", "landed"][index]
			viewport.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../build/verification/trainers")
	DirAccess.make_dir_recursive_absolute(directory)
	var capture := viewport.get_texture().get_image()
	capture.save_png(directory.path_join("target-found-hop.png"))
	var shadow_visible := true
	for row in 2:
		var pixel := capture.get_pixel(625, 373 + row * 400)
		shadow_visible = shadow_visible and pixel.r < background.color.r * 0.8 and pixel.b < background.color.b * 0.8
	viewport.queue_free()
	if not shadow_visible: return "The ground shadow is not visible beneath the airborne creature in the rendered image."
	return ""
