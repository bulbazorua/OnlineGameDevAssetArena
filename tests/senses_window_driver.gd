extends SceneTree

var app: Node
var directory := ""
var slot := ""
var busy := false
var sequence := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-session-dir="): directory = argument.trim_prefix("--dev-session-dir=")
		elif argument.begins_with("--dev-slot="): slot = argument.trim_prefix("--dev-slot=")
	_start.call_deferred()


func _start() -> void:
	app = load("res://dev/senses/senses_window.tscn").instantiate()
	root.add_child(app)
	var timer := Timer.new()
	app.add_child(timer)
	timer.wait_time = 0.1
	timer.timeout.connect(_command)
	timer.start()


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(slot + "-" + label + ".png"))


func _command() -> void:
	if busy or app.record.is_empty(): return
	var path := directory.path_join("senses-driver.json")
	if not FileAccess.file_exists(path): return
	var command = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not command is Dictionary or int(command.get("sequence", 0)) <= sequence: return
	sequence = int(command.sequence)
	busy = true
	if command.get("memory_only", false):
		await _check_exploration_memory()
	elif command.get("capture_only", false):
		await _capture("live")
		app._sense_selector.current_tab = app.OLFACTION_TAB
		await _capture("olfaction")
		app._sense_selector.current_tab = 0
	elif command.get("watch_olfaction", false):
		app._sense_selector.current_tab = app.OLFACTION_TAB
		app.scent_metrics = app.Metrics.new()
	else:
		await _check_live_ui()
		await _check_olfaction_page()
		await _check_fixture_transitions()
		await _check_staleness()
		app.metrics = app.Metrics.new()
		app.scent_metrics = app.Metrics.new()
	app._write_status()
	var file := FileAccess.open(directory.path_join("driver-" + slot + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence": sequence, "passed": true, "sample_key": app._sample_key}))
	file.close()
	busy = false


func _check_live_ui() -> void:
	assert(app.live_status == "LIVE" and app.feed.error.is_empty())
	assert(app.record.owner_id == app.owner_id and app.record.entity_id == app.record.vision.observer)
	_check_controls(app)
	assert(app._table.get_root().get_child_count() == app.readings.size())
	assert(app.readings.size() <= 6 and app._sense_selector.tab_count == 6)
	assert(app._table.get_global_rect().end.x <= app.size.x, "Readings table extends beyond the viewport")
	for index in [1, 3, 4]:
		app._sense_selector.current_tab = index
		assert(app._notice.visible and not app._vision_layout.visible and not app._scent_layout.visible and "Not implemented" in app._notice.text)
	await _capture("unsupported")
	app._sense_selector.current_tab = 0
	var before: String = app._sample_key
	await create_timer(0.35).timeout
	assert(app._sample_key != before)
	var item: TreeItem = app._table.get_root().get_first_child()
	if item != null:
		item.select(0)
		app._select_reading()
		assert(app._vision.selected_number > 0 and not app._selected_reference.is_empty())
		await create_timer(0.25).timeout
		assert(app._vision.selected_number > 0, "Selection disappeared on the next sample")
	await _capture("live")
	var original_size: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	assert(app._table.get_global_rect().end.x <= app.size.x, "Minimum window clips the table")
	await _capture("minimum")
	root.size = original_size
	app.set_filter("Focused", false)
	assert(not app._vision.show_focus and app._vision.show_periphery)
	app.set_filter("Focused", true)
	app.set_filter("Peripheral", false)
	assert(app._vision.show_focus and not app._vision.show_periphery)
	app.set_filter("Peripheral", true)
	app._sense_selector.current_tab = app.MEMORY_TAB
	assert(app._memory.visible and not app._vision_layout.visible and not app._notice.visible)
	assert(app._memory.memory.is_empty(), "Stationary Observe fixture invented exploration memory")
	app._sense_selector.current_tab = 0


# The Olfaction page shows the delivered nose sample only: anonymous class rows,
# zones at the sensor's resolution, and its own live/stale clock.
func _check_olfaction_page() -> void:
	app._sense_selector.current_tab = app.OLFACTION_TAB
	assert(app._scent_layout.visible and not app._vision_layout.visible and not app._notice.visible)
	_check_controls(app._scent_layout)
	assert(app.olfaction_status() == "LIVE" and app.record.olfaction.status == "Sampled")
	assert(app._scent_table.get_root().get_child_count() == app.scent_readings.size())
	assert(app.scent_readings.size() <= 2)
	for row in app.scent_readings:
		assert(row.class in ["Human", "Orc"] and row.strength != "None")
		for key in ["position", "subject", "entity_id", "kind"]: assert(not row.has(key), "Scent row leaked " + key)
	assert(app._scent.sample.sample_id == app.record.olfaction.sample_id, "The spatial view shows another nose sample")
	assert("reach" in app._scent_pose.text and "Nose sample #" in app._scent_timing.text)
	var before: String = app._scent_key
	await create_timer(0.45).timeout
	assert(app._scent_key != before, "The nose sample did not advance")
	var item: TreeItem = app._scent_table.get_root().get_first_child()
	if item != null:
		item.select(0)
		app._select_scent_reading()
		assert(app._scent.selected_number > 0 and "scent" in app._scent_details.text)
	await _capture("olfaction")
	var original_size: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	await process_frame
	assert(app._scent_table.get_global_rect().end.x <= app.size.x, "Minimum window clips the scent table")
	await _capture("olfaction-minimum")
	root.size = original_size
	app.set_scent_filter("Human", false)
	assert(not app._scent.show_classes.Human and app._scent.show_classes.Orc)
	app.set_scent_filter("Human", true)
	app._sense_selector.current_tab = 0


func _check_exploration_memory() -> void:
	app._sense_selector.current_tab = app.MEMORY_TAB
	assert(app._memory.visible and not app._vision_layout.visible and not app._notice.visible)
	_check_controls(app)
	assert(app._memory.live_status == "LIVE" and app._memory.memory.owner_id == app.owner_id)
	assert(app._memory.memory.visits.size() > 0 and app._memory._table.get_root().get_child_count() == app._memory.memory.visits.size())
	var first: Dictionary = app._memory.memory.visits[0]
	if DisplayServer.get_name() == "headless": app._memory._select_region(first.key)
	else:
		await RenderingServer.frame_post_draw
		var map: Control = app._memory._map
		var center: Vector2 = (Vector2(first.region[0], first.region[1]) + Vector2.ONE * 0.5) * app._memory.memory.region_size
		_click(map.get_global_transform() * (map._origin + center * map._scale))
	assert(app._memory.selected_key == first.key and app._memory._map.selected_key == first.key)
	await create_timer(0.25).timeout
	assert(app._memory.selected_key == first.key, "Visit selection was lost on refresh")
	if DisplayServer.get_name() != "headless" and app._memory.memory.visits.size() > 1:
		var table: Tree = app._memory._table
		var item := table.get_root().get_child(1)
		_click(table.get_global_transform() * table.get_item_area_rect(item).get_center())
		assert(app._memory.selected_key == item.get_metadata(0).key, "Row click did not select its remembered region")
	await _capture("exploration-memory")
	var original: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	assert(app._memory._table.get_global_rect().end.x <= app.size.x, "Minimum window clipped the memory table")
	await _capture("exploration-memory-minimum")
	root.size = original


func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _check_controls(parent: Node) -> void:
	for node in parent.get_children():
		assert(not node is TextEdit and not node is GraphEdit and not node is ItemList, "History UI in the live monitor: " + str(node.get_path()))
		_check_controls(node)


func _publish_fixture(value: Dictionary, path: String) -> void:
	value.published_us = maxi(int(value.published_us), int(app.feed.published_us) + 1)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	app._poll()
	assert(app.feed.error.is_empty(), app.feed.error)


func _check_fixture_transitions() -> void:
	var live: String = app.trace_dir
	var fixture_dir := directory.path_join("fixture-" + slot)
	DirAccess.make_dir_recursive_absolute(fixture_dir)
	var value: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(live.path_join("senses.json")))
	app.trace_dir = fixture_dir
	var target: Dictionary = value.records[app.owner_id - 1]
	var sample: Dictionary = target.vision
	assert(sample.focused_count > 0)
	var zero_sighting := {"observation_id": 0, "subject": 0, "kind": "Creature", "appearance_id": 0, "position": [0, 0], "facing": "North", "locomotion": "Idle"}
	for index in 3: sample.focused[index] = zero_sighting.duplicate(true)
	sample.focused_count = 0
	sample.sample_id += 1
	sample.cue_count = 1
	sample.cues[0] = {"observation_id": 1, "sector": 1, "band": "Far"}
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.readings.size() == 1 and app.readings[0].quality == "Peripheral")
	for key in ["position", "subject", "kind", "appearance_id", "locomotion", "facing", "distance"]:
		assert(not app.readings[0].has(key), "Peripheral cue leaked focused data: " + key)
	assert(app._vision.selected_number == 0 and not "Position" in app._details.text)
	await _capture("fixture-peripheral")
	for heartbeat in 8:
		await create_timer(0.15).timeout
		_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.live_status == "STALE" and not app.feed.is_stale(), "Heartbeat disguised a stalled sensor as live")
	sample.sample_id += 1
	sample.cue_count = 0
	sample.cues[0] = {"observation_id": 0, "sector": 0, "band": "Near"}
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.readings.is_empty() and app._table.get_root().get_child_count() == 0)
	await _check_olfaction_fixtures(value, target, fixture_dir)
	value.world.active = false
	value.world.round_id += 1
	value.records = []
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.record.is_empty() and app._vision.shape.is_empty() and app.live_status == "WAITING")
	app.trace_dir = live
	await create_timer(0.35).timeout
	assert(app.live_status == "LIVE" and not app.readings.is_empty())


