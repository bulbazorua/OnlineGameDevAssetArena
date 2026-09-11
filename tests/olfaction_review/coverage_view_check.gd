extends SceneTree

const SensorView = preload("res://dev/senses/olfaction_sensor_view.gd")
const EVIDENCE := "res://../build/verification/olfaction-review-20260911/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(10).timeout.connect(func(): push_error("Coverage review timed out."); quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("The coverage review needs graphical rendering.")
		quit(1)
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE + "no-sampled-cells.json"))
	assert(fixture.cells_sampled == 0 and fixture.sample.reading_count == 0)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(700, 500)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := SensorView.new()
	view.size = Vector2(700, 500)
	viewport.add_child(view)
	view.set_sample({"olfaction": fixture.sample}, [], fixture.tile_size)
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := viewport.get_texture().get_image()
	assert(capture.save_png(ProjectSettings.globalize_path(EVIDENCE + "zero-coverage-panel.png")) == OK)
	var near_unknown := capture.get_pixel(325, 200)
	var far_unknown := capture.get_pixel(325, 100)
	var result := {"cells_sampled": fixture.cells_sampled, "range": fixture.sample.profile.range,
		"tile_size": fixture.tile_size, "near_unknown_color": near_unknown.to_html(),
		"far_unknown_color": far_unknown.to_html()}
	var output := FileAccess.open(EVIDENCE + "coverage-render.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	if not near_unknown.is_equal_approx(far_unknown):
		push_error("Zero cells were sampled, but the outer ring uses a different fill from the unsampled center: " + JSON.stringify(result))
		quit(1)
		return
	print("PASS: zero sampled cells have no sampled-empty annulus.")
	quit(0)
