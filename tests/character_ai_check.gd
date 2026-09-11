extends "./trainers_check.gd"

# Real host, two players and a delayed audience: creatures observe and turn in
# place through the production sensing/worker/action path. Shared movement
# presentation (first-step timing) is still checked through presenter fixtures.
const Presenter = preload("res://characters/character_motion_presenter.gd")
const CharacterView = preload("res://characters/character_view.gd")
var live_history: Dictionary = {}
var recording_live := true
var audience_checked := 0
var player_checked := 0
var failure := ""
var facings := [{}, {}]
var turns := [0, 0]
var last_facing := [-1, -1]
var last_tick := -1
var last_round := -1
var start_positions: Array = []


func _host_arguments() -> PackedStringArray:
	# Deliberately omit --audience-delay: the actual default must delay AI too.
	return PackedStringArray(["--bind=127.0.0.1", "--port=%d" % port, "--content-dir=" + ProjectSettings.globalize_path("res://content/data"), "--seed=42", "--dev", "--dev-observe-only", "--dev-p1=archer", "--dev-p2=orc", "--dev-arena=tiny_swords_village"])


func _check() -> String:
	var check := _check_presenter()
	if not check.is_empty(): return check
	await _capture_first_steps()
	var first = _new_client()
	first.network.session_changed.connect(_record_live)
	first.network.world_changed.connect(_record_live)
	if not await _wait_for(func(): return first.network.session != null): return "P1 failed to join."
	var second = _new_client()
	second.network.world_changed.connect(_record_second)
	var audience = _new_client(true)
	audience.network.session_changed.connect(_record_audience)
	audience.network.world_changed.connect(_record_audience)
	if not await _wait_for(func(): return _entered(first) and _entered(second)): return "Characters failed to enter."
	start_positions = first.network.session.characters.map(func(c): return c.position)
	var initial_facings: Array = first.network.session.characters.map(func(c): return c.facing)
	if initial_facings != [2, 6]: return "Unexpected spawn facings: %s" % str(initial_facings)
	if not await _wait_for(func(): return first.network.session.summon_elapsed_ticks == 90): return "Summon never completed."
	await _capture(first, "ai-idle")
	# Empty field ahead: both scan clockwise, then notice and watch their own trainer.
	if not await _wait_for(func(): return first.network.session.characters.all(func(c): return c.facing != initial_facings[c.owner_id - 1]), 4000): return "Neither creature turned after the summon lock."
	await _capture(first, "ai-turned-p1")
	if not await _wait_for(func(): return _facings(first) == [6, 2], 6000): return "Creatures did not settle facing their own trainers: %s" % str(_facings(first))
	await create_timer(0.4).timeout
	if _facings(first) != [6, 2]: return "Attention did not hold on the observed trainer."
	if turns[0] < 3 or turns[1] < 3: return "Scan produced too few observed turns: %s" % str(turns)
	if not failure.is_empty(): return failure
	await _capture(first, "ai-observe-p1")
	await _capture(second, "ai-observe-p2")
	if not await _wait_for(func(): return _entered(audience), 7000): return "Audience did not receive historical arena state."
	if audience.network.audience_delay_ms != 5000: return "AI changed the default audience delay."
	if not await _wait_for(func(): return audience_checked >= 12 and facings[0].size() >= 3 and facings[1].size() >= 3, 12000): return "Not enough delayed observation states: %d" % audience_checked
	if not failure.is_empty(): return failure
	for client in clients:
		for c in client.network.session.characters:
			if c.input_mask != 0 or c.applied_input_sequence != 0: return "AI reused trainer input fields."
			if c.position != start_positions[c.owner_id - 1]: return "Observe translated a creature."
			if c.locomotion != 0: return "Turning in place reported walking."
			var view = client.game_arena.character_views[c.entity_id]
			if view.animation_set == null or not view.action_label.visible or view.action_label.text != "idle": return "Animated character or dev action label missing/wrong."
			if view.animator.facing != GameProtocol.FACING_NAMES[c.facing]: return "Presented facing differs from the host facing."
	# Stop one client's transport: presentation reaches its last sample then freezes.
	recording_live = false
	first.network.set_process(false)
	await create_timer(0.2).timeout
	var view = first.game_arena.character_views.values()[0]
	var frozen: Vector2 = view.position
	var frozen_facing: String = view.animator.facing
	await create_timer(0.35).timeout
	if view.position != frozen or view.animator.facing != frozen_facing: return "Stalled feed extrapolated autonomous motion or facing."
	first.network.set_process(true)
	await create_timer(0.2).timeout # Drain intentionally delayed transport before timing samples.
	recording_live = true
	# Legitimate new evidence: P1's trainer walks east past its creature, out of its
	# focused field. The creature keeps position, loses sight, remembers, then scans.
	var before_move: int = turns[0]
	_key(first, KEY_D, true)
	await create_timer(1.3).timeout
	_key(first, KEY_D, false)
	if not await _wait_for(func(): return turns[0] > before_move, 6000): return "Losing the observed trainer never led to reacquisition or scanning."
	for client in [first, second]:
		for c in client.network.session.characters:
			if c.position != start_positions[c.owner_id - 1] or c.locomotion != 0: return "Trainer movement made a creature translate or walk."
	if not await _wait_for(func(): return audience.network.session.characters.any(func(c): return c.facing != initial_facings[c.owner_id - 1]), 5000): return "Audience never reached autonomous turning on its delayed timeline."
	if player_checked < 12: return "Not enough matching player snapshots."
	var late = _new_client(true)
	if not await _wait_for(func(): return _entered(late)): return "Late audience missed autonomous entities."
	if late.network.session.summon_elapsed_ticks != 90: return "Late viewer restarted summoning."
	audience.game_arena.set_camera_owner(1)
	await _capture(audience, "ai-audience-delayed")
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return clients.all(func(c): return c.network.session.phase == SessionSnapshot.Phase.LOBBY), 7500): return "Reset failed on delayed audience."
	for client in clients:
		if not client.game_arena.character_presenters.is_empty(): return "Reset retained autonomous presenters."
	# Normal Ready path, mirror shapes: same production tick, no special dev brain.
	first.network.request_start_selection()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.SELECTING): return "Could not replay."
	first.network.request_character(3)
	second.network.request_character(3)
	if not await _wait_for(func(): return first.network.session.players[0].character_id == 3 and second.network.session.players[1].character_id == 3): return "Mirror shape selection failed."
	first.network.request_set_ready(3, true)
	second.network.request_set_ready(3, true)
	if not await _wait_for(func(): return _entered(first) and first.network.session.characters.any(func(c): return c.facing not in [2, 6]), 11000): return "Mirror shapes did not scan after the normal countdown."
	if first.network.session.characters.any(func(c): return c.locomotion != 0): return "Mirror shapes walked instead of turning."
	if first.game_arena.character_views.values().any(func(v): return v.visual == null or v.action_label.text != "idle"): return "Shape action presentation failed."
	second.network.disconnect_from_host()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.LOBBY): return "Fighter departure did not reset AI round."
	return failure