# A controlled nose sample: one strong human reading east, then a fresh empty sample
# that clears it, then a disabled receptor that is explicit rather than empty.
func _check_olfaction_fixtures(value: Dictionary, target: Dictionary, fixture_dir: String) -> void:
	app._sense_selector.current_tab = app.OLFACTION_TAB
	var nose: Dictionary = target.olfaction
	assert(nose.status == "Sampled")
	var zones := []
	for zone in 16: zones.append("None")
	zones[4] = "Strong"
	zones[5] = "Medium"
	var cleared := {"observation_id": 0, "class": "Human", "strength": "None", "freshness": "Unknown", "bearing_valid": false, "bearing": "North", "zones": zones.duplicate()}
	for index in 2: nose.readings[index] = cleared.duplicate(true)
	for index in 16: nose.readings[1].zones[index] = "None"
	nose.readings[0] = {"observation_id": 2147483657, "class": "Human", "strength": "Strong", "freshness": "Recent", "bearing_valid": true, "bearing": "East", "zones": zones}
	nose.reading_count = 1
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.scent_readings.size() == 1 and app.scent_readings[0].class == "Human" and app.scent_readings[0].direction == "E")
	assert(app._scent_table.get_root().get_child_count() == 1 and app.scent_readings[0].zones_with_scent == 2)
	await _capture("fixture-olfaction")
	nose.readings[0] = cleared.duplicate(true)
	for index in 16: nose.readings[0].zones[index] = "None"
	nose.reading_count = 0
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.scent_readings.is_empty() and app._scent_table.get_root().get_child_count() == 0 and "no scent" in app._scent_empty.text, "A fresh empty nose sample must clear current detection")
	nose.status = "Disabled"
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.olfaction_status() == "DISABLED" and "disabled" in app._scent_pose.text and app.live_status == "LIVE", "Disabled olfaction must be explicit and must not touch the eye's live clock")
	nose.status = "Sampled"
	app._sense_selector.current_tab = 0


func _check_staleness() -> void:
	var live: String = app.trace_dir
	var frozen := directory.path_join("frozen-" + slot)
	DirAccess.make_dir_recursive_absolute(frozen)
	DirAccess.copy_absolute(live.path_join("senses.json"), frozen.path_join("senses.json"))
	app.trace_dir = frozen
	await create_timer(1.0).timeout
	assert(app.live_status == "STALE" and app._vision.modulate.a < 1)
	assert(app.olfaction_status() == "STALE" and app._scent.modulate.a < 1)
	await _capture("stale")
	await create_timer(2.2).timeout
	assert(app.live_status == "DISCONNECTED")
	app.trace_dir = live
	await create_timer(0.35).timeout
	assert(app.live_status == "LIVE" and app.feed.error.is_empty())
