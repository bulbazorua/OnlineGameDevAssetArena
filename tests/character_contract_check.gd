extends SceneTree

const Builder = preload("res://characters/import/character_package_builder.gd")
const Contract = preload("res://content/character_contract.gd")
const View = preload("res://characters/character_view.gd")
const ROOT := "res://dev/fixtures/characters/"
var failures: Array[String] = []
var contract := Contract.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(contract.load_contract().is_empty(), "Contract failed to load.")
	_expect(contract.data.roles.keys() == ["idle", "walk", "hurt", "attack", "death"], "Base role vocabulary changed.")
	for key in ["reference16", "reference32"]:
		var result := Builder.inspect_module(ROOT + key)
		_expect(result.error.is_empty(), "Reference module did not build.")
		_expect(result.report.art_pass and not result.report.selection_eligible, "Art proof incorrectly grants admission or fails.")
		_expect(result.report.checks.any(func(check): return check.id == "combat" and check.status == "not_run"), "Unimplemented combat was certified.")
	var missing = _fresh()
	missing.art.bindings.assign(missing.art.bindings.filter(func(binding): return binding.role not in ["hurt", "death"]))
	var report := contract.inspect(missing)
	_expect(_failed(report, "role.hurt") and _failed(report, "role.death"), "Missing roles did not fail clearly.")
	_expect("idle" in report.renderable_roles and "hurt" not in report.renderable_roles, "Incomplete preview hides valid roles or invents missing ones.")
	_expect(_failed(contract.inspect(null), "exports"), "Absent export accepted.")
	var no_art = _fresh()
	no_art.art = null
	_expect(_failed(contract.inspect(no_art), "exports"), "Absent art export accepted.")
	for version in ["1.0.0", "2.0.0", ""]:
		var changed = _fresh()
		changed.contract_version = version
		_expect(_failed(contract.inspect(changed), "exports"), "Unsupported version accepted.")
	for value in [0, -1, NAN, INF]:
		var changed = _fresh()
		changed.art.reference_span_px = value
		_expect(_failed(contract.inspect(changed), "metrics"), "Invalid body size accepted.")
	for mutation in ["empty", "fps", "loop", "outside", "duplicate", "unknown", "facing", "ai", "effect"]:
		var changed = _fresh()
		match mutation:
			"empty": changed.art.clips.rest.frames = []
			"fps": changed.art.clips.rest.fps = NAN
			"loop": changed.art.clips.fallen.loop = true
			"outside": changed.art.foot_anchor_px = Vector2(100, 0)
			"duplicate": changed.art.bindings.append(changed.art.bindings[0].duplicate())
			"unknown": changed.art.bindings[0].role = "Archer_idle"
			"facing": changed.art.bindings.pop_front()
			"ai": changed.ai = {}
			"effect":
				for binding in changed.art.bindings:
					if binding.role == "hurt": binding.kind = "hurt_flash"
		var invalid := contract.inspect(changed)
		_expect(not invalid.art_pass and not invalid.selection_eligible, "Invalid export accepted: " + mutation)
	_expect(not Builder.inspect_module(ROOT + "absent").error.is_empty(), "Module without custom entry points accepted.")
	_expect(not Builder.inspect_module("res://../outside").error.is_empty(), "Invalid module path accepted.")
	await _check_views()
	await _check_harness()
	if failures.is_empty():
		print("PASS: draft contract, required roles, invalid exports, normalized bounds/feet, independent playback, harness controls and no admission.")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _check_views() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, 160)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var first := View.new()
	var second := View.new()
	viewport.add_child(first)
	viewport.add_child(second)
	first.position = Vector2(80, 100)
	first.self_modulate = Color(1, 1, 1, 0) # Hide owner ring only for pixel measurements.
	second.hide()
	for key in ["reference16", "reference32"]:
		var art = Builder.inspect_module(ROOT + key).candidate.art
		for size in [1.0, 1.5]:
			first.configure_art(art, 1, size, 0.375)
			second.configure_art(art, 2, size, 0.375)
			for facing in ["east", "west"]:
				first.present_art("walk", facing, "default", 0.30)
				second.present_art("idle", "east", "default", 0.0)
				_expect(first.presented_frame == 1 and second.presented_frame == 0, "Shared art leaks per-instance playback.")
				var bounds := first.body_bounds()
				_expect(bounds.size.is_equal_approx(Vector2.ONE * 32 * size), "Source resolution changed body world size.")
				var feet := first.body_sprite.to_global(art.foot_anchor_px + first.body_sprite.offset)
				_expect(feet.is_equal_approx(first.global_position), "Mirroring or scaling moved the foot anchor.")
				var image: Image = first.body_sprite.texture.get_image()
				var opaque: Rect2 = first.body_sprite.transform * Rect2(Vector2(image.get_used_rect().position) + first.body_sprite.offset, image.get_used_rect().size)
				_expect(opaque.is_equal_approx(bounds), "Padding affected rendered body bounds.")
				if DisplayServer.get_name() != "headless":
					await process_frame
					await RenderingServer.frame_post_draw
					var rendered := viewport.get_texture().get_image().get_used_rect()
					_expect(rendered.size == Vector2i(Vector2.ONE * 32 * size), "Rendered pixels disagree with 32/48 world-unit size: %s" % rendered)
		first.present_art("death", "east", "default", 100)
		_expect(first.presented_frame == 1, "Death clip did not hold its final pose.")
		first.present_art("idle", "east", "default", 1.0)
		_expect(first.presented_frame == 0, "Looping idle did not wrap.")
	viewport.queue_free()
	await process_frame