func _facings(client: Node) -> Array:
	return client.network.session.characters.map(func(c): return c.facing)


func _record_live(state) -> void:
	if not recording_live: return
	if state.phase != SessionSnapshot.Phase.IN_ARENA: return
	var key := Vector2i(state.round_id, state.server_tick)
	if not live_history.has(key): live_history[key] = {"received": Time.get_ticks_msec(), "state": state}
	# Reliable session states and unreliable world states interleave; judge turns
	# only along newer ticks of the same round, as the arena presentation does.
	if state.round_id != last_round:
		last_round = state.round_id
		last_tick = -1
		last_facing = [-1, -1]
	if last_tick >= 0 and not GameProtocol.serial_is_newer(state.server_tick, last_tick): return
	last_tick = state.server_tick
	for c in state.characters:
		facings[c.owner_id - 1][c.facing] = true
		if last_facing[c.owner_id - 1] >= 0 and c.facing != last_facing[c.owner_id - 1]:
			# 20 Hz snapshots can skip a single six-tick step; never more than two steps.
			var steps: int = (c.facing - last_facing[c.owner_id - 1] + 8) % 8
			if steps > 4: steps -= 8
			if absi(steps) > 2: failure = "A creature turned more than two 45° steps between snapshots."
			turns[c.owner_id - 1] += 1
		last_facing[c.owner_id - 1] = c.facing
		if c.locomotion != 0: failure = "Observe reported a walk locomotion."
		if not start_positions.is_empty() and c.position != start_positions[c.owner_id - 1]: failure = "Observe translated a creature."


