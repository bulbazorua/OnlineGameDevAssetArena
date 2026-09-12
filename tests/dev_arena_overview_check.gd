extends SceneTree

# Shared dev arena overview, radar and pages without a display: transforms, the
# same footprint on every page, both radar consumers, the shared field image
# against independently computed colours, host-field lifecycle and privacy.
const Overview = preload("res://dev/ui/arena_overview.gd")
const Radar = preload("res://dev/ui/sensor_radar.gd")
const Style = preload("res://dev/ui/dev_ui_style.gd")
const VisionView = preload("res://dev/senses/vision_sensor_view.gd")
const ScentView = preload("res://dev/senses/olfaction_sensor_view.gd")
const VisionPage = preload("res://dev/senses/vision_page.gd")
const OlfactionPage = preload("res://dev/senses/olfaction_page.gd")
const MemoryPanel = preload("res://dev/senses/exploration_memory_panel.gd")
const FieldImage = preload("res://dev/scent_field_image.gd")
const ScentFeed = preload("res://dev/scent_feed.gd")
const VisionReadings = preload("res://dev/senses/vision_readings.gd")
const ScentReadings = preload("res://dev/senses/olfaction_readings.gd")
const Memory = preload("res://dev/senses/exploration_memory.gd")
const Reader = preload("res://dev/ai/trace_reader.gd")
const GameContent = preload("res://content/game_content.gd")
const FIXTURE_DIR := "user://dev-arena-overview-check"
var Fixtures: GDScript
const PAGE_SIZES := [Vector2(1160, 600), Vector2(960, 500)]
var content := GameContent.new()
var published := 100
var checks := 0
var failures := 0


func _initialize() -> void:
	Fixtures = load(get_script().resource_path.get_base_dir().path_join("dev_arena_fixtures.gd"))
	_run.call_deferred()


