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


# Both views of every page at the current window size: "live" and "olfaction" keep
# their historical names (arena view); the local radars and the memory page follow.
func _capture_every_view(suffix: String) -> void:
	app._sense_selector.current_tab = 0
	app._vision_page.select_view(app._vision_page.ARENA_VIEW)
	await _capture("live" + suffix)
	app._vision_page.select_view(app._vision_page.LOCAL_VIEW)
	await _capture("vision-local" + suffix)
	app._vision_page.select_view(app._vision_page.ARENA_VIEW)
	app._sense_selector.current_tab = app.OLFACTION_TAB
	app._scent_page.select_view(app._scent_page.ARENA_VIEW)
	await _capture("olfaction" + suffix)
	app._scent_page.select_view(app._scent_page.LOCAL_VIEW)
	await _capture("olfaction-local" + suffix)
	app._scent_page.select_view(app._scent_page.ARENA_VIEW)
	app._sense_selector.current_tab = app.MEMORY_TAB
	await _capture("memory" + suffix)
	app._sense_selector.current_tab = 0


# The three pages share one arena frame; the Olfaction page adds the host field on it.
func _check_arena_views() -> void:
	for tab in [0, app.OLFACTION_TAB, app.MEMORY_TAB]:
		app._sense_selector.current_tab = tab
		await process_frame
	var reference: Control = app._vision_page.overview
	assert(reference.has_arena() and reference.map_id == int(app.record.map_id), "The overview must frame the bound arena")
	for page in [app._vision_page, app._scent_page, app._memory]:
		var overview: Control = page.overview
		assert(overview.cells == reference.cells and overview.get_global_rect().is_equal_approx(reference.get_global_rect()), "Pages disagree on the arena frame: " + str(overview.get_global_rect()) + " vs " + str(reference.get_global_rect()))
		var probe := Vector2(100, 100)
		assert((overview.get_global_transform() * overview.world_to_view(probe)).is_equal_approx(reference.get_global_transform() * reference.world_to_view(probe)), "Pages place the same world point differently")
		assert(overview.legend_fits(), "An arena legend overflows its frame")
	app._sense_selector.current_tab = app.OLFACTION_TAB
	await create_timer(0.3).timeout
	var page = app._scent_page
	assert(page.field_status == "LIVE", "Host field must be live: %s %s" % [page.field_status, page.field_reason])
	assert(page.painter.painted_cells > 0 and page.layer.texture != null, "Standing bodies emit scent: the published field must hold cells")
	var nose: Dictionary = app.record.olfaction
	var own := Vector2(nose.position[0], nose.position[1])
	var overview: Control = page.overview
	if DisplayServer.get_name() == "headless": page._pointer_pressed(own)
	else: _click(overview.get_global_transform() * overview.world_to_view(own))
	assert(page.selected_cell == overview.cell_of(own) and "Pinned cell" in page.details.text, "Clicking the nose cell must pin it: " + page.details.text)
	var own_class: String = app.record.own_emitter.class
	var report: Array = page.cell_report(page.selected_cell)
	assert(report.any(func(entry): return entry.class == own_class and int(entry.level) > 0), "The emitter's own cell must publish its class: " + str(report))
	assert("level" in page.readout.text and "newest deposit" in page.readout.text, "Readout must show level and age: " + page.readout.text)
	await _capture("olfaction-pinned")
	page._pointer_pressed(own)
	assert(page.selected_cell == Vector2i(-1, -1))
	var original_size: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	await process_frame
	await _capture_every_view("-minimum")
	root.size = original_size
	await process_frame
	await _capture_every_view("")


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
		await _capture_every_view("")
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
	assert(app._vision_page.table.get_root().get_child_count() == app.readings.size())
	assert(app.readings.size() <= 6 and app._sense_selector.tab_count == 6)
	assert(app._vision_page.table.get_global_rect().end.x <= app.size.x, "Readings table extends beyond the viewport")
	for index in [1, 3, 4]:
		app._sense_selector.current_tab = index
		assert(app._notice.visible and not app._vision_page.visible and not app._scent_page.visible and "Not implemented" in app._notice.text)
	await _capture("unsupported")
	app._sense_selector.current_tab = 0
	var before: String = app._sample_key
	await create_timer(0.35).timeout
	assert(app._sample_key != before)
	var item: TreeItem = app._vision_page.table.get_root().get_first_child()
	if item != null:
		item.select(0)
		app._vision_page.select_reading()
		assert(app._vision.selected_number > 0 and not app._vision_page.selected_reference.is_empty())
		await create_timer(0.25).timeout
		assert(app._vision.selected_number > 0, "Selection disappeared on the next sample")
	await _capture("live")
	var original_size: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	assert(app._vision_page.table.get_global_rect().end.x <= app.size.x, "Minimum window clips the table")
	await _capture("minimum")
	root.size = original_size
	app.set_filter("Focused", false)
	assert(not app._vision.show_focus and app._vision.show_periphery)
	app.set_filter("Focused", true)
	app.set_filter("Peripheral", false)
	assert(app._vision.show_focus and not app._vision.show_periphery)
	app.set_filter("Peripheral", true)
	await _check_arena_views()
	app._sense_selector.current_tab = app.MEMORY_TAB
	assert(app._memory.visible and not app._vision_page.visible and not app._notice.visible)
	assert(app._memory.memory.is_empty(), "Stationary Observe fixture invented exploration memory")
	app._sense_selector.current_tab = 0


