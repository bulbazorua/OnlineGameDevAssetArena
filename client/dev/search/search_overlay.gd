extends Node2D

const Feed = preload("res://dev/search/search_feed.gd")
const Contract = preload("res://dev/search/search_contract.gd")
const COLORS := [Color("58a6ff"), Color("ffac62")]
var enabled := false
var feed := Feed.new()
var readings: Dictionary = {}
var status := "Search debug off [F6]"
var _arena: Node2D
var _path := ""
var _run_id := ""
var _elapsed := 0.0


func configure(arena: Node2D) -> void:
	_arena = arena
	name = "SearchOverlay"
	z_index = 91
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-ai-dir="): _path = argument.trim_prefix("--dev-ai-dir=").path_join("search.json")
		elif argument.begins_with("--dev-ai-run="): _run_id = argument.trim_prefix("--dev-ai-run=")
	arena.add_child(self)
	visible = false


func set_enabled(value: bool) -> void:
	enabled = value and OS.is_debug_build() and "--dev" in OS.get_cmdline_user_args()
	_process(0)


func _process(delta: float) -> void:
	visible = false
	if not enabled:
		status = "Search debug off [F6]"
		return
	if not _arena.visible or _arena.snapshot == null or _arena.network == null or _arena.network.session == null:
		readings.clear()
		status = "Search: waiting for arena"
		return
	if _arena.network.player_id == 0:
		readings.clear()
		status = "Search: unavailable on audience timeline"
		return
	if not _path.is_absolute_path() or _run_id.is_empty():
		status = "Search: needs AI_DEBUG=1"
		return
	_discard_unmatched_readings()
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0
		feed.read_snapshot(_path, _run_id, _arena.content.fingerprint.hex_encode())
		_refresh()
	var stale: bool = feed.stale() or Time.get_ticks_msec() - _arena._last_world_ms > _arena.STALE_WORLD_MS
	for record in readings.values():
		if ((_arena.snapshot.server_tick - int(record.tick)) & 0xffffffff) > 45: stale = true
	status = "Search: STALE" if stale else "Search: live private beliefs"
	if not feed.error.is_empty(): status = feed.error
	elif readings.is_empty(): status = "Search: waiting for matching search controller"
	visible = not readings.is_empty()
	modulate.a = 0.35 if stale else 1.0
	if visible: queue_redraw()


func _discard_unmatched_readings() -> void:
	var world = _arena.network.session
	for owner in readings.keys():
		var current: Dictionary = readings[owner]
		if int(current.round_id) != world.round_id or int(current.map_id) != world.map_id or not world.characters.any(func(character): return character.entity_id == int(current.entity_id) and character.owner_id == owner):
			readings.erase(owner)


func _refresh() -> void:
	var world = _arena.network.session
	for record in feed.records:
		if int(record.round_id) != world.round_id or int(record.map_id) != world.map_id: continue
		if ((world.server_tick - int(record.tick)) & 0xffffffff) > 0x7fffffff: continue
		for character in world.characters:
			if int(record.entity_id) == character.entity_id and int(record.owner_id) == character.owner_id:
				readings[character.owner_id] = record


func _draw() -> void:
	for owner: int in readings:
		var record: Dictionary = readings[owner]
		var search: Dictionary = record.search
		var color: Color = COLORS[owner - 1]
		var origin := Vector2(search.position[0], search.position[1])
		for index in int(search.visit_count):
			var visit: Dictionary = search.visits[index]
			var point := Vector2(visit.position[0], visit.position[1])
			var age := float((int(record.tick) - int(visit.visited_tick)) & 0xffffffff)
			var strength := maxf(0, 1 - age / search.profile.history_ticks)
			draw_arc(point, 8, 0, TAU, 16, Color(color, strength * 0.5), 1.2)
		if search.center_valid and search.state == "Intensive_Search":
			var center := Vector2(search.center[0], search.center[1])
			draw_arc(center, maxf(1, search.radius), 0, TAU, 64, Color(color, 0.35), 1.2)
		if int(search.target) > 0:
			var target := Vector2(search.target_position[0], search.target_position[1])
			draw_line(origin, target, Color(color, 0.55), 1)
			draw_line(target - Vector2(6, 6), target + Vector2(6, 6), color, 1.5)
			draw_line(target + Vector2(-6, 6), target + Vector2(6, -6), color, 1.5)
		for index in 8:
			var direction := Vector2.UP.rotated(index * PI / 4)
			var chosen: bool = Contract.FACINGS[index] == search.heading
			var tint := Color("ff687a") if search.blocked[index] else Color(color, 0.8 if chosen else 0.15)
			draw_line(origin, origin + direction * (56 if chosen else 24), tint, 2 if chosen else 1)
		draw_string(ThemeDB.fallback_font, origin + Vector2(12, 26), "P%d · %s" % [owner, search.state.replace("_", " ")], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
