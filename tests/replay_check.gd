extends SceneTree

const Reader = preload("res://dev/ai/replay_reader.gd")
var failed := false
var recording := ""
var artifacts := ""
var app: Control
var temporary: Array[String] = []

func check(condition: bool, message: String) -> bool:
	if not condition: failed = true; push_error(message)
	return condition

func _initialize() -> void:
	Engine.max_fps = 120
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--replay="): recording = argument.trim_prefix("--replay=")
		if argument.begins_with("--artifacts="): artifacts = argument.trim_prefix("--artifacts=")
	_run.call_deferred()

func until(condition: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call() and Time.get_ticks_msec() < deadline: await process_frame
	return check(condition.call(), message)

func fixture(name: String, text: String) -> String:
	var path := recording.get_base_dir().path_join("check-%s.replay.jsonl" % name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	temporary.append(path)
	return path

func pose_signature() -> String:
	var poses := []
	for id in app.stage.views:
		var view = app.stage.views[id]
		poses.append([id, view.position, view.presented_frame, view.animator.elapsed, view.visible])
	return str([app.current_index, app.snapshot.server_tick, poses])

func seek(index: int) -> bool:
	app.seek_frame(index)
	return await until(func(): return app.current_index == index, "Seek did not reach frame %d" % index)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or artifacts.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifacts.path_join(name + ".png"))

func _run() -> void:
	app = load("res://dev/ai/replay_window.tscn").instantiate()
	root.add_child(app)
	if not await until(func(): return app.current_index == 0, "Initial recording did not open: " + recording): _finish(); return
	var reader := Reader.new()
	var fingerprint: String = app.content.fingerprint.hex_encode()
	if not check(reader.scan(recording, fingerprint), "Production replay rejected: " + reader.error): _finish(); return
	check(reader.warning.is_empty(), "Gracefully closed production recording is incomplete: " + reader.warning)
	var active := -1
	var first_trainer := Vector2.INF
	var first_creature := Vector2.INF
	var trainer_moved := false
	var creature_moved := false
	for index in reader.entries.size():
		var result := reader.read_frame(index)
		if not check(result.error.is_empty(), "Invalid recorded frame: " + result.error): _finish(); return
		var state: SessionSnapshot = result.snapshot
		if state.phase != SessionSnapshot.Phase.IN_ARENA: continue
		if first_trainer == Vector2.INF:
			first_trainer = state.trainers[0].position
			first_creature = state.characters[0].position
		trainer_moved = trainer_moved or state.trainers[0].position != first_trainer
		creature_moved = creature_moved or state.characters[0].position != first_creature
		if result.frame.ai.size() == 2 and state.summon_elapsed_ticks == 90: active = index
	check(trainer_moved, "Fixture contains no actual recorded trainer movement.")
	# Integration captures a full wander cycle; the 60-tick writer unit fixture
	# intentionally ends before some seeded idle deadlines.
	if reader.entries.size() > 300: check(creature_moved, "Fixture contains no actual creature movement.")
	if not check(active > 0, "No frame with both creature traces."): _finish(); return
	await seek(active)
	var expected := reader.read_frame(active)
	check(app.frame.packet_hex == expected.frame.packet_hex, "Seek displayed a different world packet.")
	for entity in app.snapshot.trainers + app.snapshot.characters:
		check(app.stage.views[entity.entity_id].position == entity.position, "Rendered entity differs from selected authoritative position.")
	var paused := pose_signature()
	await create_timer(0.3).timeout
	check(pose_signature() == paused, "Pause advanced the world or animation.")
	app.stage.focus_owner(1)
	await capture("replay-arena-p1")
	app.stage.overview()
	await capture("replay-arena-overview")
	for owner in [1, 2]:
		app._tabs.current_tab = owner
		await process_frame
		check(app._traces[owner].input.tick == app.snapshot.server_tick, "AI panel is on a different tick.")
		var graph: Control = app._graphs[owner - 1]
		for node in graph.nodes:
			if node.parent > 0: check(graph.positions[int(node.parent)].y < graph.positions[int(node.id)].y, "Graph does not branch downward.")
		app.step_trace(owner, -100)
		check(graph.event_count == 0, "First event did not rewind the graph.")
		app.step_trace(owner, 1)
		check(graph.event_count == 1, "Single event stepping skipped a node.")
		app.step_trace(owner, 100)
		graph.center_root()
		await capture("replay-tree-p%d" % owner)
	app._tabs.current_tab = 0
	await seek(maxi(0, active - 30))
	await seek(active)
	check(pose_signature() == paused, "Backward then forward seek did not restore identical poses.")
	await seek(0)
	app.speed = 2.0
	app.toggle_play()
	await create_timer(0.2).timeout
	app.toggle_play()
	check(app.current_index > 4 and not app.playing, "Play/speed/pause did not advance recorded frames.")
	paused = pose_signature()
	await create_timer(0.15).timeout
	check(pose_signature() == paused, "A pending worker result advanced playback after pause.")
	await seek(reader.entries.size() - 1)
	app.toggle_play()
	await until(func(): return app.current_index < reader.entries.size() - 1, "Play at end did not restart.")
	if app.playing: app.toggle_play()
	var header := JSON.stringify(reader.header) + "\n"
	var first: Dictionary = reader.read_frame(0).frame
	var second: Dictionary = reader.read_frame(1).frame
	var probe := Reader.new()
	check(not probe.scan(recording, "0".repeat(64)), "Content mismatch was accepted.")
	var partial := fixture("partial", header + JSON.stringify(first) + "\n{\"kind\":")
	check(probe.scan(partial, fingerprint) and not probe.warning.is_empty() and probe.entries.size() == 1, "Incomplete final line was not recovered/reported.")
	for mutation in [
		func(value): value.tick += 1,
		func(value): value.packet_hex = "xx",
		func(value): value.ai = [expected.frame.ai[0], expected.frame.ai[0]],
		func(value): value.ai = [expected.frame.ai[0]],
	]:
		var broken: Dictionary = first.duplicate(true)
		mutation.call(broken)
		var path := fixture("invalid-%d" % temporary.size(), header + JSON.stringify(broken) + "\n")
		check(not probe.scan(path, fingerprint), "Malformed or mismatched frame was accepted.")
	check(not probe.scan(fixture("interior", header + JSON.stringify(first) + "\ninvalid\n" + JSON.stringify(second) + "\n"), fingerprint), "Interior corruption was accepted.")
	check(not probe.scan(fixture("order", header + JSON.stringify(second) + "\n" + JSON.stringify(first) + "\n"), fingerprint), "Out-of-order frames were accepted.")
	check(not probe.scan(fixture("large-line", header + "x".repeat(Reader.MAX_LINE + 1)), fingerprint), "Oversized line was accepted.")
	var mismatched: Dictionary = reader.header.duplicate(true)
	mismatched.schema_version = 999
	check(not probe.scan(fixture("schema", JSON.stringify(mismatched) + "\n"), fingerprint), "Unknown schema was accepted.")
	var gap: Dictionary = second.duplicate(true)
	gap.sequence = first.sequence + 2
	var gap_path := fixture("gap", header + JSON.stringify(first) + "\n" + JSON.stringify(gap) + "\n")
	check(probe.scan(gap_path, fingerprint) and probe.entries[1].gap_before, "Lost frame was not detected.")
	app.open_recording(gap_path)
	await until(func(): return app.current_index == 0, "Gap recording did not load.")
	app.toggle_play()
	await create_timer(0.15).timeout
	check(not app.playing and app.current_index == 0 and "gap" in app._notice, "Playback silently crossed a missing frame.")
	await seek(1)
	check(app.snapshot.server_tick == int(gap.tick), "Explicit seek past gap failed.")
	var absent: Dictionary = expected.frame.duplicate(true)
	absent.ai = []
	app.open_recording(fixture("no-ai", header + JSON.stringify(absent) + "\n"))
	await until(func(): return app.current_index == 0, "Missing-trace recording did not load.")
	for owner in [1, 2]:
		app._tabs.current_tab = owner
		await process_frame
		check(not app._graphs[owner - 1].visible and app._trace_labels[owner - 1].text.begins_with("No P"), "Missing AI trace was replaced by a previous one.")
	if not artifacts.is_empty():
		var output := FileAccess.open(artifacts.path_join("replay-check.json"), FileAccess.WRITE)
		output.store_string(JSON.stringify({"passed": not failed, "frames": reader.entries.size(), "trainer_moved": trainer_moved, "creature_moved": creature_moved, "graphical": DisplayServer.get_name() != "headless"}))
	_finish()

func _finish() -> void:
	if app != null:
		root.remove_child(app)
		app.free()
	for path in temporary: DirAccess.remove_absolute(path)
	if not failed: print("PASS: recorded world and AI identity, movement, seek, frozen poses, play/speed/restart, graphs, gaps, missing traces, bounded malformed-file handling.")
	quit(1 if failed else 0)
