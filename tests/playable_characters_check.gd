extends "./host_check.gd"

const Animator = preload("res://characters/character_animator.gd")


func _host_arguments() -> PackedStringArray:
	return PackedStringArray(["--audience-delay=0.35", "--bind=127.0.0.1", "--port=%d" % port, "--content-dir=" + ProjectSettings.globalize_path("res://content/data")])


func _check() -> String:
	var animator := Animator.new()
	animator.observe_motion(Vector2(-3, -3))
	animator.advance(0.25)
	animator.observe_motion(Vector2(-3, -3))
	if animator.action != "walk" or animator.facing != "north_west" or animator.elapsed != 0.25: return "Continuous walking reset the animation clock."
	animator.observe_motion(Vector2.ZERO)
	if animator.action != "idle" or animator.facing != "north_west" or animator.elapsed != 0: return "Idle did not preserve facing/reset its own clip."
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 could not join."
	var second = _new_client()
	var watcher = _new_client(true)
	first.game_arena.debug_actions = true
	watcher.game_arena.debug_actions = true
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.LOBBY) and first.network.session.player_mask == 3): return "Lobby did not converge."
	first.network.request_start_selection()
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.SELECTING)): return "Selection did not converge."
	first.selection.cards[5].pressed.emit()
	second.selection.cards[6].pressed.emit()
	if not await _wait_for(func(): return watcher.network.session.players[0].character_id == 5 and watcher.network.session.players[1].character_id == 6): return "Animated picks did not reach the audience."
	for client in clients:
		if client.selection.cards.size() != 6: return "Six roster cards were not available."
		for index in 2:
			var view = client.selection._previews[index]
			if view.character_id != 5 + index or view.animation_set == null or view.visual != null or not view.body_sprite.visible: return "Selection did not display processed character art."
		for id in [5, 6]:
			if watcher.selection.cards[id].disabled != true: return "Audience could select a character."
	first.selection.ready_button.pressed.emit()
	second.selection.ready_button.pressed.emit()
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.IN_ARENA), 8500): return "Animated characters did not spawn after countdown."
	for client in clients:
		for owner in [1, 2]:
			var view = _view(client, owner)
			if view == null or view.character_id != owner + 4 or view.animation_set == null or view.visual != null or not view.body_sprite.visible: return "Arena spawned a placeholder instead of character art."
			if not is_equal_approx(view.radius, 12) or not is_equal_approx(view.body_bounds().size.y, 32): return "Character visual/host footprint calibration changed."
			if view.action_label.visible != (client != second): return "Debug action text ignored the dev toggle."
	_key(first, KEY_D, true)
	_key(second, KEY_A, true)
	await create_timer(0.10).timeout
	if _view(first, 1).animator.action != "walk" or _view(second, 2).animator.action != "walk": return "Local walking waited for host snapshots."
	if _view(watcher, 1).animator.action != "idle": return "Audience action text leaked live movement."
	if not await _wait_for(func(): return _view(watcher, 1).animator.action == "walk" and _view(watcher, 2).animator.action == "walk", 1500): return "Delayed movement did not animate for the audience."
	for client in clients:
		if _view(client, 1).animator.facing != "east" or _view(client, 2).animator.facing != "west": return "Movement facing disagreed across clients."
		if _view(client, 1).action_label.text != "walk": return "Label did not show the presented action."
	_key(first, KEY_D, false)
	_key(second, KEY_A, false)
	await create_timer(0.08).timeout
	if _view(first, 1).animator.action != "idle" or _view(watcher, 1).animator.action != "walk": return "Local stop/audience delay was not preserved."
	if not await _wait_for(func(): return _all_action("idle"), 1500): return "Stopped characters did not return to idle."
	_key(first, KEY_W, true)
	await create_timer(2.0).timeout
	if not await _wait_for(func(): return _all_action("idle"), 2000): return "Walking into blocked terrain kept the walk action active."
	_key(first, KEY_W, false)
	var late = _new_client(true)
	if not await _wait_for(func(): return late.game_arena.character_views.size() == 2, 2000): return "Late audience did not receive animated characters."
	if _view(late, 1).animation_set == null or _view(late, 1).animator.action != "idle": return "Late audience did not render idle art."
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return _all_phase(SessionSnapshot.Phase.LOBBY), 2000): return "Round reset did not clear character views."
	for client in clients:
		if not client.game_arena.character_views.is_empty(): return "Reset retained character/action labels."
	return ""


func _all_phase(phase: int) -> bool:
	for client in clients:
		if client.network.session == null or client.network.session.phase != phase: return false
	return true


func _view(client: Node, owner: int):
	for view in client.game_arena.character_views.values():
		if view.player_id == owner: return view
	return null


func _all_action(action: String) -> bool:
	for client in clients:
		for view in client.game_arena.character_views.values():
			if view.animator.action != action: return false
	return true


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	client.game_arena._unhandled_key_input(event)
