extends RefCounted

const Reader = preload("res://dev/ai/trace_reader.gd")
const MAX_BYTES := 32 * 1024
const STALE_MS := 750
const RECORD_KEYS := ["owner_id", "entity_id", "round_id", "tick", "definition_id", "map_id", "delivered_us", "vision", "sight_fan", "scent_delivered_us", "olfaction", "own_emitter"]
var records: Array[Dictionary] = []
var world: Dictionary = {}
var origin_unix_us := 0
var error := ""
var published_us := -1
var received_ms := -1
var read_us := 0


func read_snapshot(path: String, run_id: String, fingerprint: String) -> void:
	var started := Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "Waiting for host senses"
		return
	if file.get_length() > MAX_BYTES:
		error = "Sense snapshot exceeds its size limit"
		return
	var value = Reader.parse_json(file.get_as_text())
	error = validate(value, run_id, fingerprint)
	read_us = Time.get_ticks_usec() - started
	if not error.is_empty() or int(value.published_us) <= published_us: return
	published_us = int(value.published_us)
	received_ms = Time.get_ticks_msec()
	records.assign(value.records)
	world = value.world
	origin_unix_us = int(value.origin_unix_us)


func record_for_owner(owner: int) -> Dictionary:
	for record: Dictionary in records:
		if int(record.owner_id) == owner: return record
	return {}


func is_stale() -> bool:
	return received_ms < 0 or Time.get_ticks_msec() - received_ms > STALE_MS


static func validate(value: Variant, run_id: String, fingerprint: String) -> String:
	if not value is Dictionary or value.get("schema_version") != 3 or value.size() != 7:
		return "Unsupported sense snapshot"
	if value.get("run_id") != run_id or value.get("fingerprint") != fingerprint:
		return "Senses belong to another run or content version"
	if not Reader.integer(value.get("published_us"), 0, 9223372036854775807):
		return "Invalid sense publication time"
	if not Reader.integer(value.get("origin_unix_us"), 1, 9223372036854775807):
		return "Invalid sense clock origin"
	var lifecycle: Variant = value.get("world")
	if not lifecycle is Dictionary or lifecycle.size() != 4 or not lifecycle.get("active") is bool:
		return "Invalid sense lifecycle"
	if not Reader.integer(lifecycle.get("round_id"), 0, 4294967295) or not Reader.integer(lifecycle.get("map_id"), 0, 65535):
		return "Invalid sense round"
	if not lifecycle.get("entities") is Array or lifecycle.entities.size() != 2:
		return "Invalid sense bindings"
	for entity: Variant in lifecycle.entities:
		if not Reader.integer(entity, 0, 4294967295): return "Invalid sense entity"
	if not value.get("records") is Array or value.records.size() > 2:
		return "Invalid sense record count"
	if not lifecycle.active and not value.records.is_empty(): return "Readings outside an active round"
	var owners := {}
	for record: Variant in value.records:
		var problem := _validate_record(record)
		if not problem.is_empty(): return problem
		if record.round_id != lifecycle.round_id or record.map_id != lifecycle.map_id or record.entity_id != lifecycle.entities[int(record.owner_id) - 1]:
			return "Readings belong to an old creature or round"
		if not Reader.integer(record.delivered_us, -1, int(value.published_us)) or not Reader.integer(record.scent_delivered_us, -1, int(value.published_us)):
			return "Invalid sense delivery time"
		if owners.has(int(record.owner_id)): return "Duplicate sense observer"
		owners[int(record.owner_id)] = true
	return ""


static func _validate_record(record: Variant) -> String:
	if not record is Dictionary or record.size() != RECORD_KEYS.size(): return "Invalid sense record fields"
	for key in RECORD_KEYS:
		if not record.has(key): return "Missing sense record field"
	if not Reader.integer(record.owner_id, 1, 2): return "Invalid sense owner"
	for key in ["entity_id", "round_id", "tick"]:
		if not Reader.integer(record[key], 0, 4294967295): return "Invalid sense identity"
	for key in ["definition_id", "map_id"]:
		if not Reader.integer(record[key], 1, 65535): return "Invalid sense definition"
	var problem := Reader.validate_vision_sample(record.vision)
	if not problem.is_empty(): return problem
	var sample: Dictionary = record.vision
	if sample.status == "Sampled":
		if sample.observer != record.entity_id or sample.round_id != record.round_id:
			return "Vision belongs to another creature"
		if ((int(record.tick) - int(sample.delivered_tick)) & 0xffffffff) > 0x7fffffff:
			return "Vision was delivered after this record"
		if ((int(sample.delivered_tick) - int(sample.sample_tick)) & 0xffffffff) > 0x7fffffff:
			return "Vision was delivered before it was sampled"
		var profile: Dictionary = sample.profile
		if not profile.enabled or profile.range <= 0 or profile.range > 2048 or profile.focused_fov_degrees < 45 or profile.focused_fov_degrees >= profile.overall_fov_degrees or profile.overall_fov_degrees > 180:
			return "Invalid active vision geometry"
	if not record.sight_fan is Array or record.sight_fan.size() not in [0, 65]: return "Invalid vision outline"
	if sample.status != "Sampled" and not record.sight_fan.is_empty(): return "Outline without a vision sample"
	for point: Variant in record.sight_fan:
		if not Reader.vector(point): return "Invalid vision outline point"
	problem = Reader.validate_scent_sample(record.olfaction)
	if not problem.is_empty(): return problem
	var nose: Dictionary = record.olfaction
	if nose.status == "Sampled":
		if nose.observer != record.entity_id or nose.round_id != record.round_id: return "Scent belongs to another creature"
		if ((int(record.tick) - int(nose.delivered_tick)) & 0xffffffff) > 0x7fffffff: return "Scent was delivered after this record"
		if ((int(nose.delivered_tick) - int(nose.sample_tick)) & 0xffffffff) > 0x7fffffff: return "Scent was delivered before it was sampled"
	if not Reader.validate_emitter(record.own_emitter): return "Invalid own scent emitter"
	return ""
