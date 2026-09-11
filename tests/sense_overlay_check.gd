extends "./collision_overlay_check.gd"

const SenseFeed = preload("res://dev/sense_feed.gd")
const ConeGeometry = preload("res://dev/vision_cone_geometry.gd")
var trace_directory := ""


func _host_arguments() -> PackedStringArray:
	trace_directory = ProjectSettings.globalize_path("res://../build/verification/sense-overlay-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(trace_directory)
	var arguments := super._host_arguments()
	arguments.append_array(["--dev-ai-dir=" + trace_directory, "--dev-ai-run=sense-overlay-check"])
	return arguments


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 did not connect."
	var second = _new_client()
	var audience = _new_client(true)
	if not await _wait_for(func(): return clients.all(func(client): return _entered(client))): return "Arena did not start."
	for client in clients:
		var overlay = client.get_node("DebugOverlay").senses
		overlay._path = trace_directory.path_join("senses.json")
		overlay._run_id = "sense-overlay-check"
	var ui = first.get_node("DebugOverlay")
	var senses = ui.senses
	if not await _wait_for(func(): return senses.readings.size() == 2 and senses.visible): return "Default vision cones did not appear. " + senses.status
	if not audience.get_node("DebugOverlay").senses.readings.is_empty(): return "Audience borrowed live private senses."
	var error := _check_delivered_geometry(first)
	if not error.is_empty(): return error
	error = _check_invalid_snapshots(senses.feed, first.content.fingerprint.hex_encode())
	if not error.is_empty(): return error
	_push_key(first, KEY_F3)
	if ui.colliders.enabled or not senses.visible: return "Physical collider toggle hid the senses."
	await _capture_senses(first, "vision-only")
	_push_key(first, KEY_F5)
	if senses.visible or not second.get_node("DebugOverlay").senses.enabled: return "Vision toggle affected another window or failed to hide."
	_push_key(first, KEY_F5)
	if not senses.visible or ui.colliders.enabled: return "Vision toggle changed physical colliders."
	_push_key(first, KEY_F4)
	await process_frame
	ui.get_node("%Filters").ensure_control_visible(ui.sense_buttons.focus)
	await process_frame
	_click(first, ui.sense_buttons.focus.get_global_rect().get_center())
	if senses.categories.focus or not senses.categories.periphery: return "Focused vision checkbox did not act independently."
	if first.get_viewport().gui_get_focus_owner() != null: return "Sense filter stole movement focus."
	await _capture_senses(first, "peripheral-only")
	ui.sense_buttons.focus.button_pressed = true
	ui.sense_buttons.periphery.button_pressed = false
	ui.sense_buttons.p2.button_pressed = false
	await _capture_senses(first, "p1-focus-only")
	ui.sense_buttons.periphery.button_pressed = true
	ui.sense_buttons.p2.button_pressed = true
	ui.get_node("%AllColliders").pressed.emit()
	if not senses.enabled or senses.categories.values().count(true) != 4: return "All colliders changed sense filters."
	ui.get_node("%NoColliders").pressed.emit()
	if not senses.visible: return "No colliders hid vision."
	first.get_viewport().size = Vector2i(800, 760)
	await process_frame
	await process_frame
	if not Rect2(0, 0, 800, 640).encloses(ui.get_node("%Panel").get_global_rect()): return "Sense filters cover the bottom HUD."
	await _capture_senses(first, "senses-filters")
	_push_key(first, KEY_F4)
	_key(first, KEY_D, true)
	await create_timer(0.55).timeout
	_key(first, KEY_D, false)
	error = _check_delivered_geometry(first)
	if not error.is_empty(): return error
	var frozen := trace_directory.path_join("frozen.json")
	DirAccess.copy_absolute(trace_directory.path_join("senses.json"), frozen)
	senses._path = frozen
	await create_timer(1.05).timeout
	if not senses.feed.is_stale() or not "STALE" in senses.status or senses.modulate.a >= 1: return "Stopped sense feed still looks live."
	await _capture_senses(first, "stale-senses")
	senses._path = trace_directory.path_join("senses.json")
	if not await _wait_for(func(): return not senses.feed.is_stale() and senses.modulate.a == 1): return "Sense feed did not recover."
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.LOBBY): return "Lobby reset failed."
	await process_frame
	if senses.visible or not senses.readings.is_empty(): return "Lobby retained a creature's cone."
	print("Sense reader: ", senses.feed.read_us, " µs; snapshot: ", FileAccess.get_file_as_bytes(trace_directory.path_join("senses.json")).size(), " bytes")
	return ""