# The Olfaction page shows the delivered nose sample only: anonymous class rows,
# zones at the sensor's resolution, and its own live/stale clock.
func _check_olfaction_page() -> void:
	app._sense_selector.current_tab = app.OLFACTION_TAB
	assert(app._scent_page.visible and not app._vision_page.visible and not app._notice.visible)
	_check_controls(app._scent_page)
	assert(app.olfaction_status() == "LIVE" and app.record.olfaction.status == "Sampled")
	assert(app._scent_page.table.get_root().get_child_count() == app.scent_readings.size())
	assert(app.scent_readings.size() <= 2)
	for row in app.scent_readings:
		assert(row.class in ["Human", "Orc"] and row.strength != "None")
		for key in ["position", "subject", "entity_id", "kind"]: assert(not row.has(key), "Scent row leaked " + key)
	assert(app._scent.sample.sample_id == app.record.olfaction.sample_id, "The spatial view shows another nose sample")
	assert("reach" in app._scent_page.summary.text and "Nose sample #" in app._scent_page.timing.text)
	var counts: Dictionary = app._scent.coverage_counts()
	assert(counts.recorded and counts.sampled + counts.partial + counts.unsampled == 16, "The live nose sample must carry its coverage")
	assert("Measured" in app._scent_page.note.text or "No ground" in app._scent_page.note.text, "The readings column must state the measured coverage")
	assert(app._scent.legend_fits(), "The Olfaction legend overflows the view")
	var before: String = app._scent_key
	await create_timer(0.45).timeout
	assert(app._scent_key != before, "The nose sample did not advance")
	var item: TreeItem = app._scent_page.table.get_root().get_first_child()
	if item != null:
		item.select(0)
		app._scent_page.select_reading()
		assert(app._scent.selected_number > 0 and "scent" in app._scent_page.details.text)
	await _capture("olfaction")
	app._scent_page.select_view(app._scent_page.LOCAL_VIEW)
	assert(app._scent.visible and not app._scent_page.overview.visible, "The local nose view must stay available")
	await _capture("olfaction-local")
	var original_size: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	await process_frame
	assert(app._scent_page.table.get_global_rect().end.x <= app.size.x, "Minimum window clips the scent table")
	assert(app._scent.legend_fits(), "The Olfaction legend overflows the minimum window")
	await _capture("olfaction-local-minimum")
	app._scent_page.select_view(app._scent_page.ARENA_VIEW)
	await process_frame
	assert(app._scent_page.overview.legend_fits(), "The arena legend overflows the minimum window")
	await _capture("olfaction-minimum")
	root.size = original_size
	app.set_scent_filter("Human", false)
	assert(not app._scent.show_classes.Human and app._scent.show_classes.Orc)
	app.set_scent_filter("Human", true)
	app._sense_selector.current_tab = 0


