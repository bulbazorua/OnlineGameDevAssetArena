extends SceneTree

# Renders the real pages and both local radars at the two supported window sizes on a
# rectangular arena with fixture data, reads pixels back where the fixtures say marks
# must be, and saves every capture. Needs a display; headless is reported as blocked.
const VisionPage = preload("res://dev/senses/vision_page.gd")
const OlfactionPage = preload("res://dev/senses/olfaction_page.gd")
const MemoryPanel = preload("res://dev/senses/exploration_memory_panel.gd")
const VisionView = preload("res://dev/senses/vision_sensor_view.gd")
const ScentView = preload("res://dev/senses/olfaction_sensor_view.gd")
const VisionReadings = preload("res://dev/senses/vision_readings.gd")
const ScentReadings = preload("res://dev/senses/olfaction_readings.gd")
const Memory = preload("res://dev/senses/exploration_memory.gd")
const MemoryLayer = preload("res://dev/senses/exploration_memory_layer.gd")
const Style = preload("res://dev/ui/dev_ui_style.gd")
const GameContent = preload("res://content/game_content.gd")
const FIXTURE_DIR := "user://dev-arena-overview-render"
const PAGE_SIZES := {"1200x800": Vector2(1160, 604), "1000x700": Vector2(960, 504)}
const RADAR_MINIMUM := Vector2(400, 350)
var Fixtures: GDScript
var content := GameContent.new()
var output := "res://../build/verification/dev-arena-overview-render"
var results: Dictionary = {}
var pixel_probe_count := 0
var failures: Array[String] = []


func _initialize() -> void:
	Fixtures = load(get_script().resource_path.get_base_dir().path_join("dev_arena_fixtures.gd"))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	_run.call_deferred()


func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Dev arena overview render check timed out."); quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("The dev arena overview render check needs graphical rendering; rendered checks are blocked without a display.")
		quit(1)
		return
	assert(content.load_catalog().is_empty(), "content catalog")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	var field: Dictionary = Fixtures.field_fixture(Fixtures.trail_levels(), Fixtures.trail_ages())
	field.published_us = 1000
	Fixtures.write_json(FIXTURE_DIR + "/scent.json", field)
	for label: String in PAGE_SIZES: await _render_pages(label, PAGE_SIZES[label])
	await _render_radars()
	Fixtures.write_json(output.path_join("render-results.json"), {"results": results, "pixel_probe_count": pixel_probe_count, "failures": failures})
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: three pages and both radars rendered at two window sizes on a rectangular arena; %d pixel probes match independent expectations." % pixel_probe_count)
	quit(0 if failures.is_empty() else 1)


func _viewport(size: Vector2) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _capture(viewport: SubViewport, name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(output.path_join(name + ".png")))
	return image


# One pixel against an independent expectation; the record keeps both colours.
func _probe(image: Image, point: Vector2, expected: Color, name: String, tolerance := 3.0 / 255.0) -> void:
	pixel_probe_count += 1
	var actual := image.get_pixel(int(point.x), int(point.y))
	results[name] = {"point": [int(point.x), int(point.y)], "actual": actual.to_html(false), "expected": expected.to_html(false)}
	if not Fixtures.close(Color(actual, 1.0), Color(expected, 1.0), tolerance): failures.append("%s: %s expected %s" % [name, actual.to_html(false), expected.to_html(false)])


func _bright(image: Image, point: Vector2, name: String) -> void:
	pixel_probe_count += 1
	var actual := image.get_pixel(int(point.x), int(point.y))
	results[name] = {"point": [int(point.x), int(point.y)], "actual": actual.to_html(false), "expected": "white marker"}
	if actual.r < 0.85 or actual.g < 0.85 or actual.b < 0.85: failures.append("%s: %s is not the white marker" % [name, actual.to_html(false)])


func _page_point(overview: Control, world: Vector2) -> Vector2:
	return overview.get_global_position() + overview.world_to_view(world)