func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Dev arena overview check did not finish."); quit(1))
	assert(content.load_catalog().is_empty(), "content catalog")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	_check_overview_transform()
	await _check_same_footprint()
	await _check_radar_consumers()
	_check_field_image()
	await _check_field_lifecycle()
	await _check_memory_selection()
	if failures > 0:
		push_error("FAIL: %d of %d checks failed." % [failures, checks])
		quit(1)
		return
	print("PASS: %d assertions on the shared arena overview, both radar consumers, the field image, host-field lifecycle, privacy, view modes and linked memory selection." % checks)
	quit(0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error("Check failed: " + message)


# Bypasses the page's read throttle so each step of the story reads the file now.
func _poll(page: OlfactionPage, directory: String, world: Dictionary) -> void:
	page._next_read_ms = 0
	page.update_field(directory, "fixture", "fp", world)


func _check_overview_transform() -> void:
	var overview := Overview.new()
	overview.size = Vector2(600, 400)
	_expect(not overview.has_arena() and overview.cell_of(Vector2(5, 5)) == Overview.NO_CELL, "no arena yet")
	var rectangular: ArenaCatalog.ArenaDefinition = Fixtures.arena(7, 30, 16, 32, "Scent Trail (QA)")
	_expect(overview.set_arena(rectangular) and not overview.set_arena(rectangular), "arena change is reported once")
	var rect := overview.arena_rect()
	var plot := overview.plot_rect()
	_expect(plot.encloses(rect.grow(-0.01)), "arena fits inside the plot")
	_expect(is_equal_approx(rect.size.x / rect.size.y, 960.0 / 512.0), "aspect ratio kept for a rectangular arena")
	_expect(overview.world_to_view(Vector2.ZERO).is_equal_approx(rect.position), "world origin lands on the outline corner")
	_expect(overview.world_to_view(Vector2(960, 512)).is_equal_approx(rect.end), "world extent lands on the far corner")
	for point in [Vector2.ZERO, Vector2(960, 512), Vector2(123.4, 456.7), Vector2(-50, 20), Vector2(3000, -7)]:
		_expect(overview.view_to_world(overview.world_to_view(point)).is_equal_approx(point), "round trip " + str(point))
	_expect(overview.contains_world(Vector2.ZERO) and overview.contains_world(Vector2(959.9, 511.9)), "inside corners")
	_expect(not overview.contains_world(Vector2(960, 512)) and not overview.contains_world(Vector2(-1, 0)), "outside edges")
	_expect(overview.cell_of(Vector2(959.9, 511.9)) == Vector2i(29, 15) and overview.cell_of(Vector2(960, 512)) == Overview.NO_CELL, "edge cell")
	_expect(overview.cell_rect(Vector2i(29, 15)).end.is_equal_approx(rect.end), "last cell ends on the outline")
	_expect(overview.cell_rect(Vector2i(0, 0)).position.is_equal_approx(rect.position), "first cell starts on the outline")
	var before := overview.world_to_view(Vector2(480, 256))
	overview.size = Vector2(900, 300)
	_expect(overview.world_to_view(Vector2(480, 256)).is_equal_approx(overview.arena_rect().get_center()), "centre stays centred after a resize")
	_expect(not overview.world_to_view(Vector2(480, 256)).is_equal_approx(before), "resize changes the fit")
	_expect(is_equal_approx(overview.arena_rect().size.x / overview.arena_rect().size.y, 960.0 / 512.0), "aspect kept after a resize")
	_expect(overview.clip_contents, "layers are clipped to the frame")
	overview.size = Vector2.ZERO
	_expect(is_finite(overview.world_to_view(Vector2(10, 10)).x) and overview.scale_factor() > 0, "a hidden frame keeps a finite transform")
	_expect(overview.grid_step_cells() == 1, "grid step for 30x16")
	overview.set_arena(Fixtures.arena(1, 60, 28, 32, "Meadow"))
	_expect(overview.grid_step_cells() == 2, "grid step for 60x28")
	overview.set_arena(Fixtures.arena(9, 128, 128, 16, "Huge"))
	_expect(overview.grid_step_cells() == 4, "grid step for 128x128")
	_expect(overview.set_arena(null) and not overview.has_arena(), "arena can be cleared")
	overview.free()


# The three pages must put the same world point at the same place at the same window size.
func _check_same_footprint() -> void:
	var arena: ArenaCatalog.ArenaDefinition = Fixtures.arena(7, 30, 16, 32, "Scent Trail (QA)")
	var pages := _pages(PAGE_SIZES[0])
	for size: Vector2 in PAGE_SIZES:
		for page in pages:
			page.get_parent().size = size
			page.set_arena(arena)
		await process_frame
		await process_frame
		for page in pages: _expect(page.size.is_equal_approx(size), "page fills its host at " + str(size) + ": " + str(page.size))
		var reference: Overview = pages[0].overview
		var reference_rect := reference.get_global_rect()
		var reference_point: Vector2 = reference.get_global_transform() * reference.world_to_view(Vector2(300, 200))
		_expect(reference_rect.size.x >= Style.MIN_SUPPORTED_WIDTH and reference_rect.size.y >= 250, "the canvas is usable at " + str(size))
		for page in pages:
			var overview: Overview = page.overview
			_expect(overview.get_global_rect().is_equal_approx(reference_rect), "same canvas footprint on %s at %s" % [page.get_script().resource_path.get_file(), size])
			var point: Vector2 = overview.get_global_transform() * overview.world_to_view(Vector2(300, 200))
			_expect(point.is_equal_approx(reference_point), "same world placement on %s at %s" % [page.get_script().resource_path.get_file(), size])
			_expect(overview.legend_fits(), "legend fits on " + page.get_script().resource_path.get_file())
		for page in pages:
			page.get_parent().size = Vector2.ZERO
			page.hide()
			await process_frame
			_expect(page.overview.legend_fits(), "legend fits while the page is hidden and unlaid")
			page.show()
	_expect(pages[2].view_buttons.size() == 1 and pages[0].view_buttons.size() == 2 and pages[1].view_buttons.size() == 2, "memory has one view, the sensors two")
	for page in pages:
		_expect(page.view_mode == page.ARENA_VIEW and page.overview.visible, "arena overview is the default view")
	pages[1].select_view(pages[1].LOCAL_VIEW)
	_expect(pages[1].view.visible and not pages[1].overview.visible and pages[1].view_buttons[pages[1].LOCAL_VIEW].button_pressed, "local sensor view can be selected")
	pages[1].select_view(pages[1].ARENA_VIEW)
	_expect(pages[1].overview.visible and not pages[1].view.visible, "arena view restored")
	for page in pages: page.queue_free()
	await process_frame


# Pages live inside a fixed-size host, as they do inside the window's layout; a bare
# top-level page would be stretched to the unlaid minimum of its wrapping labels.
func _host(page: Control, size: Vector2) -> Control:
	var host := Control.new()
	host.size = size
	root.add_child(host)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(page)
	return host


func _pages(size: Vector2) -> Array:
	var vision := VisionPage.new()
	_host(vision, size)
	vision.configure(content)
	var olfaction := OlfactionPage.new()
	_host(olfaction, size)
	olfaction.configure()
	var memory := MemoryPanel.new()
	_host(memory, size)
	memory.configure(1)
	return [vision, olfaction, memory]


# Both local views are built on the one radar frame, with their own direction rules.
func _check_radar_consumers() -> void:
	var eye := VisionView.new()
	var nose := ScentView.new()
	_expect(eye.radar.get_script() == Radar and nose.radar.get_script() == Radar, "both views instantiate sensor_radar.gd")
	_expect(eye.radar.get_parent() == eye and nose.radar.get_parent() == nose, "the radar is the frame inside each view")
	for view in [eye, nose]:
		root.add_child(view)
		view.size = Vector2(700, 500)
	await process_frame
	var record: Dictionary = Fixtures.vision_record("East")
	var rows: Array[Dictionary] = VisionReadings.current(record.vision)
	eye.set_sample(record, rows)
	nose.set_sample(record, ScentReadings.current(record.olfaction), 32.0)
	_expect(rows.size() == 2 and not rows[1].has("position"), "a peripheral cue carries no position")
	_expect(is_equal_approx(eye.cue_angle(rows[1]), PI / 2.0), "cue sector 2 while facing East points South")
	record = Fixtures.vision_record("North")
	eye.set_sample(record, VisionReadings.current(record.vision))
	_expect(is_equal_approx(eye.cue_angle(eye.rows[1]), 0.0), "the same cue sector points East when facing North")
	_expect(is_equal_approx(nose.sector_angle(4), 0.0) and is_equal_approx(nose.sector_angle(8), PI / 2.0), "nose zones stay in world directions")
	_expect(is_equal_approx(eye.radar.range_units, 160.0) and is_equal_approx(nose.radar.range_units, 256.0), "each radar scales to its own reach")
	for view in [eye, nose]:
		var geometry: Dictionary = view.plot_geometry()
		var legend_height: float = Style.legend_height(view.radar.wrapped_legend().size())
		_expect(is_equal_approx(geometry.legend_height, legend_height), "legend strip height follows the wrapped lines")
		_expect(is_equal_approx(geometry.radius, minf(700.0, 500.0 - legend_height - 24.0) * 0.42), "plot radius from the shared rule")
		_expect(geometry.center.is_equal_approx(Vector2(350.0, 24.0 + (500.0 - legend_height - 24.0) / 2.0)), "plot centre from the shared rule")
		_expect(view.radar.polar_to_view(0.0, view.radar.range_units).is_equal_approx(geometry.center + Vector2(geometry.radius, 0)), "the outer ring is the sensor's reach")
		_expect(view.legend_fits(), "legend fits at 700x500")
		view.size = Vector2.ZERO
		await process_frame
		_expect(view.legend_fits(), "legend fits for a hidden view at the supported minimum width")
		view.size = Vector2(400, 350)
		await process_frame
		_expect(view.legend_fits(), "legend fits at the minimum page size")
	_expect(nose.plot_geometry().has("blind") and nose.plot_geometry().blind > 0, "the nose keeps its blind disc geometry")
	var eye_rings: Array[float] = [1.0, 0.5]
	_expect(nose.radar.guide_rings.has(1.0) and eye.radar.guide_rings == eye_rings, "guide rings: shared outer ring, nose adds its blind edge")
	eye.queue_free()
	nose.queue_free()
	await process_frame


func _publish(value: Dictionary) -> void:
	published += 1
	value.published_us = published
	Fixtures.write_json(FIXTURE_DIR + "/scent.json", value)


func _check_field_image() -> void:
	var feed := ScentFeed.new()
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages()))
	feed.read_snapshot(FIXTURE_DIR + "/scent.json", "fixture", "fp")
	_expect(feed.error.is_empty(), "fixture field accepted: " + feed.error)
	var painter := FieldImage.new()
	_expect(painter.repaint(feed, {"Human": true, "Orc": true}) and painter.rebuilds == 1, "first repaint builds the image")
	var image: Image = painter.image
	_expect(image.get_size() == Vector2i(30, 16), "one pixel per cell")
	_expect(Fixtures.close(image.get_pixel(1, 1), Fixtures.expected_cell(255, 0, 0.06, 0.42)), "saturated human cell")
	_expect(Fixtures.close(image.get_pixel(2, 3), Fixtures.expected_cell(128, 64, 0.06, 0.42)), "overlapping human and orc cell")
	_expect(Fixtures.close(image.get_pixel(4, 2), Fixtures.expected_cell(0, 200, 0.06, 0.42)), "orc cell")
	_expect(Fixtures.close(image.get_pixel(5, 5), Fixtures.expected_cell(1, 0, 0.06, 0.42)), "a faint cell stays faint on the fixed scale")
	_expect(image.get_pixel(0, 0).a == 0 and image.get_pixel(29, 15).a == 0, "empty cells are transparent")
	for step in 11: _expect(Fixtures.close(image.get_pixel(10 + step, 8), Fixtures.expected_cell(255 - step * 20, 0, 0.06, 0.42)), "wake cell %d" % step)
	_expect(painter.painted_cells == 15, "painted cells counted independently: 3 human + 11 wake + 1 orc-only = 15")
	_expect(not painter.repaint(feed, {"Human": true, "Orc": true}) and painter.rebuilds == 1, "same field and filters: no rebuild")
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages()))
	feed.read_snapshot(FIXTURE_DIR + "/scent.json", "fixture", "fp")
	_expect(not painter.repaint(feed, {"Human": true, "Orc": true}) and painter.rebuilds == 1, "a republished identical tick does not rebuild")
	_expect(painter.repaint(feed, {"Human": false, "Orc": true}) and painter.painted_cells == 2, "hiding human leaves the two orc cells")
	image = painter.image
	_expect(image.get_pixel(1, 1).a == 0 and Fixtures.close(image.get_pixel(2, 3), Fixtures.expected_cell(0, 64, 0.06, 0.42)), "filtered cells drop out or keep only the shown class")
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), 606))
	feed.read_snapshot(FIXTURE_DIR + "/scent.json", "fixture", "fp")
	_expect(painter.repaint(feed, {"Human": false, "Orc": true}) and painter.rebuilds == 3, "a new field tick rebuilds")
	_publish(Fixtures.field_fixture({}, {}, 612))
	feed.read_snapshot(FIXTURE_DIR + "/scent.json", "fixture", "fp")
	_expect(painter.repaint(feed, {"Human": true, "Orc": true}) and painter.painted_cells == 0, "an empty field paints nothing")
	painter.floor_alpha = 0.18
	painter.max_alpha = 0.82
	_publish(Fixtures.field_fixture({"Human": {Vector2i(0, 0): 50}}, {}, 618))
	feed.read_snapshot(FIXTURE_DIR + "/scent.json", "fixture", "fp")
	painter.repaint(feed, {"Human": true, "Orc": true})
	_expect(Fixtures.close(painter.image.get_pixel(0, 0), Fixtures.expected_cell(50, 0, 0.18, 0.82)), "the minimap ramp is fixed too, not scaled to the strongest cell")


