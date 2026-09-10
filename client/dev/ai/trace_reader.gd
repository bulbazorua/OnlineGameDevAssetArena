extends RefCounted

const MAX_SNAPSHOT_BYTES := 4 * 1024 * 1024
const MAX_JOURNAL_BYTES := 9 * 1024 * 1024
const HISTORY_LIMIT := 2048
const MAX_NODES := 48
const STAGES := ["Input", "State", "Controller", "Branch", "Decision", "Outcome"]
const STATUSES := ["Info", "Passed", "Rejected", "Skipped", "Selected", "Resolved", "Unavailable"]
var records: Array[Dictionary] = []
var last_sequence := 0
var missed_live_records := 0
var error := ""
var warning := ""
var snapshot: Dictionary = {}


static func parse_json(text: String) -> Variant:
	# Invalid/partial external data is a reader status, not an engine error spam.
	var parser := JSON.new()
	if parser.parse(text) != OK: return null
	return parser.data


static func integer(value: Variant, minimum: int = 0, maximum: int = 9007199254740991) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(v: Variant) -> bool:
		return (v is int or v is float) and is_finite(float(v)) and absf(float(v)) <= 1.0e9)


static func intent(value: Variant) -> bool:
	return value is Dictionary and value.get("kind") in ["Hold", "Move"] and vector(value.get("direction"))


static func action_result(value: Variant) -> bool:
	return value is Dictionary and value.get("kind") in ["Held", "Moved", "Terrain_Blocked", "Anchor_Limit", "Locked", "Invalid_Request", "Preparing"] and vector(value.get("displacement"))


static func validate_record(record: Variant, run_id: String, fingerprint: String, owner: int) -> String:
	if not record is Dictionary or record.get("schema_version") != 1:
		return "Unsupported trace schema."
	if record.get("run_id") != run_id or record.get("fingerprint") != fingerprint or record.get("owner_id") != owner:
		return "Trace belongs to another run, content version or creature."
	for key in ["sequence", "worker_id", "definition_id", "map_id"]:
		if not integer(record.get(key), 1): return "Invalid trace %s." % key
	if not integer(record.get("facing"), 0, 7): return "Invalid facing."
	for key in ["queued_us", "started_us", "finished_us"]:
		if not integer(record.get(key)): return "Invalid worker timing."
	if record.queued_us > record.started_us or record.started_us > record.finished_us:
		return "Worker timing is out of order."
	var input = record.get("input")
	if not input is Dictionary or not vector(input.get("position")) or not vector(input.get("anchor")) or not input.get("can_move") is bool:
		return "Invalid private input."
	for key in ["entity_id", "round_id", "tick"]:
		if not integer(input.get(key), 0, 4294967295): return "Invalid input identity/tick."
	if input.entity_id == 0: return "Missing runtime entity."
	for key in ["before", "after"]:
		var agent = record.get(key)
		if not agent is Dictionary or agent.get("entity_id") != input.entity_id or agent.get("round_id") != input.round_id:
			return "Agent state does not match the observer."
		if not agent.get("wander") is Dictionary or not agent.get("random") is Dictionary or not integer(agent.random.get("value"), 0, 4294967295):
			return "Invalid agent state."
		if not intent(agent.get("intent")):
			return "Invalid intent."
		var last = agent.get("last")
		if not last is Dictionary or not intent(last.get("requested")) or not action_result(last.get("result")) or not integer(last.get("tick"), 0, 4294967295) or not last.get("reason") is String:
			return "Invalid previous decision record."
		if not agent.wander.get("started") is bool or agent.wander.get("phase") not in ["Idle", "Walk"]:
			return "Invalid wander phase."
		for field in ["deadline", "next_decision"]:
			if not integer(agent.wander.get(field), 0, 4294967295): return "Invalid private deadline."
	var result = record.get("result")
	if not action_result(result):
		return "Invalid confirmed result."
	if not vector(record.get("position_after")) or not record.get("decision_reason") is String:
		return "Missing outcome or decision reason."
	var config = record.get("config")
	if not config is Dictionary or not config.get("roam_radius") is float and not config.get("roam_radius") is int:
		return "Missing wander configuration."
	if not is_finite(float(config.roam_radius)) or config.roam_radius <= 0 or config.roam_radius > 4096:
		return "Invalid roam radius."
	var nodes = record.get("nodes")
	if not nodes is Array or nodes.is_empty() or nodes.size() > MAX_NODES or not integer(record.get("truncated_nodes")):
		return "Invalid branch count."
	var previous_time := 0
	for index in nodes.size():
		var node = nodes[index]
		if not node is Dictionary or node.get("id") != index + 1 or not integer(node.get("parent"), 0, index):
			return "Broken branch ancestry."
		if index > 0 and node.parent == 0: return "Multiple decision roots."
		if node.get("stage") not in STAGES or node.get("status") not in STATUSES:
			return "Unknown trace stage/status."
		for key in ["label", "metric"]:
			if not node.get(key) is String or node[key].length() > 512: return "Invalid branch label."
		for key in ["value", "threshold"]:
			if not (node.get(key) is int or node.get(key) is float) or not is_finite(float(node[key])):
				return "Invalid branch operand."
		if not vector(node.get("direction")) or not integer(node.get("thread_id"), 1) or not integer(node.get("elapsed_us"), previous_time):
			return "Invalid branch vector/timing."
		previous_time = int(node.elapsed_us)
	return ""


