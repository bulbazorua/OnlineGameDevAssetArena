extends Node2D

const Feed = preload("res://dev/sense_feed.gd")
const Geometry = preload("res://dev/vision_cone_geometry.gd")
const FOCUS := Color("62d9ff")
const PERIPHERAL := Color("ffb454")
const CONE_OPACITY := 0.2
const CATEGORIES := [
	{"key": "focus", "label": "Focused vision", "color": FOCUS},
	{"key": "periphery", "label": "Peripheral vision", "color": PERIPHERAL},
	{"key": "p1", "label": "Character P1", "color": Color("58a6ff")},
	{"key": "p2", "label": "Character P2", "color": Color("ffac62")},
]
var enabled := true
var categories := {"focus": true, "periphery": true, "p1": true, "p2": true}
var feed := Feed.new()
var readings: Dictionary = {}
var status := "Senses: waiting for arena"
var _geometry: Dictionary = {}
var _arena: Node2D
var _path := ""
var _run_id := ""
var _elapsed := 0.0
var _stale := true


func configure(arena: Node2D) -> void:
	_arena = arena
	name = "SenseOverlay"
	z_index = 90
	process_priority = 100
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-ai-dir="): _path = argument.trim_prefix("--dev-ai-dir=").path_join("senses.json")
		elif argument.begins_with("--dev-ai-run="): _run_id = argument.trim_prefix("--dev-ai-run=")
	arena.add_child(self)
	visible = false


func set_enabled(value: bool) -> void:
	enabled = value
	_process(0)


func set_category(key: String, value: bool) -> void:
	if categories.has(key): categories[key] = value
	_process(0)


func _process(delta: float) -> void:
	visible = false
	if not _arena.visible or _arena.snapshot == null:
		readings.clear()
		_geometry.clear()
		status = "Senses: waiting for arena"
		return
	if _arena.network.player_id == 0:
		status = "Senses: unavailable in audience view"
		return
	if not _path.is_absolute_path() or _run_id.is_empty():
		status = "Senses: needs AI_DEBUG=1"
		return
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0
		feed.read_snapshot(_path, _run_id, _arena.content.fingerprint.hex_encode())
	_refresh_readings()
	_stale = feed.is_stale() or not feed.error.is_empty() or Time.get_ticks_msec() - _arena._last_world_ms > _arena.STALE_WORLD_MS
	status = "Senses: STALE" if _stale else "Vision: cyan focus / amber periphery"
	if readings.is_empty(): status = "Senses: " + (feed.error if not feed.error.is_empty() else "waiting for a matching sample")
	if not enabled: status = "Senses hidden [F5]"
	visible = enabled and not readings.is_empty() and (categories.focus or categories.periphery) and (categories.p1 or categories.p2)
	modulate.a = 0.4 if _stale else 1.0
	if visible: queue_redraw()


func _refresh_readings() -> void:
	var state = _arena.snapshot
	for owner: int in readings.keys():
		if not _matches_world(readings[owner]):
			readings.erase(owner)
			_geometry.erase(owner)
	for record: Dictionary in feed.records:
		if not _matches_world(record): continue
		var sample: Dictionary = record.vision
		if ((int(state.server_tick) - int(sample.delivered_tick)) & 0xffffffff) > 0x7fffffff: continue
		var owner := int(record.owner_id)
		if sample.status != "Sampled" or record.sight_fan.is_empty():
			readings.erase(owner)
			_geometry.erase(owner)
			continue
		if not readings.has(owner) or readings[owner].vision.sample_id != sample.sample_id:
			_geometry[owner] = Geometry.build(sample, record.sight_fan)
		readings[owner] = record


func _matches_world(record: Dictionary) -> bool:
	var state = _arena.snapshot
	if int(record.round_id) != state.round_id or int(record.map_id) != state.map_id: return false
	for character in state.characters:
		if character.owner_id == int(record.owner_id):
			return character.entity_id == int(record.entity_id) and character.definition_id == int(record.definition_id)
	return false


func diagnostics() -> Dictionary:
	var samples: Array[Dictionary] = []
	for owner: int in readings:
		var record: Dictionary = readings[owner]
		samples.append({"owner": owner, "entity": int(record.entity_id), "round": int(record.round_id),
			"sample_id": int(record.vision.sample_id), "sample_tick": int(record.vision.sample_tick),
			"position": record.vision.pose.position, "facing": record.vision.pose.facing})
	return {"enabled": enabled, "visible": visible, "status": status, "stale": _stale,
		"read_us": feed.read_us, "error": feed.error, "samples": samples}


func _draw() -> void:
	for owner: int in readings:
		if not categories["p%d" % owner]: continue
		var shape: Dictionary = _geometry[owner]
		draw_set_transform(shape.center)
		if categories.periphery:
			_draw_field(shape.left, PERIPHERAL)
			_draw_field(shape.right, PERIPHERAL)
		if categories.focus: _draw_field(shape.focus, FOCUS)
		var sample: Dictionary = readings[owner].vision
		var age := (int(_arena.snapshot.server_tick) - int(sample.sample_tick)) & 0xffffffff
		var label := "P%d vision · %d ms old" % [owner, roundi(age * 1000.0 / 60.0)]
		if _stale: label += " · STALE"
		draw_string(ThemeDB.fallback_font, Vector2(11, -21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
		draw_string(ThemeDB.fallback_font, Vector2(10, -22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	draw_set_transform(Vector2.ZERO)


func _draw_field(polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3: return
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, Color(color, CONE_OPACITY), 1.2, true)
