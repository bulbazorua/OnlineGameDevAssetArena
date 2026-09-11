extends RefCounted

const Reader = preload("res://dev/ai/trace_reader.gd")
const Contract = preload("res://dev/search/search_contract.gd")
const MAX_BYTES := 32 * 1024
var records: Array[Dictionary] = []
var world: Dictionary = {}
var error := "Waiting for search data"
var last_published := -1
var updated_ms := 0


func read_snapshot(path: String, run_id: String, fingerprint: String) -> void:
	error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		error = "Search needs development telemetry (AI_DEBUG=1)"
		return
	var value = Reader.parse_json(file.get_as_text())
	if not value is Dictionary or value.get("schema_version") != 2 or value.get("run_id") != run_id or value.get("fingerprint") != fingerprint:
		error = "Search feed identity mismatch"
		return
	var lifecycle = value.get("world")
	if not lifecycle is Dictionary or not lifecycle.get("active") is bool or not Reader.integer(lifecycle.get("round_id")) or not Reader.integer(lifecycle.get("map_id")) or not lifecycle.get("entities") is Array or lifecycle.entities.size() != 2:
		error = "Invalid search lifecycle"
		return
	if not Reader.integer(value.get("published_us")) or not value.get("records") is Array or value.records.size() > 2:
		error = "Invalid search snapshot"
		return
	var next: Array[Dictionary] = []
	var owners := {}
	for record in value.records:
		if not record is Dictionary or not Reader.integer(record.get("owner_id"), 1, 2) or not Reader.integer(record.get("tick"), 0, 4294967295):
			error = "Invalid search record"
			return
		var owner := int(record.owner_id)
		if not lifecycle.active or owners.has(owner) or record.get("entity_id") != lifecycle.entities[owner - 1] or record.get("round_id") != lifecycle.round_id or record.get("map_id") != lifecycle.map_id:
			error = "Search record belongs to another creature or round"
			return
		if not Contract.valid(record.get("search")) or not Reader.intent(record.get("intent"), 3) or not Reader.action_result(record.get("result"), 3) or not Reader.vector(record.get("position_after")):
			error = "Invalid search belief or action"
			return
		owners[owner] = true
		next.append(record)
	if int(value.published_us) < last_published:
		error = "Search feed moved backward"
		return
	if int(value.published_us) != last_published:
		updated_ms = Time.get_ticks_msec()
		last_published = int(value.published_us)
	records = next
	world = lifecycle


func stale() -> bool:
	return not error.is_empty() or updated_ms == 0 or Time.get_ticks_msec() - updated_ms > 750
