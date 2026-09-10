extends "./trainers_check.gd"

const TrainerMotion = preload("res://players/trainer_movement.gd")
const Presenter = preload("res://characters/character_motion_presenter.gd")
const PlayerView = preload("res://players/player_view.gd")


func _check() -> String:
	var content := GameContent.new()
	var error := content.load_catalog()
	if not error.is_empty(): return error
	var arena = content.arena_catalog.arenas_by_id[1]
	var origin: Vector2 = arena.cell_center(arena.spawns[0])
	var states: Array[SessionSnapshot.TrainerState] = []
	var state := SessionSnapshot.TrainerState.new()
	state.position = origin
	# Same literal contract as Odin: walk starts at 100; first displacement at 108.
	for age in 31:
		TrainerMotion.step(state, 2, 100 + age, arena, content.arena_catalog)
		states.append(TrainerMotion.copy_state(state))
		if state.locomotion != 1 or state.state_start_tick != 100: return "Prediction restarted the walk clock."
		if age < 8 and state.position != origin: return "Prediction moved before the first plant."
		if age == 8 and state.position != origin + Vector2(2, 0): return "Predicted first movement differs from the host fixture."
	var replay := TrainerMotion.copy_state(states[3])
	for age in range(4, 9): TrainerMotion.step(replay, 2, 100 + age, arena, content.arena_catalog)
	if replay.position != states[8].position or replay.state_start_tick != 100 or states[3].position != origin: return "Reconciliation restarted preparation or mutated the received snapshot."
	TrainerMotion.step(replay, 0, 109, arena, content.arena_catalog)
	TrainerMotion.step(replay, 1, 110, arena, content.arena_catalog)
	if replay.state_start_tick != 110 or replay.position != states[8].position or replay.facing != 6: return "Release/restart bypassed the first step or failed to face left."
	var tap := TrainerMotion.copy_state(states[2])
	TrainerMotion.step(tap, 0, 103, arena, content.arena_catalog)
	if tap.position != origin or tap.locomotion != 0: return "Short tap did not cancel preparation."
	var late := PlayerView.new()
	content.player_content.configure_view(late, 1, 1)
	var late_presenter := Presenter.new(late, GameProtocol.TRAINER_WALK_START_TICKS)
	late_presenter.push(states[30], 130)
	if late.presented_frame != 5 or late.position != states[30].position:
		late.free()
		return "Late trainer view replayed preparation instead of sampling the current pose."
	late_presenter.advance(1.0)
	if late.animator.elapsed != 0.5 or late.position != states[30].position:
		late.free()
		return "Stalled trainer feed extrapolated animation or position."
	# Only the action's first two frames accelerate. Later loop passes stay at
	# 8 FPS, while the observable animation clock remains the actual action age.
	for sample in [[0.0, 0], [0.035, 1], [0.070, 2], [0.84, 0], [0.94, 0], [0.96, 1]]:
		late.present_locomotion("walk", "east", sample[0])
		if late.presented_frame != sample[1] or late.animator.elapsed != sample[0]:
			late.free()
			return "Walk acceleration repeated on the loop or changed the action clock."
	late.present_locomotion("idle", "east", 0.2)
	if late.presented_frame != 1: late.free(); return "Walk startup changed idle playback."
	late.free()
	for fps in [30, 60, 120]:
		for phase in 8:
			error = _check_render_timing(content, states, fps, float(phase) / 4.0)
			if not error.is_empty(): return error
	await _capture_step_sequence(content, states)
	return await super._check()


func _check_render_timing(content: GameContent, states: Array[SessionSnapshot.TrainerState], fps: int, phase: float) -> String:
	for remote in [false, true]:
		var view := PlayerView.new()
		content.player_content.configure_view(view, 1, 1)
		var presenter := Presenter.new(view, GameProtocol.TRAINER_WALK_START_TICKS)
		presenter.push(states[0], 100)
		presenter.push(states[8], 108)
		presenter.advance(phase / 60.0)
		var planted := false
		var lifted := false
		var moved := false
		for frame in ceili(fps * 0.6):
			if remote:
				presenter.advance(1.0 / fps)
			else:
				var age := minf(phase + frame * 60.0 / fps, 30.0)
				view.position = states[int(age)].position
				view.present_locomotion("walk", "east", age / 60.0)
			if view.position == states[0].position:
				lifted = lifted or view.presented_frame == 1 # Raw pose 4: raised front foot.
				planted = planted or view.presented_frame == 2 # Raw pose 5: contact.
			else:
				moved = true
				if not lifted or not planted:
					view.free()
					return "Player translated before lift/plant at %d FPS, phase %.2f, remote=%s." % [fps, phase, remote]
		view.free()
		if not moved: return "Player step test never reached translation."
	return ""


func _capture_step_sequence(content: GameContent, states: Array[SessionSnapshot.TrainerState]) -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1260, 360)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1260, 360)
	backdrop.color = Color("18232e")
	viewport.add_child(backdrop)
	var ages := [0, 2, 4, 7, 8, 12]
	var raw_poses := [3, 4, 5, 5, 5, 6]
	for column in ages.size():
		var parent := Node2D.new()
		parent.position = Vector2(90 + column * 205, 305)
		parent.scale = Vector2(5, 5)
		viewport.add_child(parent)
		var marker := Line2D.new()
		marker.points = PackedVector2Array([Vector2(0, -40), Vector2(0, 6)])
		marker.width = 0.25
		marker.default_color = Color("677d8b")
		parent.add_child(marker)
		var view := PlayerView.new()
		content.player_content.configure_view(view, 1, 1)
		parent.add_child(view)
		view.present_locomotion("walk", "east", ages[column] / 60.0)
		view.position = states[ages[column]].position - states[0].position
		var label := Label.new()
		label.position = Vector2(column * 205, 15)
		label.size.x = 205
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = "%d ms · raw pose %d\nMoved %.1f units" % [roundi(ages[column] * 1000.0 / 60.0), raw_poses[column], view.position.x]
		viewport.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../build/verification/player-step")
	DirAccess.make_dir_recursive_absolute(folder)
	viewport.get_texture().get_image().save_png(folder.path_join("player-first-step.png"))
	viewport.queue_free()