func _render_pages(label: String, size: Vector2) -> void:
	var arena = Fixtures.arena(7, 30, 16, 32, "Scent Trail (QA)")
	var world := {"active": true, "round_id": 5, "map_id": 7, "entities": [3, 4]}
	var record: Dictionary = Fixtures.vision_record("East")
	var viewport := _viewport(size)
	var vision := VisionPage.new()
	vision.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(vision)
	vision.configure(content)
	vision.set_arena(arena)
	vision.set_sample(record, VisionReadings.current(record.vision))
	vision.set_status("LIVE")
	vision.refresh_text("", 0)
	var image := await _capture(viewport, "page-vision-arena-" + label)
	var placement := {"vision": _placement(vision.overview)}
	_bright(image, _page_point(vision.overview, Vector2(100, 100)), "vision arena self marker " + label)
	_probe(image, _page_point(vision.overview, Vector2(190, 100)), VisionView.FOCUS, "vision arena focused sighting " + label)
	_probe(image, vision.overview.get_global_position() + vision.overview.arena_rect().position - Vector2(4, 4), Style.BACKGROUND, "vision frame padding " + label)
	vision.select_view(vision.LOCAL_VIEW)
	image = await _capture(viewport, "page-vision-local-" + label)
	var geometry: Dictionary = vision.view.plot_geometry()
	var dot: Vector2 = vision.view.get_global_position() + geometry.center + Vector2(90, 0) * geometry.radius / 160.0
	_probe(image, dot, VisionView.FOCUS, "vision radar focused sighting " + label)
	results["vision radar component " + label] = vision.view.radar.get_script().resource_path
	vision.queue_free()
	var page := OlfactionPage.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(page)
	page.configure()
	page.set_arena(arena)
	page.set_sample(record, ScentReadings.current(record.olfaction), 32.0)
	page.set_status("LIVE")
	page.refresh_text("", 0)
	page._next_read_ms = 0
	page.update_field(FIXTURE_DIR, "fixture", "fp", world)
	if page.field_status != "LIVE": failures.append("olfaction field not live: %s %s" % [page.field_status, page.field_reason])
	image = await _capture(viewport, "page-olfaction-arena-" + label)
	placement.olfaction = _placement(page.overview)
	var ground: Color = Style.GROUND
	var ramp := [page.painter.floor_alpha, page.painter.max_alpha]
	_probe(image, _page_point(page.overview, Vector2(1.5, 1.5) * 32), Fixtures.over_ground(Fixtures.expected_cell(255, 0, ramp[0], ramp[1]), ground), "field saturated human cell " + label)
	_probe(image, _page_point(page.overview, Vector2(2.5, 3.5) * 32), Fixtures.over_ground(Fixtures.expected_cell(128, 64, ramp[0], ramp[1]), ground), "field overlapping cell " + label)
	_probe(image, _page_point(page.overview, Vector2(4.5, 2.5) * 32), Fixtures.over_ground(Fixtures.expected_cell(0, 200, ramp[0], ramp[1]), ground), "field orc cell " + label)
	_probe(image, _page_point(page.overview, Vector2(15.5, 8.5) * 32), Fixtures.over_ground(Fixtures.expected_cell(155, 0, ramp[0], ramp[1]), ground), "field wake cell " + label)
	_probe(image, _page_point(page.overview, Vector2(20.5, 8.5) * 32), Fixtures.over_ground(Fixtures.expected_cell(55, 0, ramp[0], ramp[1]), ground), "field wake tail " + label)
	_probe(image, _page_point(page.overview, Vector2(7.5, 1.5) * 32), ground, "field empty cell is ground " + label)
	_probe(image, _page_point(page.overview, Vector2(25.5, 12.5) * 32), ground, "field empty far cell is ground " + label)
	_probe(image, page.overview.get_global_position() + page.overview.arena_rect().position - Vector2(4, 4), Style.BACKGROUND, "field frame padding " + label)
	page.select_view(page.LOCAL_VIEW)
	image = await _capture(viewport, "page-olfaction-local-" + label)
	_probe_nose(image, page.view, label)
	results["olfaction radar component " + label] = page.view.radar.get_script().resource_path
	page.queue_free()
	var memory := MemoryPanel.new()
	memory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(memory)
	memory.configure(1)
	memory.set_arena(arena)
	memory._set_memory(Memory.project(Fixtures.memory_record()))
	memory.feed.error = ""
	memory.feed.updated_ms = Time.get_ticks_msec()
	memory._record_received_ms = memory.feed.updated_ms
	memory._refresh_status(memory.feed.updated_ms)
	image = await _capture(viewport, "page-memory-arena-" + label)
	placement.memory = _placement(memory.overview)
	_probe(image, _page_point(memory.overview, Vector2(110, 110)), Fixtures.over_ground(Color(MemoryLayer.FRESH, 0.36), ground), "memory fresh region fill " + label)
	_probe(image, _page_point(memory.overview, Vector2(700, 400)), ground, "memory blank ground " + label)
	_bright(image, _page_point(memory.overview, Vector2(160, 96)), "memory self marker " + label)
	results["placement " + label] = str(placement)
	for key in ["olfaction", "memory"]:
		if not placement[key][0].is_equal_approx(placement.vision[0]) or not placement[key][1].is_equal_approx(placement.vision[1]):
			failures.append("%s: %s frames the arena differently from vision" % [label, key])
	memory.queue_free()
	viewport.queue_free()
	await process_frame