func _check_exploration_memory() -> void:
	app._sense_selector.current_tab = app.MEMORY_TAB
	assert(app._memory.visible and not app._vision_page.visible and not app._notice.visible)
	_check_controls(app)
	assert(app._memory.live_status == "LIVE" and app._memory.memory.owner_id == app.owner_id)
	assert(app._memory.memory.visits.size() > 0 and app._memory.table.get_root().get_child_count() == app._memory.memory.visits.size())
	var first: Dictionary = app._memory.memory.visits[0]
	if DisplayServer.get_name() == "headless": app._memory._select_region(first.key)
	else:
		await RenderingServer.frame_post_draw
		var overview: Control = app._memory.overview
		var center: Vector2 = (Vector2(first.region[0], first.region[1]) + Vector2.ONE * 0.5) * app._memory.memory.region_size
		_click(overview.get_global_transform() * overview.world_to_view(center))
	assert(app._memory.selected_key == first.key and app._memory._map.selected_key == first.key)
	await create_timer(0.25).timeout
	assert(app._memory.selected_key == first.key, "Visit selection was lost on refresh")
	if DisplayServer.get_name() != "headless" and app._memory.memory.visits.size() > 1:
		var table: Tree = app._memory.table
		var item := table.get_root().get_child(1)
		_click(table.get_global_transform() * table.get_item_area_rect(item).get_center())
		assert(app._memory.selected_key == item.get_metadata(0).key, "Row click did not select its remembered region")
	await _capture("exploration-memory")
	var original: Vector2i = root.size
	root.size = root.min_size
	await process_frame
	assert(app._memory.table.get_global_rect().end.x <= app.size.x, "Minimum window clipped the memory table")
	assert(app._memory.overview.legend_fits(), "The memory legend overflows the minimum window")
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
	assert(app._vision.selected_number == 0 and not "Position" in app._vision_page.details.text)
	await _capture("fixture-peripheral")
	for heartbeat in 8:
		await create_timer(0.15).timeout
		_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.live_status == "STALE" and not app.feed.is_stale(), "Heartbeat disguised a stalled sensor as live")
	sample.sample_id += 1
	sample.cue_count = 0
	sample.cues[0] = {"observation_id": 0, "sector": 0, "band": "Near"}
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.readings.is_empty() and app._vision_page.table.get_root().get_child_count() == 0)
	await _check_olfaction_fixtures(value, target, fixture_dir)
	value.world.active = false
	value.world.round_id += 1
	value.records = []
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.record.is_empty() and app._vision.shape.is_empty() and app.live_status == "WAITING")
	assert(app._scent_page.field_status != "LIVE" and app._scent_page.layer.texture == null, "An inactive world must not keep drawing the last round's field")
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
	assert(app._scent_page.table.get_root().get_child_count() == 1 and app.scent_readings[0].zones_with_scent == 2)
	await _capture("fixture-olfaction")
	nose.readings[0] = cleared.duplicate(true)
	for index in 16: nose.readings[0].zones[index] = "None"
	nose.reading_count = 0
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.scent_readings.is_empty() and app._scent_page.table.get_root().get_child_count() == 0 and "no scent" in app._scent_page.note.text, "A fresh empty nose sample must clear current detection")
	await _check_coverage_fixtures(value, nose, fixture_dir)
	var live_coverage: Array = nose.coverage.duplicate()
	for index in 16: nose.coverage[index] = "Unsampled"
	nose.status = "Disabled"
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.olfaction_status() == "DISABLED" and "disabled" in app._scent_page.summary.text and app.live_status == "LIVE", "Disabled olfaction must be explicit and must not touch the eye's live clock")
	nose.status = "Sampled"
	nose.coverage = live_coverage
	app._sense_selector.current_tab = 0


