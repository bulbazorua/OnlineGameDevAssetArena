extends SceneTree

const Artifact = preload("res://characters/character_artifact.gd")
const View = preload("res://characters/character_view.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for key in ["archer", "orc"]:
		var result := Artifact.read_current(key)
		if not result.error.is_empty():
			push_error(result.error)
			quit(1)
			return
		await _check_views(key, result)
		await _check_harness(key)
	if failures.is_empty():
		print("PASS: Archer/Orc body calibration, every clip frame, mirrored ground anchors, independent instances and explicit staged-candidate UI")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _check_views(key: String, result: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var a := View.new()
	var b := View.new()
	viewport.add_child(a)
	viewport.add_child(b)
	a.position = Vector2(160, 210)
	a.self_modulate = Color(1, 1, 1, 0) # Measure sprite pixels without the owner ring.
	b.hide()
	var art = result.candidate.art
	for size in [1.0, 1.5]:
		a.configure_art(art, 1, size, 0.375)
		b.configure_art(art, 2, size, 0.375)
		b.present_art("idle", "east", "default", 0)
		for facing in ["east", "west"]:
			for role: String in result.report.renderable_roles:
				var variant := "primary" if role == "attack" else "default"
				var binding: Dictionary = art.binding_for(role, facing, variant)
				var clip: Dictionary = art.clips[binding.clip]
				for index in clip.frames.size():
					_expect(a.present_art(role, facing, variant, float(index) / clip.fps + 0.00001), "Valid art could not be sampled")
					_expect(a.presented_frame == index and b.presented_frame == 0, "Shared art leaked playback state")
					_expect(is_equal_approx(a.body_bounds().size.y, 32 * size), "%s body scale changed across clips" % key)
					var feet := a.body_sprite.to_global(art.foot_anchor_px + a.body_sprite.offset)
					_expect(feet.is_equal_approx(a.global_position), "%s feet moved under scaling/mirroring" % key)
					if DisplayServer.get_name() == "headless": continue
					await process_frame
					await RenderingServer.frame_post_draw
					var used: Rect2i = _visible_bounds(a.body_sprite.texture.get_image())
					var expected: Rect2 = a.body_sprite.global_transform * Rect2(Vector2(used.position) + a.body_sprite.offset, used.size)
					var actual: Rect2 = _visible_bounds(viewport.get_texture().get_image())
					_expect((actual.position - expected.position).abs().x <= 2 and (actual.position - expected.position).abs().y <= 2 and (actual.end - expected.end).abs().x <= 2 and (actual.end - expected.end).abs().y <= 2,
						"%s %s/%s frame %d rendered bounds differ: %s vs %s" % [key, role, facing, index, actual, expected])
	a.present_art("death", "east", "default", 100)
	_expect(a.presented_frame == (6 if key == "archer" else 3), "%s death did not retain final pose" % key)
	a.present_art("hurt", "east", "default", 100)
	_expect(a.presented_frame == (5 if key == "archer" else 3), "%s hurt did not retain final pose" % key)
	viewport.queue_free()
	await process_frame


func _check_harness(key: String) -> void:
	var harness = load("res://dev/character_harness.tscn").instantiate()
	harness.module_path = "res://characters/packages/" + key
	root.add_child(harness)
	harness.paused = true
	_expect(harness.candidate != null and harness.candidate.module_key == key and harness.views[0].visible, "%s successful output was unavailable" % key)
	_expect(harness.report.art_pass and not harness.report.selection_eligible, "%s art checks failed or granted combat admission" % key)
	harness.preview_source.select(1)
	harness.preview_source.item_selected.emit(1)
	_expect(harness.artifact_path.contains("/stage/") and harness.build_status.text.contains("STAGED CANDIDATE"), "Candidate artifact was mislabeled as a successful generation")
	harness.preview_source.select(0)
	harness.preview_source.item_selected.emit(0)
	for role in ["idle", "walk", "attack", "hurt", "death"]:
		harness.select_role(role)
		harness.elapsed = 100 if role == "death" else (0.15 if role == "hurt" else 0.30)
		harness._present()
		_expect(harness.views[0].visible and harness.views[0].body_sprite.visible and harness.views[1].body_sprite.visible, "%s/%s failed to display" % [key, role])
		if DisplayServer.get_name() != "headless": await _capture(key + "-" + role)
	# The missing-role demonstration remains a preview-only mutation of a fresh load.
	harness.missing.button_pressed = true
	harness.load_module()
	harness.select_role("hurt")
	_expect(not harness.report.art_pass and not harness.views[0].visible and harness.views[1].body_sprite.visible, "Missing-role demonstration lost its diagnostic or affected independent idle")
	harness.missing.button_pressed = false
	harness.load_module()
	_expect(harness.report.art_pass, "Preview mutation changed the saved artifact")
	harness.queue_free()
	await process_frame


func _capture(name: String) -> void:
	for size in [Vector2i(900, 800), Vector2i(800, 760)]:
		root.size = size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../build/verification/characters/modules")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join("%s-%dx%d.png" % [name, size.x, size.y]))


func _visible_bounds(image: Image) -> Rect2i:
	# Uploaded sheets have faint alpha specks outside the poses. Compare visible
	# silhouettes; nearest-neighbor minification can legitimately drop those specks.
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	for index in range(3, pixels.size(), 4):
		if pixels[index] < 32: pixels[index] = 0
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels).get_used_rect()


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
