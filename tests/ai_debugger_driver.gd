extends SceneTree

# Test-only driver. The real launcher never enables this command reader.
const Reader = preload("res://dev/ai/trace_reader.gd")
var app: Node
var directory := ""
var slot := ""
var sequence := 0
var busy := false
var early_pause := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-session-dir="): directory = argument.trim_prefix("--dev-session-dir=")
		elif argument.begins_with("--dev-slot="): slot = argument.trim_prefix("--dev-slot=")
	_start.call_deferred()


func _start() -> void:
	app = load("res://dev/ai/ai_debug_window.tscn").instantiate()
	root.add_child(app)
	var timer := Timer.new()
	app.add_child(timer)
	timer.wait_time = 0.1
	timer.timeout.connect(_command)
	timer.start()


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(slot + "-" + name + ".png"))


func _command() -> void:
	if busy: return
	if slot == "ai2" and not early_pause and app.reader.records.is_empty():
		# Mirror the reviewed failure: browsing starts before the first decision exists.
		early_pause = true
		app._timeline.browse_started.emit()
		assert(app.paused and app.selected.is_empty())
		return
	var path := directory.path_join("ai-driver.json")
	if not FileAccess.file_exists(path): return
	var command = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not command is Dictionary or int(command.get("sequence", 0)) <= sequence: return
	if app.reader.records.is_empty(): return
	sequence = int(command.sequence)
	busy = true
	if early_pause:
		# The early pause pinned the first decision while the live history kept growing.
		assert(app.paused and int(app.selected.sequence) == int(app.reader.records.front().sequence) and app.reader.records.size() > 1)
	# Prefer a real attention branch driven by evidence: first a peripheral orient,
	# else an observation, else the newest record.
	var record: Dictionary = app.reader.records.back()
	var observed: Dictionary = {}
	for candidate in app.reader.records:
		if candidate.decision_reason == "Orient" and observed.is_empty(): observed = candidate
	if observed.is_empty():
		for candidate in app.reader.records:
			if candidate.decision_reason == "Observe": observed = candidate
	if not observed.is_empty(): record = observed
	app.select_record(record)
	app.restart_decision()
	assert(app.paused and app.event_cursor == 0 and app._graph.event_count == 0)
	app.step_event(1)
	assert(app.event_cursor == 1 and app._graph.nodes[0].stage == "Input")
	app.step_event(1)
	assert(app.event_cursor == 2)
	app.step_event(-1)
	assert(app.event_cursor == 1)
	var pinned: int = app.selected.sequence
	var live_before: int = app.live_reader.last_sequence
	await create_timer(0.8).timeout
	assert(app.selected.sequence == pinned and app.live_reader.last_sequence > live_before)
	app.select_record(record)
	for node in record.nodes:
		if int(node.parent) > 0:
			assert(app._graph.positions[int(node.id)].y > app._graph.positions[int(node.parent)].y)
	app._filter.text = "sample"
	app._rebuild_timeline()
	assert(app._visible_records.size() > 0)
	app._filter.text = ""
	app._rebuild_timeline()
	app._graph.fit_all()
	await _capture("tree")
	var tabs: TabContainer = app._spatial.get_parent()
	tabs.current_tab = 3
	assert(app._vision.record == record and int(record.schema_version) == 5)
	# Stepping never reveals memory changes before their node.
	app.restart_decision()
	app.step_event(1)
	tabs.current_tab = 3
	app._render_active_tab()
	assert(app._vision.event_count == 1 and not app._vision._revealed("Age private memory", "State"))
	app.step_event(100)
	app._render_active_tab()
	assert(app._vision._revealed("Age private memory", "State") and app._vision._revealed("Host resolved", "Outcome"))
	await _capture("vision")
	var evidence_nodes := 0
	for node in record.nodes:
		if not Reader.evidence_for(record, int(node.reference), int(node.subject)).is_empty(): evidence_nodes += 1
	assert(evidence_nodes > 0 or record.input.senses.vision.status != "Sampled")
	app._host_toggle.button_pressed = true
	app._render_active_tab()
	assert(app._vision.host_view)
	await _capture("vision-host")
	app._host_toggle.button_pressed = false
	tabs.current_tab = 0
	app.step_decision(-1)
	assert(app.event_cursor == 0)
	app.open_journal(app.trace_dir.path_join("ai-%d.jsonl" % app.observer_id))
	var deadline := Time.get_ticks_msec() + 10000
	while app._journal_loading and Time.get_ticks_msec() < deadline: await process_frame
	assert(app.offline and app.paused and app.event_cursor == 0)
	app.go_live()
	assert(not app.offline and not app.paused and app.selected.sequence == app.live_reader.last_sequence)
	# Exercise browsing at the full retention limit using copies of actual traces.
	app.paused = true
	var saved: Array[Dictionary] = app.reader.records
	var full: Array[Dictionary] = []
	for i in app.Reader.HISTORY_LIMIT:
		var copy: Dictionary = record.duplicate(true)
		copy.sequence = i + 1
		full.append(copy)
	app.reader.records = full
	app._rebuild_timeline()
	await process_frame
	var rebuilds: int = app.timeline_rebuilds
	var times: Array[int] = []
	for i in 30:
		var start := Time.get_ticks_usec()
		app.select_record(full[100 + i])
		times.append(Time.get_ticks_usec() - start)
		await process_frame
	times.sort()
	assert(app.timeline_rebuilds == rebuilds, "Selecting a row rebuilt the history")
	assert(app._timeline.drawn_rows < 40, "History rendering is not virtualized")
	assert(times[28] < 12000, "Selection exceeds the interactive budget")
	app.reader.records = saved
	app.go_live()
	app._write_status()
	var file := FileAccess.open(directory.path_join("driver-" + slot + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence": sequence, "passed": true, "worker_id": record.worker_id, "early_pause": early_pause,
		"decision_reason": record.decision_reason, "branch_count": record.nodes.size(), "pinned_sequence": pinned,
		"browse_p95_us": times[28], "drawn_rows": app._timeline.drawn_rows, "evidence_nodes": evidence_nodes,
		"sample_tick": record.input.senses.vision.sample_tick, "decision_tick": record.input.tick}))
	file.close()
	busy = false
