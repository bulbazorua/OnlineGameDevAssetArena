extends RefCounted

const Trace = preload("res://dev/ai/trace_reader.gd")
const Protocol = preload("res://network/protocol.gd")
const MAX_BYTES := 128 * 1024 * 1024
const MAX_LINE := 128 * 1024
const MAX_FRAMES := 250000
var header: Dictionary = {}
var entries: Array[Dictionary] = []
var warning := ""
var error := ""
var file_path := ""
var indexed_bytes := 0

# Read at most MAX_LINE bytes, including for malformed files without newlines.
static func line_at(file: FileAccess, limit: int) -> Dictionary:
	var start := file.get_position()
	var bytes := file.get_buffer(mini(MAX_LINE, limit - start))
	var newline := bytes.find(10)
	if newline < 0:
		return {"error": "Replay line exceeds 128 KiB." if bytes.size() == MAX_LINE else "Incomplete final line.", "partial": bytes.size() < MAX_LINE}
	file.seek(start + newline + 1)
	return {"text": bytes.slice(0, newline).get_string_from_utf8(), "error": "", "partial": false}

func scan(path: String, fingerprint: String, progress := Callable(), cancelled := Callable()) -> bool:
	header = {}
	entries = []
	warning = ""
	error = ""
	file_path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		error = "Cannot open recording, or file exceeds 128 MiB."
		return false
	indexed_bytes = file.get_length()
	var first := line_at(file, indexed_bytes)
	var value = Trace.parse_json(first.get("text", ""))
	if not value is Dictionary or value.get("kind") != "header" or value.get("schema_version") != 1 or value.get("protocol_version") != Protocol.HEADER[4] or value.get("simulation_hz") != 60:
		error = "Unsupported replay header/schema/protocol."
		return false
	if value.get("fingerprint") != fingerprint or not value.get("run_id") is String or value.run_id.is_empty() or value.run_id.length() > 256 or not Trace.integer(value.get("seed"), 0, 4294967295):
		error = "Replay content or run identity does not match."
		return false
	header = value
	var previous := 0
	var previous_tick := 0
	var ended := false
	while file.get_position() < indexed_bytes:
		if cancelled.is_valid() and cancelled.call(): error = "Cancelled"; return false
		var offset := file.get_position()
		var line := line_at(file, indexed_bytes)
		if line.partial: warning = "Incomplete recording: ignored unfinished final line."; break
		if not line.error.is_empty(): error = line.error; return false
		value = Trace.parse_json(line.text)
		if value is Dictionary and value.get("kind") == "end":
			if value.get("frames") != entries.size() or value.get("last_sequence") != previous or not Trace.integer(value.get("captured_frames"), previous) or not Trace.integer(value.get("dropped_messages")) or value.get("status") not in ["complete", "size_limit", "write_error", "encode_error"]:
				error = "Replay end record does not match its frames."
				return false
			if value.status != "complete" or value.captured_frames != previous or value.dropped_messages > 0:
				warning = "Recording status: %s; captured %d / last saved %d; dropped telemetry messages: %d." % [value.status, int(value.captured_frames), previous, int(value.dropped_messages)]
			ended = true
			if file.get_position() != indexed_bytes: error = "Unexpected data after replay end."; return false
			break
		var decoded := decode_frame(value)
		if not decoded.error.is_empty(): error = decoded.error; return false
		var sequence := int(value.sequence)
		if sequence <= previous or entries.size() >= MAX_FRAMES:
			error = "Replay sequence is out of order, or frame limit exceeded."
			return false
		var gap := sequence != previous + 1 or (not entries.is_empty() and ((int(value.tick) - previous_tick) & 0xffffffff) != 1)
		entries.append({"offset": offset, "sequence": sequence, "tick": int(value.tick), "gap_before": gap})
		previous = sequence
		previous_tick = int(value.tick)
		if progress.is_valid() and entries.size() % 64 == 0: progress.call(float(file.get_position()) / maxi(indexed_bytes, 1))
	if entries.is_empty(): error = "Recording has no complete frames."; return false
	if not ended and warning.is_empty(): warning = "Unfinished or live recording: playback ends at the data captured when opened."
	return true

func decode_frame(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("kind") != "frame" or not Trace.integer(value.get("sequence"), 1) or not Trace.integer(value.get("tick"), 0, 4294967295):
		return {"error": "Malformed replay frame."}
	var hex = value.get("packet_hex")
	if not hex is String or hex.length() not in [64, 276]: return {"error": "Invalid replay world packet length."}
	for character in hex:
		if character not in "0123456789abcdef": return {"error": "Invalid replay packet encoding."}
	var message = Protocol.decode(hex.hex_decode(), 0)
	if not message.error_title.is_empty() or message.kind != Protocol.MessageKind.SESSION_STATE or message.session.server_tick != int(value.tick):
		return {"error": "Replay world packet/tick is invalid."}
	if not value.get("ai") is Array or value.ai.size() > 2: return {"error": "Invalid replay AI count."}
	var owners := {}
	for record in value.ai:
		if not record is Dictionary or not Trace.integer(record.get("owner_id"), 1, 2): return {"error": "Invalid replay AI owner."}
		var owner := int(record.owner_id)
		var problem := Trace.validate_record(record, header.run_id, header.fingerprint, owner)
		if not problem.is_empty(): return {"error": problem}
		if owners.has(owner) or record.input.tick != value.tick or record.input.round_id != message.session.round_id or record.map_id != message.session.map_id:
			return {"error": "AI trace does not belong to this replay frame."}
		var subjects: Array = message.session.characters.filter(func(subject): return subject.owner_id == owner)
		if subjects.size() != 1 or subjects[0].entity_id != int(record.input.entity_id) or subjects[0].definition_id != int(record.definition_id):
			return {"error": "AI trace entity does not match the recorded world."}
		owners[owner] = true
	return {"error": "", "snapshot": message.session, "frame": value}

func read_frame(index: int) -> Dictionary:
	if index < 0 or index >= entries.size(): return {"error": "Replay frame index is out of range."}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null or file.get_length() < indexed_bytes: return {"error": "Recording was removed or truncated after indexing."}
	file.seek(int(entries[index].offset))
	var line := line_at(file, indexed_bytes)
	if not line.error.is_empty(): return {"error": line.error}
	var value = Trace.parse_json(line.text)
	if not value is Dictionary or value.get("sequence") != entries[index].sequence or value.get("tick") != entries[index].tick: return {"error": "Recording changed after indexing."}
	return decode_frame(value)
