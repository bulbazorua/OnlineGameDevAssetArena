extends RefCounted

# Bounded reader of the host's privileged scent field publication. It validates
# identity and shape, decodes the quantized layers, and never invents cells.
const Reader = preload("res://dev/ai/trace_reader.gd")
const MAX_BYTES := 96 * 1024
const STALE_MS := 750
const CLASSES := ["Human", "Orc"]
var field: Dictionary = {}
var world: Dictionary = {}
var levels: Array[PackedByteArray] = []
var ages: Array[PackedByteArray] = []
var error := ""
var published_us := -1
var received_ms := -1
var read_us := 0


func read_snapshot(path: String, run_id: String, fingerprint: String) -> void:
	var started := Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "Waiting for the host scent field"
		return
	if file.get_length() > MAX_BYTES:
		error = "Scent field exceeds its size limit"
		return
	var value = Reader.parse_json(file.get_as_text())
	error = validate(value, run_id, fingerprint)
	read_us = Time.get_ticks_usec() - started
	if not error.is_empty() or int(value.published_us) <= published_us: return
	published_us = int(value.published_us)
	received_ms = Time.get_ticks_msec()
	world = value.world
	field = value.field
	levels = []
	ages = []
	if field.valid:
		for index in CLASSES.size():
			levels.append(Marshalls.base64_to_raw(field.levels[index]))
			ages.append(Marshalls.base64_to_raw(field.ages[index]))


func is_stale() -> bool:
	return received_ms < 0 or Time.get_ticks_msec() - received_ms > STALE_MS


func level(class_index: int, cell: Vector2i) -> int:
	if not field.get("valid", false) or cell.x < 0 or cell.y < 0 or cell.x >= int(field.width) or cell.y >= int(field.height): return 0
	return levels[class_index][cell.y * int(field.width) + cell.x]


func age_seconds(class_index: int, cell: Vector2i) -> int:
	if not field.get("valid", false) or cell.x < 0 or cell.y < 0 or cell.x >= int(field.width) or cell.y >= int(field.height): return 0
	return ages[class_index][cell.y * int(field.width) + cell.x]


static func validate(value: Variant, run_id: String, fingerprint: String) -> String:
	if not value is Dictionary or value.get("schema_version") != 1 or value.size() != 6:
		return "Unsupported scent snapshot"
	if value.get("run_id") != run_id or value.get("fingerprint") != fingerprint:
		return "Scent field belongs to another run or content version"
	if not Reader.integer(value.get("published_us"), 0, 9223372036854775807): return "Invalid scent publication time"
	var lifecycle: Variant = value.get("world")
	if not lifecycle is Dictionary or lifecycle.size() != 4 or not lifecycle.get("active") is bool: return "Invalid scent lifecycle"
	var field: Variant = value.get("field")
	if not field is Dictionary or not field.get("valid") is bool or not Reader.integer(field.get("step_ticks"), 1, 60): return "Invalid scent field"
	if not field.get("classes") is Array or field.classes != CLASSES: return "Unknown scent classes"
	if not field.valid:
		if not field.get("levels") is Array or not field.levels.is_empty() or not field.get("ages") is Array or not field.ages.is_empty(): return "Layers without a valid field"
		return ""
	if not lifecycle.active: return "Scent field outside an active round"
	if not Reader.integer(field.get("round_id"), 0, 4294967295) or not Reader.integer(field.get("tick"), 0, 4294967295) or not Reader.integer(field.get("map_id"), 1, 65535): return "Invalid scent field identity"
	if field.round_id != lifecycle.round_id or field.map_id != lifecycle.map_id: return "Scent field belongs to another round"
	if not Reader.integer(field.get("width"), 1, 128) or not Reader.integer(field.get("height"), 1, 128) or not Reader.finite(field.get("tile_size")) or field.tile_size <= 0: return "Invalid scent field size"
	var cells := int(field.width) * int(field.height)
	for key in ["levels", "ages"]:
		if not field.get(key) is Array or field[key].size() != CLASSES.size(): return "Invalid scent layers"
		for encoded in field[key]:
			if not encoded is String or Marshalls.base64_to_raw(encoded).size() != cells: return "Scent layer does not cover the map"
	return ""