func _record_second(state) -> void:
	var key := Vector2i(state.round_id, state.server_tick)
	if not live_history.has(key): return
	for index in 2:
		var a = state.characters[index]
		var b = live_history[key].state.characters[index]
		if a.position != b.position or a.locomotion != b.locomotion or a.facing != b.facing or a.state_start_tick != b.state_start_tick:
			failure = "Player clients received different character state for the same tick."
	player_checked += 1


func _record_audience(state) -> void:
	if state.phase != SessionSnapshot.Phase.IN_ARENA: return
	var key := Vector2i(state.round_id, state.server_tick)
	# Audience captures are independently sampled. Check shared ticks directly;
	# other captured ticks are covered by the server history/value-isolation test.
	if not live_history.has(key): return
	var live = live_history[key]
	if Time.get_ticks_msec() - live.received < 4850: failure = "Audience received an AI frame before the configured delay."
	for index in 2:
		var a = state.characters[index]
		var b = live.state.characters[index]
		if a.entity_id != b.entity_id or a.position != b.position or a.locomotion != b.locomotion or a.facing != b.facing or a.state_start_tick != b.state_start_tick:
			failure = "Audience facing/action differs from the host's historical frame."
	audience_checked += 1


func _check_presenter() -> String:
	var content := GameContent.new()
	var error := content.load_catalog()
	if not error.is_empty(): return error
	for id in [5, 6]:
		for fps in [30, 60, 120]:
			for phase in 8:
				error = _check_first_step(content, id, fps, float(phase) / 4.0)
				if not error.is_empty(): return error
	var view := CharacterView.new()
	var presenter := Presenter.new(view)
	var idle := SessionSnapshot.CharacterState.new()
	idle.position = Vector2(20, 20)
	idle.state_start_tick = 100
	idle.facing = 2
	presenter.push(idle, 110)
	var walking := SessionSnapshot.CharacterState.new()
	walking.position = idle.position
	walking.locomotion = 1
	walking.facing = 2
	walking.state_start_tick = 112
	presenter.push(walking, 113)
	presenter.advance(1.0 / 60.0)
	if view.animator.action != "idle" or view.position != idle.position: view.free(); return "Presenter moved or exposed walk before its transition tick."
	presenter.advance(2.0 / 60.0)
	if view.animator.action != "walk" or not is_equal_approx(view.animator.elapsed, 1.0 / 60.0): view.free(); return "Presenter failed to sample authoritative walk timing."
	presenter.push(walking, 116)
	presenter.advance(1.0)
	# A skipped packet spans the planted first step and the first displacement.
	walking = _motion_state(1, 112, Vector2(21, 20))
	presenter.push(walking, 124)
	presenter.advance(7.0 / 60.0) # represented tick 123, just before movement
	if view.position != idle.position: view.free(); return "Position interpolation slid through the planted first step."
	presenter.advance(0.5 / 60.0)
	if not view.position.is_equal_approx(Vector2(20.5, 20)): view.free(); return "First movement was not confined to its host tick."
	presenter.advance(0.5 / 60.0)
	# Last movement completes at 125; idle starts at 126, within this packet pair.
	var stopped := _motion_state(0, 126, Vector2(22, 20))
	presenter.push(stopped, 127)
	presenter.advance(2.0 / 60.0)
	if view.animator.action != "idle" or view.position != stopped.position: view.free(); return "Idle pose slid after walking stopped."
	presenter.advance(1.0 / 60.0)
	# A facing-only change while idle turns the pose without inventing a walk.
	idle = SessionSnapshot.CharacterState.new()
	idle.position = Vector2(22, 20)
	idle.facing = 6
	idle.state_start_tick = 126
	presenter.push(idle, 130)
	presenter.advance(1.0)
	if view.animator.action != "idle" or view.animator.facing != "west" or view.position != Vector2(22, 20): view.free(); return "Turn in place invented movement or kept the old facing."
	# Tick wrap and late-join age.
	presenter = Presenter.new(view)
	idle.state_start_tick = 0xfffffffe
	presenter.push(idle, 1)
	if not is_equal_approx(view.animator.elapsed, 3.0 / 60.0): view.free(); return "Presenter mishandled wrapped animation age."
	# A new packet arriving mid-blend must not jump or restart the animation clock.
	presenter = Presenter.new(view)
	walking = _motion_state(1, 112, Vector2(20, 20))
	presenter.push(walking, 113)
	presenter.push(walking, 116)
	presenter.advance(1.0 / 60.0)
	var age := view.animator.elapsed
	presenter.push(walking, 119)
	if not is_equal_approx(view.animator.elapsed, age): view.free(); return "Early packet skipped the displayed animation time."
	presenter.advance(1.0)
	if not is_equal_approx(view.animator.elapsed, 7.0 / 60.0): view.free(); return "Presenter did not settle at the received state age."
	view.free()
	return ""


