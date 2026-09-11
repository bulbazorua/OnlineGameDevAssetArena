extends SceneTree

const Reader = preload("res://dev/ai/replay_reader.gd")
const Stage = preload("res://dev/ai/replay_stage.gd")
const Content = preload("res://content/game_content.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(15).timeout.connect(func(): push_error("Search replay check did not finish."); quit(1))
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): path = argument.trim_prefix("--fixture=")
	var content := Content.new()
	assert(content.load_catalog().is_empty())
	var reader := Reader.new()
	assert(reader.scan(path, content.fingerprint.hex_encode()), reader.error)
	assert(int(reader.header.schema_version) == 5 and int(reader.header.protocol_version) == Stage.Protocol.HEADER[4])
	var stage := Stage.new()
	stage.content = content
	stage.size = Vector2(900, 700)
	root.add_child(stage)
	var found := {}
	var absent := -1
	var acquired := -1
	var airborne := -1
	var reset_frames := {}
	for index in reader.entries.size():
		var decoded := reader.read_frame(index)
		assert(decoded.error.is_empty(), decoded.error)
		stage.present(decoded.snapshot)
		if decoded.snapshot.characters.size() == 2 and not reset_frames.has(decoded.snapshot.round_id): reset_frames[decoded.snapshot.round_id] = index
		for character in decoded.snapshot.characters:
			var view = stage.views[character.entity_id]
			assert(view.target_alert.visible == character.target_alert)
			var age := float((decoded.snapshot.server_tick - character.target_acquired_tick) & 0xffffffff) / 60.0
			if character.target_alert and age >= 0.1 and age <= 0.25:
				assert(view.body_sprite.position.y < -8, "Recorded target acquisition did not lift the creature body")
				assert(view.surprise_hop.visible and view.surprise_hop.global_position.is_equal_approx(view.global_position), "Recorded shadow left the ground")
				airborne = index
			elif not character.target_alert or age >= 0.36:
				assert(view.body_sprite.position == Vector2.ZERO, "Recorded creature did not land")
			if character.target_alert:
				found[character.owner_id] = true
				acquired = index
			else:
				absent = index
	assert(found.size() == 2 and absent >= 0 and acquired >= 0 and airborne >= 0)
	if "--expect-reset" in OS.get_cmdline_user_args():
		assert(reset_frames.size() == 2, "Search reset was not recorded as a fresh round")
		var reset_index: int = reset_frames.values()[-1]
		var fresh = reader.read_frame(reset_index).snapshot
		assert(fresh.summon_elapsed_ticks < 90 and fresh.characters.all(func(character): return not character.target_alert))
		assert(fresh.characters[0].position.distance_to(fresh.characters[1].position) >= 408)
		stage.present(fresh)
		assert(stage.views.has(fresh.characters[0].entity_id) and stage.views.has(fresh.characters[1].entity_id))
	stage.present(reader.read_frame(acquired).snapshot)
	assert(stage.views.values().any(func(view): return view.target_alert != null and view.target_alert.visible))
	stage.present(reader.read_frame(absent).snapshot)
	var frozen = reader.read_frame(absent).snapshot
	for character in frozen.characters:
		assert(stage.views[character.entity_id].target_alert.visible == character.target_alert)
	stage.present(reader.read_frame(airborne).snapshot)
	var poses := {}
	for character in stage.snapshot.characters: poses[character.entity_id] = stage.views[character.entity_id].body_sprite.position
	stage.present(reader.read_frame(airborne).snapshot)
	for entity_id in poses: assert(stage.views[entity_id].body_sprite.position == poses[entity_id], "Pause changed the creature's jump pose")
	stage.present(reader.read_frame(absent).snapshot)
	stage.present(reader.read_frame(airborne).snapshot)
	for entity_id in poses: assert(stage.views[entity_id].body_sprite.position == poses[entity_id], "Seeking back changed the creature's jump pose")
	stage.queue_free()
	await process_frame
	print("PASS: current-protocol search recording, both target alerts, creature body hops, fixed ground shadows, paused/seeking jump poses, reset rounds and alert absence.")
	quit()
