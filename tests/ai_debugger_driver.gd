extends SceneTree

# Test-only driver. The real launcher never enables this command reader.
var app: Node
var directory := ""
var slot := ""
var sequence := 0
var busy := false


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
	var path := directory.path_join("ai-driver.json")
	if not FileAccess.file_exists(path): return
	var command = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not command is Dictionary or int(command.get("sequence", 0)) <= sequence: return
	if app.reader.records.is_empty(): return
	sequence = int(command.sequence)
	busy = true
	var record: Dictionary = app.reader.records.back()
	for candidate in app.reader.records:
		if candidate.decision_reason == "Choosing_Direction": record = candidate
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
	app._filter.text = "candidate"
	app._rebuild_timeline()
	assert(app._visible_records.size() > 0)
	app._filter.text = ""
	app._rebuild_timeline()
	app._graph.fit_all()
	await _capture("tree")
	var tabs: TabContainer = app._spatial.get_parent()
	tabs.current_tab = 3
	await _capture("spatial")
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
	file.store_string(JSON.stringify({"sequence": sequence, "passed": true, "worker_id": record.worker_id,
		"decision_reason": record.decision_reason, "branch_count": record.nodes.size(), "pinned_sequence": pinned,
		"browse_p95_us": times[28], "drawn_rows": app._timeline.drawn_rows}))
	file.close()
	busy = false