func read_snapshot(path: String, run_id: String, fingerprint: String, owner: int) -> bool:
	error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "Waiting for the host trace stream."
		return false
	if file.get_length() > MAX_SNAPSHOT_BYTES:
		error = "Snapshot exceeds the debugger size limit."
		return false
	var value = parse_json(file.get_as_text())
	if not value is Dictionary or value.get("schema_version") != 1 or value.get("run_id") != run_id or value.get("fingerprint") != fingerprint or value.get("owner_id") != owner:
		error = "Snapshot schema, run, content or creature mismatch."
		return false
	if not value.get("records") is Array or value.records.size() > 128:
		error = "Invalid snapshot history."
		return false
	for key in ["published_us", "dropped_records", "overwritten_records", "publish_us", "log_limit_bytes", "retained_segments"]:
		if not integer(value.get(key)):
			error = "Invalid snapshot counter."
			return false
	if not value.get("writer_error") is String:
		error = "Invalid writer status."
		return false
	var previous := 0
	for record in value.records:
		error = validate_record(record, run_id, fingerprint, owner)
		if not error.is_empty(): return false
		if int(record.sequence) <= previous:
			error = "Snapshot decisions are out of order."
			return false
		previous = int(record.sequence)
	snapshot = value
	var changed := false
	for record: Dictionary in value.records:
		var sequence := int(record.sequence)
		if sequence <= last_sequence: continue
		if last_sequence > 0: missed_live_records += maxi(0, sequence - last_sequence - 1)
		records.append(record)
		last_sequence = sequence
		changed = true
	while records.size() > HISTORY_LIMIT: records.pop_front()
	return changed


func load_journal(path: String, fingerprint: String, owner: int) -> bool:
	error = ""
	warning = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_JOURNAL_BYTES:
		error = "Cannot open journal, or file exceeds 9 MiB."
		return false
	var data := file.get_as_text()
	var lines := data.split("\n", false)
	var loaded: Array[Dictionary] = []
	var run_id := ""
	var previous := 0
	for index in lines.size():
		var record = parse_json(lines[index])
		if record == null and index == lines.size() - 1 and not data.ends_with("\n"):
			warning = "Ignored incomplete final journal line."
			break
		if record is Dictionary and run_id.is_empty(): run_id = str(record.get("run_id", ""))
		error = validate_record(record, run_id, fingerprint, owner)
		if not error.is_empty(): return false
		if int(record.sequence) <= previous:
			error = "Journal decisions are out of order."
			return false
		previous = int(record.sequence)
		loaded.append(record)
		if loaded.size() > HISTORY_LIMIT: loaded.pop_front()
	if loaded.is_empty():
		error = "Journal has no complete decisions."
		return false
	records = loaded
	last_sequence = previous
	return true