# Where a page's frame sits and where it puts one world point, for the cross-page comparison.
func _placement(overview: Control) -> Array:
	return [overview.get_global_rect(), _page_point(overview, Vector2(300, 200))]


# Unknown ground dark, measured ground faint, scent over measured ground tinted; probes
# sit 12 degrees off the sector centre and away from the blind disc, rings and arrow.
func _probe_nose(image: Image, view: Control, label: String) -> void:
	var geometry: Dictionary = view.plot_geometry()
	var origin: Vector2 = view.get_global_position() + geometry.center
	var radius: float = geometry.radius
	var unknown := origin + Vector2.from_angle(Style.heading_angle(7) + deg_to_rad(12)) * radius * 0.78
	_probe(image, unknown, view.UNKNOWN, "nose unmeasured zone stays dark " + label)
	var measured := origin + Vector2.from_angle(Style.heading_angle(0) + deg_to_rad(12)) * radius * 0.3
	_probe(image, measured, view.MEASURED, "nose measured empty zone is faint " + label)
	var scented := origin + Vector2.from_angle(Style.heading_angle(2) + deg_to_rad(12)) * radius * 0.3
	_probe(image, scented, Fixtures.over_ground(Color(ScentReadings.color_of("Human"), 0.78), view.MEASURED), "nose strong human zone over measured ground " + label)


func _render_radars() -> void:
	var record: Dictionary = Fixtures.vision_record("East")
	for entry in [["vision", VisionView.new()], ["olfaction", ScentView.new()]]:
		var viewport := _viewport(RADAR_MINIMUM)
		var view: Control = entry[1]
		view.size = RADAR_MINIMUM
		viewport.add_child(view)
		if entry[0] == "vision": view.set_sample(record, VisionReadings.current(record.vision))
		else: view.set_sample(record, ScentReadings.current(record.olfaction), 32.0)
		var name: String = "radar-%s-%dx%d" % [entry[0], RADAR_MINIMUM.x, RADAR_MINIMUM.y]
		var image := await _capture(viewport, name)
		results[name] = {"legend_fits": view.legend_fits(), "component": view.radar.get_script().resource_path, "legend": view.radar.wrapped_legend()}
		if not view.legend_fits(): failures.append(name + ": legend overflows the minimum radar size")
		if entry[0] == "olfaction": _probe_nose(image, view, "minimum radar")
		else:
			var geometry: Dictionary = view.plot_geometry()
			_probe(image, view.get_global_position() + geometry.center + Vector2(90, 0) * geometry.radius / 160.0, VisionView.FOCUS, "vision minimum radar focused sighting")
		viewport.queue_free()
		await process_frame