# Coverage fixtures: a nose that measured nothing must show no measured ground, and a
# partly measured reach must show exactly the delivered zone words.
func _check_coverage_fixtures(value: Dictionary, nose: Dictionary, fixture_dir: String) -> void:
	var original: Array = nose.coverage.duplicate()
	for index in 16: nose.coverage[index] = "Unsampled"
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	var counts: Dictionary = app._scent.coverage_counts()
	assert(counts.recorded and counts.unsampled == 16 and "No ground was measured" in app._scent_page.note.text, "Zero coverage must read as unknown, not as sampled absence")
	await _capture("fixture-olfaction-no-coverage")
	for index in 16: nose.coverage[index] = "Sampled" if index >= 6 else ("Partial" if index % 2 == 0 else "Unsampled")
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	counts = app._scent.coverage_counts()
	assert(counts.sampled == 10 and counts.partial == 3 and counts.unsampled == 3, str(counts))
	for index in 16: assert(app._scent.zone_coverage(index) == nose.coverage[index])
	assert("Measured 10 of 16 zones fully, 3 partly; 3 unknown." in app._scent_page.note.text, app._scent_page.note.text)
	await _capture("fixture-olfaction-partial-coverage")
	nose.coverage = original
	# Scent claimed in a zone the nose never measured is rejected as a whole sample.
	var broken: Dictionary = value.duplicate(true)
	var broken_nose: Dictionary = broken.records[app.owner_id - 1].olfaction
	for index in 16: broken_nose.coverage[index] = "Unsampled"
	broken_nose.readings[0] = {"observation_id": 2147483665, "class": "Orc", "strength": "Weak", "freshness": "Unknown", "bearing_valid": false, "bearing": "North", "zones": broken_nose.readings[0].zones.duplicate()}
	broken_nose.readings[0].zones[2] = "Weak"
	broken_nose.reading_count = 1
	broken_nose.sample_id += 5
	broken.published_us = int(app.feed.published_us) + 1
	var file := FileAccess.open(fixture_dir.path_join("senses.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(broken))
	file.close()
	app._poll()
	assert(app.feed.error == "Scent in an unmeasured zone." and app._scent.sample.sample_id != broken_nose.sample_id, "A reading in unmeasured ground must be refused: " + app.feed.error)
	nose.sample_id += 1
	_publish_fixture(value, fixture_dir.path_join("senses.json"))
	assert(app.feed.error.is_empty())


func _check_staleness() -> void:
	var live: String = app.trace_dir
	var frozen := directory.path_join("frozen-" + slot)
	DirAccess.make_dir_recursive_absolute(frozen)
	DirAccess.copy_absolute(live.path_join("senses.json"), frozen.path_join("senses.json"))
	app.trace_dir = frozen
	await create_timer(1.0).timeout
	assert(app.live_status == "STALE" and app._vision.modulate.a < 1)
	assert(app.olfaction_status() == "STALE" and app._scent.modulate.a < 1)
	assert(app._scent_page.field_status in ["STALE", "DISCONNECTED"] and app._scent_page.layer.field_alpha < 1, "A frozen directory without a field publication must show the field as stale: " + app._scent_page.field_status)
	await _capture("stale")
	app._sense_selector.current_tab = app.OLFACTION_TAB
	await _capture("olfaction-arena-stale")
	app._sense_selector.current_tab = 0
	await create_timer(2.2).timeout
	assert(app.live_status == "DISCONNECTED")
	app.trace_dir = live
	await create_timer(0.35).timeout
	assert(app.live_status == "LIVE" and app.feed.error.is_empty())
	assert(app._scent_page.field_status == "LIVE", "The host field must recover with the live directory: " + app._scent_page.field_status)
