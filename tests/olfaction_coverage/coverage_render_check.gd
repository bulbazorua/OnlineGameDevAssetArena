extends SceneTree

# Renders the actual Olfaction control with production-generated samples and reads
# pixels back: unknown ground stays dark, measured ground is faint, partly measured
# ground is striped, and the legend fits at the supported minimum size.
const SensorView = preload("res://dev/senses/olfaction_sensor_view.gd")
const EVIDENCE := "res://../build/verification/olfaction-fix-20260911/"
const SIZES := [Vector2i(700, 500), Vector2i(400, 350)]
var results: Array = []
var failures: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Coverage render check timed out."); quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("The coverage render check needs graphical rendering.")
		quit(1)
		return
	for label in ["zero-coverage", "partial-coverage", "full-coverage-empty"]:
		var fixture = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE + "fixtures/" + label + ".json"))
		if not fixture is Dictionary:
			failures.append("missing fixture " + label)
			continue
		for size in SIZES:
			await _check(label, fixture, size)
	var output := FileAccess.open(EVIDENCE + "captures/coverage-render.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"results": results, "failures": failures}, "\t") + "\n")
	output.close()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: zero, partial and full coverage render honestly at %d sizes." % SIZES.size())
	quit(0 if failures.is_empty() else 1)


func _check(label: String, fixture: Dictionary, size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := SensorView.new()
	view.size = Vector2(size)
	viewport.add_child(view)
	var readings: Array[Dictionary] = view.Readings.current(fixture.sample)
	view.set_sample({"olfaction": fixture.sample}, readings, float(fixture.tile_size))
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := viewport.get_texture().get_image()
	var name := "coverage-%s-%dx%d" % [label, size.x, size.y]
	capture.save_png(ProjectSettings.globalize_path(EVIDENCE + "captures/" + name + ".png"))
	var geometry: Dictionary = view.plot_geometry()
	var result := {"fixture": label, "size": [size.x, size.y], "legend_fits": view.legend_fits(), "counts": view.coverage_counts(), "zones": {}}
	if not result.legend_fits: failures.append("%s: legend overflows the view" % name)
	for zone in 16:
		var word: String = fixture.sample.coverage[zone]
		var scented := readings.any(func(row): return row.zones[zone] != "None")
		var colors := _probe(capture, geometry, zone)
		result.zones[str(zone)] = {"coverage": word, "scented": scented, "colors": colors}
		if colors.is_empty(): continue
		var unknown := _share(colors, view.UNKNOWN)
		var measured := _share(colors, view.MEASURED)
		match word:
			"Unsampled":
				if unknown < 0.9: failures.append("%s zone %d: unknown ground is not drawn dark: %s" % [name, zone, colors])
			"Sampled":
				if scented and measured + unknown > 0.1: failures.append("%s zone %d: scent wedge missing over measured ground: %s" % [name, zone, colors])
				if not scented and measured < 0.9: failures.append("%s zone %d: measured empty ground is not the faint fill: %s" % [name, zone, colors])
			"Partial":
				if not scented and (_share(colors, view.STRIPE) == 0 or unknown == 0): failures.append("%s zone %d: partly measured ground is not striped: %s" % [name, zone, colors])
	results.append(result)
	viewport.queue_free()


func _share(colors: Array, expected: Color) -> float:
	var html := expected.to_html(false)
	return float(colors.filter(func(c): return c == html).size()) / colors.size()


# Pixels along one zone's band, 12° off the sector centre so a bearing arrow never
# lies under the probe, and clear of the centre marker, ring lines and wedge edges.
func _probe(capture: Image, geometry: Dictionary, zone: int) -> Array:
	var colors: Array = []
	var far := zone % 2 == 1
	var inner: float = maxf(geometry.radius * 0.5, geometry.blind) if far else geometry.blind
	var outer: float = geometry.radius if far else geometry.radius * 0.5
	var start: float = inner + (5.0 if far else 24.0)
	if outer - 5.0 - start < 8.0: return colors
	var angle := (zone / 2) * PI / 4.0 - PI / 2.0 + deg_to_rad(12.0)
	var distance := start
	while distance < outer - 5.0:
		var point: Vector2 = geometry.center + Vector2.from_angle(angle) * distance
		colors.append(capture.get_pixel(int(point.x), int(point.y)).to_html(false))
		distance += 1.0
	return colors