func _check_field_lifecycle() -> void:
	var pages := _pages(Vector2(1160, 600))
	var vision: VisionPage = pages[0]
	var page: OlfactionPage = pages[1]
	var memory: MemoryPanel = pages[2]
	var arena: ArenaCatalog.ArenaDefinition = Fixtures.arena(7, 30, 16, 32, "Scent Trail (QA)")
	var world := {"active": true, "round_id": 5, "map_id": 7, "entities": [3, 4]}
	for entry in pages: entry.set_arena(arena)
	await process_frame
	await process_frame
	var record: Dictionary = Fixtures.vision_record("East")
	vision.set_sample(record, VisionReadings.current(record.vision))
	page.set_sample(record, ScentReadings.current(record.olfaction), 32.0)
	memory._set_memory(Memory.project(Fixtures.memory_record()))
	var rows_before := page.readings.duplicate(true)
	var vision_rows := vision.readings.duplicate(true)
	var visits_before: Array = memory.memory.visits.duplicate(true)
	var preferences := _preference_files()
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages()))
	_poll(page, FIXTURE_DIR, world)
	_expect(page.field_status == "LIVE" and page.layer.texture != null and page.painter.painted_cells == 15, "matching field is live and drawn: %s %s cells=%d" % [page.field_status, page.field_reason, page.painter.painted_cells])
	_expect(page.overview.badge.begins_with("LIVE · field tick 600") and page.overview.badge_live, "badge names the field tick: " + page.overview.badge)
	var report := page.cell_report(Vector2i(1, 1))
	_expect(report.size() == 2 and report[0].class == "Human" and report[0].level == 255 and report[0].age == 3 and report[1].level == 0, "cell report per class")
	for entry in report: _expect(entry.keys() == ["class", "level", "age", "shown"], "a cell report holds only class, level, age and filter state")
	_expect("Human level 255/255, newest deposit 3 s ago" in page.cell_line(Vector2i(1, 1)) and "Orc no published level" in page.cell_line(Vector2i(1, 1)), "readout words: " + page.cell_line(Vector2i(1, 1)))
	_expect("≥ 255 s ago (capped)" in page.cell_details(Vector2i(2, 3)) and "capped at 255" in page.cell_details(Vector2i(2, 3)), "a capped age is never shown as exact")
	_expect("Zero = nothing published" in page.cell_details(Vector2i(0, 0)), "a zero cell is explained as unpublished")
	var inside := Vector2(1.5 * 32, 1.5 * 32)
	page._pointer_moved(inside)
	_expect(page.hover_cell == Vector2i(1, 1) and page.readout.text.begins_with("Hover cell (1, 1)"), "hover readout: " + page.readout.text)
	page._pointer_pressed(inside)
	_expect(page.selected_cell == Vector2i(1, 1) and page.layer.selected_cell == Vector2i(1, 1) and "Pinned cell (1, 1)" in page.details.text, "pinned cell details")
	page._pointer_left()
	_expect(page.hover_cell == Overview.NO_CELL and page.readout.text.begins_with("Pinned cell (1, 1)"), "the pinned cell stays in the readout: " + page.readout.text)
	page._pointer_pressed(inside)
	_expect(page.selected_cell == Overview.NO_CELL, "clicking the pinned cell unpins it")
	page._pointer_pressed(Vector2(2.5 * 32, 3.5 * 32))
	page.set_class_filter("Human", false)
	_expect(page.painter.painted_cells == 2 and not page.view.show_classes.Human and "(filtered out of the picture)" in page.details.text, "the minimap filter hides a class without touching the numbers")
	_expect(_preference_files() == preferences, "minimap filters save no window preference")
	page.set_class_filter("Human", true)
	_expect(page.readings == rows_before and vision.readings == vision_rows and memory.memory.visits == visits_before, "the host field adds no private readings or visits")
	_expect(vision.layer.rows == vision.readings and not vision.layer.rows[1].has("position") and vision.layer.shape.center == Vector2(100, 100), "the vision layer anchors to the sampled pose and keeps cues approximate")
	var debug := JSON.stringify(page.field_debug())
	_expect(not "entities" in debug and not "position" in debug, "field diagnostics carry no identities or positions")
	page.refresh_field(page.feed.received_ms + 800)
	_expect(page.field_status == "STALE" and page.layer.texture != null and is_equal_approx(page.layer.field_alpha, 0.4) and page.overview.badge.begins_with("STALE"), "a stalled publication keeps the last field, dimmed and labelled: %s %s %.2f" % [page.field_status, page.overview.badge, page.layer.field_alpha])
	page.refresh_field(page.feed.received_ms + 3100)
	_expect(page.field_status == "DISCONNECTED", "three seconds without a publication: " + page.field_status)
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages()))
	_poll(page, FIXTURE_DIR, world)
	_expect(page.field_status == "LIVE", "a fresh publication recovers: " + page.field_status)
	_poll(page, "user://nowhere-at-all", world)
	_expect(page.field_status == "STALE" and page.field_debug().error == "Waiting for the host scent field" and page.layer.texture != null, "a missing file is explicit and keeps the last field: %s %s" % [page.field_status, page.field_debug().error])
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages()))
	_poll(page, FIXTURE_DIR, world)
	_expect(page.field_status == "LIVE", "the field recovers after the file returns")
	var broken: Dictionary = Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), published + 1, 630)
	broken.field.width = 0
	_publish(broken)
	_poll(page, FIXTURE_DIR, world)
	_expect(page.field_status == "STALE" and page.field_debug().error == "Invalid scent field size" and page.field_debug().field_tick == 600, "an invalid publication is refused and named, the last good field kept: %s %s" % [page.field_status, page.field_debug().error])
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), 636, 30, 16, 64.0))
	_poll(page, FIXTURE_DIR, world)
	_expect(page.field_status == "WAITING" and "does not match arena" in page.field_reason and page.layer.texture == null, "a tile size mismatch is never drawn over the arena: %s %s" % [page.field_status, page.field_reason])
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), 642))
	_poll(page, FIXTURE_DIR, world)
	page._pointer_pressed(inside)
	_expect(page.field_status == "LIVE" and page.selected_cell == Vector2i(1, 1), "back to live with a pinned cell: " + page.field_status)
	var next_round := world.duplicate(true)
	next_round.round_id = 6
	_poll(page, FIXTURE_DIR, next_round)
	_expect(page.field_status == "WAITING" and "round 5" in page.field_reason and page.layer.texture == null and page.selected_cell == Overview.NO_CELL, "a new round drops the old field and its selection: %s %s" % [page.field_status, page.field_reason])
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), 700, 30, 16, 32.0, 6))
	_poll(page, FIXTURE_DIR, next_round)
	_expect(page.field_status == "LIVE" and page.painter.painted_cells == 15, "the new round's field appears: " + page.field_status)
	page.set_arena(Fixtures.arena(1, 60, 28, 32, "Meadow"))
	_expect(not page._matches and page.layer.texture == null and "does not match arena" in page.field_reason, "a map change with old dimensions is not drawn: " + page.field_reason)
	page.set_arena(arena)
	_expect(page._matches and page.layer.texture != null, "the matching arena draws again")
	var lobby := next_round.duplicate(true)
	lobby.active = false
	_poll(page, FIXTURE_DIR, lobby)
	_expect(page.field_status == "WAITING" and page.field_reason == "no active round" and page.layer.texture == null, "an inactive world shows no field: " + page.field_reason)
	page.hide()
	_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), 706, 30, 16, 32.0, 6))
	_poll(page, FIXTURE_DIR, next_round)
	_expect(page.field_status == "LIVE" and page.painter.rebuilds > 0, "a hidden page still tracks the field")
	var rebuilds: int = page.painter.rebuilds
	for repeat in 5:
		_publish(Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages(), 706, 30, 16, 32.0, 6))
		_poll(page, FIXTURE_DIR, next_round)
	_expect(page.painter.rebuilds == rebuilds and page.polls >= 6, "republished unchanged ticks are read but never rebuild the image")
	page.show()
	for entry in pages: entry.get_parent().queue_free()
	await process_frame