func _motion_state(role: int, start: int, position: Vector2) -> SessionSnapshot.CharacterState:
	var state := SessionSnapshot.CharacterState.new()
	state.locomotion = role
	state.state_start_tick = start
	state.position = position
	state.facing = 2
	return state


func _check_first_step(content: GameContent, id: int, fps: int, phase: float) -> String:
	var view := CharacterView.new()
	content.configure_character(view, id)
	var presenter := Presenter.new(view)
	var origin := Vector2(20, 20)
	# Literal host fixture: walk at 112, first movement at 124. Also verifies
	# late joins midway through preparation do not restart the clip.
	presenter.push(_motion_state(1, 112, origin), 116)
	presenter.push(_motion_state(1, 112, origin + Vector2(64.0 / 60.0, 0)), 124)
	presenter.advance(phase / 60.0)
	var stepped_in_place := false
	var moved := false
	for frame in fps / 5:
		presenter.advance(1.0 / fps)
		if view.position.is_equal_approx(origin) and view.presented_frame >= 1:
			stepped_in_place = true
		if not view.position.is_equal_approx(origin):
			moved = true
			if not stepped_in_place:
				view.free()
				return "%s moved before its first visible step at %d FPS (phase %.2f)." % [content.by_id[id].key, fps, phase]
	view.free()
	return "" if moved and stepped_in_place else "Walk timing check did not exercise both preparation and movement."


func _capture(client: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../build/verification/character-ai")
	DirAccess.make_dir_recursive_absolute(folder)
	client.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))


func _capture_first_steps() -> void:
	if DisplayServer.get_name() == "headless": return
	var content := GameContent.new()
	if not content.load_catalog().is_empty(): return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1260, 440)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1260, 440)
	backdrop.color = Color("18232e")
	viewport.add_child(backdrop)
	var ages := [0, 4, 8, 11, 12, 18]
	for row in 2:
		for column in ages.size():
			var parent := Node2D.new()
			parent.position = Vector2(100 + column * 200, 165 + row * 210)
			parent.scale = Vector2(3, 3)
			viewport.add_child(parent)
			var marker := Line2D.new()
			marker.points = PackedVector2Array([Vector2(0, -40), Vector2(0, 7)])
			marker.width = 0.5
			marker.default_color = Color("677d8b")
			parent.add_child(marker)
			var view := CharacterView.new()
			content.configure_character(view, row + 5, row + 1)
			parent.add_child(view)
			var presenter := Presenter.new(view)
			presenter.push(_motion_state(1, 112, Vector2.ZERO), 112)
			presenter.push(_motion_state(1, 112, Vector2(7.0 * 64.0 / 60.0, 0)), 130)
			presenter.advance(presenter.interval * float(ages[column]) / 18.0)
			var label := Label.new()
			label.position = Vector2(column * 200, 8 + row * 210)
			label.size.x = 200
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.text = "%s · %d ms\nPose %d · moved %.1f" % [content.by_id[row + 5].display_name, roundi(ages[column] * 1000.0 / 60.0), view.presented_frame + 1, view.position.x]
			viewport.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../build/verification/character-ai")
	DirAccess.make_dir_recursive_absolute(folder)
	viewport.get_texture().get_image().save_png(folder.path_join("walk-first-step-sequence.png"))
	viewport.queue_free()
