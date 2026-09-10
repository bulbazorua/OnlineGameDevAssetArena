extends SceneTree

const Artifact = preload("res://characters/character_artifact.gd")
const Contract = preload("res://content/character_contract.gd")
const ROLES := ["idle", "walk", "run", "advise", "hurt", "cheer", "surprised", "disappointed"]
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result := Artifact.read_current("player1", "players")
	if not result.error.is_empty():
		push_error(result.error)
		quit(1)
		return
	var candidate = result.candidate
	var contract := Contract.new()
	_expect(contract.load_contract(Contract.PLAYER_PATH).is_empty(), "Player contract unavailable")
	_expect(contract.data.roles.keys() == ROLES and result.report.art_pass, "Eight required player roles changed or failed")
	var bindings: Array = candidate.art.bindings.duplicate(true)
	for role: String in ROLES:
		candidate.art.bindings.assign(bindings.filter(func(binding): return binding.role != role))
		var report := contract.inspect(candidate)
		_expect(not report.art_pass and role not in report.renderable_roles and report.renderable_roles.size() == 7, "Missing %s was accepted or invalidated unrelated roles" % role)
	candidate.art.bindings.assign(bindings)
	candidate.contract_version = "99.0.0"
	_expect(not contract.inspect(candidate).art_pass, "Unknown player contract version accepted")
	candidate.contract_version = "1.0.0-draft.1"
	var gladiator := Contract.new()
	gladiator.load_contract()
	_expect(not gladiator.inspect(candidate).art_pass, "Trainer passed the gladiator contract")
	_expect(not result.report.selection_eligible, "Art preview incorrectly admitted a gameplay entity")
	var harness = load("res://dev/player_harness.tscn").instantiate()
	root.add_child(harness)
	harness.paused = true
	_expect(harness.report.art_pass and harness.modules.item_count == 1 and harness.candidate.module_key == "player1", "Player registry/default output failed")
	_expect(harness.role_buttons.keys() == ROLES, "Harness does not expose every required player state")
	var b_frame: int = harness.views[1].presented_frame
	for size in [1.0, 1.5]:
		harness.size_input.value = size
		for facing_index in contract.data.facings.size():
			harness.facings.select(facing_index)
			var facing: String = contract.data.facings[facing_index]
			for role: String in ROLES:
				harness.role_buttons[role].pressed.emit()
				var binding: Dictionary = candidate.art.binding_for(role, facing, "default")
				var clip: Dictionary = candidate.art.clips[binding.clip]
				var expected_frames := 8 if role == "walk" else 6
				_expect(clip.frames.size() == expected_frames and binding.flip_h == ("west" in facing), "Wrong frame count or facing mapping")
				for index in expected_frames:
					harness.elapsed = float(index) / clip.fps + 0.00001
					harness._present()
					var a = harness.views[0]
					_expect(a.visible and a.body_sprite.visible and a.presented_frame == index, "Player %s frame %d invisible or sampled incorrectly" % [role, index])
					_expect(a.body_sprite.texture.get_image().get_used_rect().size != Vector2i.ZERO, "Blank processed frame")
					_expect(is_equal_approx(a.body_bounds().size.y, 32 * size), "Player gameplay size drifted between states")
					_expect(harness.views[1].presented_frame == b_frame, "Player instances share playback state")
					_expect(a.body_sprite.to_global(candidate.art.foot_anchor_px + a.body_sprite.offset).is_equal_approx(a.global_position), "Player feet moved when mirrored/scaled")
				if not clip.loop:
					harness.elapsed = 100
					harness._present()
					_expect(harness.views[0].presented_frame == expected_frames - 1, "One-shot player gesture did not retain its final pose")
				else:
					harness.elapsed = float(expected_frames) / clip.fps + 0.00001
					harness._present()
					_expect(harness.views[0].presented_frame == 0, "Player locomotion failed to loop")
	harness.size_input.value = 1
	harness.facings.select(2)
	for role: String in ROLES:
		harness.select_role(role)
		harness.elapsed = 2.01 / candidate.art.clips["trainer_" + role].fps
		harness._present()
		if DisplayServer.get_name() != "headless": await _capture(role)
	harness.missing.button_pressed = true
	harness.select_role("advise")
	_expect(not harness.report.art_pass and not harness.views[0].visible and harness.views[1].visible, "Missing advise demonstration failed")
	harness.missing.button_pressed = false
	_expect(harness.report.art_pass and harness.views[0].visible, "Preview mutation changed persisted art")
	harness.preview_source.select(1)
	harness.preview_source.item_selected.emit(1)
	_expect(harness.artifact_path.contains("/stage/") and harness.build_status.text.contains("STAGED CANDIDATE"), "Player candidate/source selector used the wrong namespace")
	harness.preview_source.select(0)
	harness.preview_source.item_selected.emit(0)
	var buttons: Array[Node] = harness.find_children("*", "Button", true, false)
	var step = buttons.filter(func(button): return button.text == "Step 1/60s")[0]
	harness.select_role("idle")
	step.pressed.emit()
	_expect(harness.paused and is_equal_approx(harness.elapsed, 1.0 / 60.0), "Player step control failed")
	var replay = buttons.filter(func(button): return button.text == "Replay")[0]
	replay.pressed.emit()
	_expect(harness.elapsed == 0 and harness.role == "idle", "Player replay control failed")
	harness.save_report()
	harness.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: eight required player states, contract separation, 50 frames in all facings/sizes, independent instances, loop policies, source selector and preview controls")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _capture(role: String) -> void:
	root.size = Vector2i(1000, 850)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../build/verification/players/harness")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join("player1-" + role + ".png"))


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