func _preference_files() -> PackedStringArray:
	var directory := ProjectSettings.globalize_path("user://dev")
	if not DirAccess.dir_exists_absolute(directory): return PackedStringArray()
	return DirAccess.get_files_at(directory)


# Region hit testing goes through the shared transform, so selection survives a resize.
func _check_memory_selection() -> void:
	var panel := MemoryPanel.new()
	var host := _host(panel, Vector2(1160, 600))
	panel.configure(1)
	panel.set_arena(Fixtures.arena(7, 30, 16, 32, "Scent Trail (QA)"))
	await process_frame
	await process_frame
	var projection := Memory.project(Fixtures.memory_record())
	panel._set_memory(projection)
	var second: Dictionary = projection.visits[1]
	var center := (Vector2(second.region[0], second.region[1]) + Vector2.ONE * 0.5) * float(projection.region_size)
	_expect(panel._map.region_at(center) == second.key and panel._map.region_at(Vector2(900, 500)).is_empty(), "region hit test through world coordinates")
	panel._pressed(panel.overview.view_to_world(panel.overview.world_to_view(center)))
	_expect(panel.selected_key == second.key and panel._map.selected_key == second.key and "(150.0, 110.0)" in panel.details.text, "a click selects the region and its row")
	host.size = Vector2(960, 500)
	await process_frame
	await process_frame
	_expect(panel.size.is_equal_approx(Vector2(960, 500)) and panel.selected_key == second.key and panel._map.region_at(center) == second.key, "selection and hit test survive a resize")
	panel._hover(center)
	_expect("remembered visit #2" in panel.readout.text, "hover names the remembered visit")
	panel._hover(Vector2(900, 500))
	_expect("not remembered" in panel.readout.text, "blank ground is unvisited or forgotten, never confirmed empty")
	host.queue_free()
	await process_frame