func _check_delivered_geometry(client: Node) -> String:
	var senses = client.get_node("DebugOverlay").senses
	for owner: int in senses.readings:
		var record: Dictionary = senses.readings[owner]
		var sample: Dictionary = record.vision
		var shape: Dictionary = senses._geometry[owner]
		if shape.center != Vector2(sample.pose.position[0], sample.pose.position[1]): return "Cone follows a different pose from the delivered sample."
		if int(sample.delivered_tick) > client.game_arena.snapshot.server_tick: return "Cone shows future sensory evidence."
		for field in ["focus", "left", "right"]:
			for point: Vector2 in shape[field]:
				if point.length() > float(sample.profile.range) + 0.01: return "Cone exceeds the sampled range."
		sample = sample.duplicate(true)
		sample.profile.focused_fov_degrees = 61.0
		for facing in 8:
			sample.pose.facing = SenseFeed.Reader.FACINGS[facing]
			var fan: Array = []
			var axis := facing * PI / 4.0 - PI / 2.0
			for index in 65:
				var angle := axis + deg_to_rad(-80.0 + index * 2.5)
				var point: Vector2 = shape.center + Vector2.from_angle(angle) * 100.0
				fan.append([point.x, point.y])
			var rotated := ConeGeometry.build(sample, fan)
			if rotated.focus.is_empty() or rotated.left.is_empty() or rotated.right.is_empty(): return "A facing lost a vision field."
			if absf(angle_difference(rotated.focus[1].angle(), axis - deg_to_rad(30.5))) > 0.00001: return "Focused cone has the wrong angle."
			if rotated.focus[1].length() > 100.01 or rotated.focus[1].length() < 99.9: return "Focused boundary left the host fan."
		var blocked_fan: Array = []
		for index in 65: blocked_fan.append([shape.center.x, shape.center.y])
		var blocked := ConeGeometry.build(sample, blocked_fan)
		if not blocked.focus.is_empty() or not blocked.left.is_empty() or not blocked.right.is_empty(): return "Opaque origin still has a visible cone."
	return ""


func _check_invalid_snapshots(feed: RefCounted, fingerprint: String) -> String:
	var value = JSON.parse_string(FileAccess.get_file_as_string(trace_directory.path_join("senses.json")))
	if not SenseFeed.validate(value, "sense-overlay-check", fingerprint).is_empty(): return "Host sense snapshot did not validate."
	for field in ["host_audit", "before", "nodes"]:
		var changed: Dictionary = value.duplicate(true)
		changed.records[0][field] = {}
		if SenseFeed.validate(changed, "sense-overlay-check", fingerprint).is_empty(): return "Sense feed accepted privileged/history fields."
	var duplicate: Dictionary = value.duplicate(true)
	duplicate.records[1] = duplicate.records[0]
	if SenseFeed.validate(duplicate, "sense-overlay-check", fingerprint).is_empty(): return "Sense feed accepted duplicate observers."
	if SenseFeed.validate(value, "another-run", fingerprint).is_empty(): return "Sense feed accepted another run."
	var mixed: Dictionary = value.duplicate(true)
	mixed.records[0].vision.observer += 1
	if SenseFeed.validate(mixed, "sense-overlay-check", fingerprint).is_empty(): return "Sense feed accepted another creature's eye."
	if feed.records.size() != 2: return "Reader did not retain the two latest readings."
	return ""


func _capture_senses(client: Node, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	client.get_viewport().get_texture().get_image().save_png(trace_directory.path_join(label + ".png"))