func _check_harness() -> void:
	var harness = load("res://dev/character_harness.tscn").instantiate()
	root.add_child(harness)
	harness.paused = true
	_expect(harness.report.art_pass and not harness.report.selection_eligible, "Harness misreports admission.")
	harness.role_buttons.attack.pressed.emit()
	_expect(harness.role == "attack", "Role button did not target canonical attack.")
	harness.size_input.value = 1.5
	_expect(harness.views[0].body_bounds().size == Vector2(48, 48), "Size control did not update the real CharacterView.")
	if DisplayServer.get_name() != "headless":
		await _capture("complete")
	harness.role_buttons.hurt.pressed.emit()
	harness.missing.button_pressed = true
	_expect(_failed(harness.report, "role.hurt") and _failed(harness.report, "role.death"), "Missing-state demo did not revalidate.")
	_expect(not harness.views[0].visible, "Missing hurt displayed a healthy idle fallback.")
	_expect(harness.views[1].visible and harness.views[1].body_sprite.visible, "Missing A role hid B's valid independent idle.")
	if DisplayServer.get_name() != "headless":
		await _capture("missing")
	harness.modules.select(1)
	harness.modules.item_selected.emit(1)
	harness.missing.button_pressed = false
	harness.role_buttons.idle.pressed.emit()
	_expect(harness.candidate.module_key == "reference32" and harness.views[0].body_bounds().size == Vector2(48, 48), "Switching native resolution changed body size.")
	harness.save_report()
	harness.module_path = ROOT + "absent"
	harness.load_module()
	harness.select_role("idle")
	_expect(harness.report.scope == "art_preview_only" and not harness.report.art_pass and not harness.report.selection_eligible, "Unavailable module lost preview-only failure status.")
	_expect(not harness.views[0].visible and not harness.views[1].visible, "Unavailable module retained previous art.")
	harness.queue_free()
	await process_frame


func _capture(name: String) -> void:
	for size in [Vector2i(900, 800), Vector2i(800, 760)]:
		root.size = size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../build/verification/characters/harness")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join("%s-%dx%d.png" % [name, size.x, size.y]))


func _fresh():
	return Builder.inspect_module(ROOT + "reference16").candidate


func _failed(report: Dictionary, id: String) -> bool:
	return report.checks.any(func(check): return check.id == id and check.status == "fail")


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
