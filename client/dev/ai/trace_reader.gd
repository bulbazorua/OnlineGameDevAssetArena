extends RefCounted

# Validated development input. Schema 1: historical wander trace; 2: eye sample, memory,
# attention, host audit; 3: private search; 4: nose sample, scent memory and evidence;
# 5: nose zone coverage and audit excluded cells. No schema is synthesized from another.
const MAX_SNAPSHOT_BYTES := 4 * 1024 * 1024
const MAX_JOURNAL_BYTES := 9 * 1024 * 1024
const HISTORY_LIMIT := 2048
const MAX_NODES := 48
const MAX_OBSERVATIONS := 3
const MAX_SCENT_READINGS := 2
const SCENT_ZONES := 16
const MAX_FAN := 65
const SearchContract = preload("res://dev/search/search_contract.gd")
const SCHEMAS := [1, 2, 3, 4, 5]
const LATEST_SCHEMA := 5
const STAGES := ["Input", "State", "Controller", "Branch", "Decision", "Outcome"]
const STATUSES := ["Info", "Passed", "Rejected", "Skipped", "Selected", "Resolved", "Unavailable"]
const SENSE_STATUSES := ["Unsupported", "Disabled", "Waiting_For_Summon", "Sampled"]
const REASONS_V2 := ["Locked", "Scan", "Orient", "Observe", "Reacquire"]
const ATTENTION_STATES := ["Scan", "Orient", "Observe", "Reacquire"]
const EVIDENCE_KINDS := ["None", "Focused", "Cue", "Focused_Memory", "Cue_Memory", "Scent", "Scent_Memory"]
const SCENT_CLASSES := ["Human", "Orc"]
const SCENT_STRENGTHS := ["None", "Weak", "Medium", "Strong"]
const SCENT_FRESHNESS := ["Unknown", "Old", "Recent", "Very_Recent"]
const SCENT_COVERAGE := ["Unsampled", "Partial", "Sampled"]
const SUBJECT_KINDS := ["Creature", "Trainer"]
const LOCOMOTIONS := ["Idle", "Walk"]
const BANDS := ["Near", "Far"]
const VERDICTS := ["Not_Evaluated", "Self", "Invalid", "Out_Of_Range", "Outside_Field", "Occluded", "Focused", "Peripheral"]
const RESULTS_V1 := ["Held", "Moved", "Terrain_Blocked", "Anchor_Limit", "Locked", "Invalid_Request", "Preparing"]
const RESULTS_V2 := ["Held", "Moved", "Terrain_Blocked", "Anchor_Limit", "Locked", "Invalid_Request", "Preparing", "Turned", "Turn_Pending"]
# Enum names as the host serializes them; index order is the wire facing value.
const FACINGS := ["North", "North_East", "East", "South_East", "South", "South_West", "West", "North_West"]
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


static func finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(v: Variant) -> bool:
		return (v is int or v is float) and is_finite(float(v)) and absf(float(v)) <= 1.0e9)


# JSON numbers arrive as floats; Array.has does not equate 2.0 with 2.
static func schema_of(value: Variant) -> int:
	return int(value) if integer(value, 1, LATEST_SCHEMA) else 0


static func facing_index(value: Variant) -> int:
	return FACINGS.find(value) if value is String else -1


static func facing(value: Variant) -> bool:
	return facing_index(value) >= 0


static func intent(value: Variant, schema: int) -> bool:
	if not value is Dictionary or not vector(value.get("direction")): return false
	if schema == 1: return value.get("kind") in ["Hold", "Move"]
	return value.get("kind") in ["Hold", "Move", "Face"] and facing(value.get("facing"))


static func action_result(value: Variant, schema: int) -> bool:
	if not value is Dictionary or not vector(value.get("displacement")): return false
	if schema == 1: return value.get("kind") in RESULTS_V1
	return value.get("kind") in RESULTS_V2 and facing(value.get("facing"))


static func validate_record(record: Variant, run_id: String, fingerprint: String, owner: int) -> String:
	if not record is Dictionary or schema_of(record.get("schema_version")) == 0:
		return "Unsupported trace schema."
	var schema := schema_of(record.schema_version)
	if record.get("run_id") != run_id or record.get("fingerprint") != fingerprint or record.get("owner_id") != owner:
		return "Trace belongs to another run, content version or creature."
	for key in ["sequence", "worker_id", "definition_id", "map_id"]:
		if not integer(record.get(key), 1): return "Invalid trace %s." % key
	if not integer(record.get("facing"), 0, 7): return "Invalid facing."
	for key in ["queued_us", "started_us", "finished_us"]:
		if not integer(record.get(key)): return "Invalid worker timing."
	if record.queued_us > record.started_us or record.started_us > record.finished_us:
		return "Worker timing is out of order."
	var problem := _validate_legacy(record) if schema == 1 else _validate_current(record)
	if not problem.is_empty(): return problem
	if not action_result(record.get("result"), schema):
		return "Invalid confirmed result."
	if not vector(record.get("position_after")) or not record.get("decision_reason") is String:
		return "Missing outcome or decision reason."
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
		if schema >= 2 and (not integer(node.get("reference"), 0, 4294967295) or not integer(node.get("subject"), 0, 4294967295)):
			return "Invalid evidence reference."
		previous_time = int(node.elapsed_us)
	return ""


# Historical wander records keep their original field names and rules.
static func _validate_legacy(record: Dictionary) -> String:
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
		if not intent(agent.get("intent"), 1):
			return "Invalid intent."
		var last = agent.get("last")
		if not last is Dictionary or not intent(last.get("requested"), 1) or not action_result(last.get("result"), 1) or not integer(last.get("tick"), 0, 4294967295) or not last.get("reason") is String:
			return "Invalid previous decision record."
		if not agent.wander.get("started") is bool or agent.wander.get("phase") not in ["Idle", "Walk"]:
			return "Invalid wander phase."
		for field in ["deadline", "next_decision"]:
			if not integer(agent.wander.get(field), 0, 4294967295): return "Invalid private deadline."
	var config = record.get("config")
	if not config is Dictionary or not config.get("roam_radius") is float and not config.get("roam_radius") is int:
		return "Missing wander configuration."
	if not is_finite(float(config.roam_radius)) or config.roam_radius <= 0 or config.roam_radius > 4096:
		return "Invalid roam radius."
	return ""


static func _validate_sighting(value: Variant) -> bool:
	if not value is Dictionary: return false
	return integer(value.get("observation_id"), 1, 4294967295) and integer(value.get("subject"), 1, 4294967295) and value.get("kind") in SUBJECT_KINDS \
		and integer(value.get("appearance_id"), 1, 65535) and vector(value.get("position")) and facing(value.get("facing")) and value.get("locomotion") in LOCOMOTIONS


# A cue may carry only its observation ID, sector and band: no coordinates,
# identity, kind or action may travel through auxiliary fields.
static func _validate_cue(value: Variant) -> bool:
	if not value is Dictionary or value.keys().size() != 3: return false
	return integer(value.get("observation_id"), 1, 4294967295) and integer(value.get("sector"), 0, 7) and value.get("band") in BANDS


static func _cleared(value: Variant) -> bool:
	return value is Dictionary and integer(value.get("observation_id"), 0, 0)


static func _validate_bounded_list(list: Variant, count: Variant, check: Callable) -> bool:
	if not list is Array or list.size() != MAX_OBSERVATIONS or not integer(count, 0, MAX_OBSERVATIONS): return false
	for index in MAX_OBSERVATIONS:
		if index < int(count):
			if not check.call(list[index]): return false
		elif not _cleared(list[index]):
			return false # Removed evidence must not linger in an unused slot.
	return true


static func _validate_zones(value: Variant) -> bool:
	if not value is Array or value.size() != SCENT_ZONES: return false
	for zone in value:
		if zone not in SCENT_STRENGTHS: return false
	return true


# A scent reading carries only class, bands, an optional coarse bearing and zones.
static func _validate_scent_reading(value: Variant) -> bool:
	if not value is Dictionary or value.keys().size() != 7: return false
	if not integer(value.get("observation_id"), 1, 4294967295) or value.get("class") not in SCENT_CLASSES: return false
	if value.get("strength") not in SCENT_STRENGTHS or value.strength == "None" or value.get("freshness") not in SCENT_FRESHNESS: return false
	if not value.get("bearing_valid") is bool or not facing(value.get("bearing")): return false
	return _validate_zones(value.get("zones"))


static func _validate_scent_readings(list: Variant, count: Variant) -> bool:
	if not list is Array or list.size() != MAX_SCENT_READINGS or not integer(count, 0, MAX_SCENT_READINGS): return false
	for index in MAX_SCENT_READINGS:
		if index < int(count):
			if not _validate_scent_reading(list[index]): return false
		elif not _cleared(list[index]):
			return false
	return true


static func validate_olfaction_profile(profile: Variant) -> bool:
	return profile is Dictionary and profile.get("enabled") is bool and finite(profile.get("range")) and integer(profile.get("sample_interval"), 0, 4294967295) and profile.get("estimates_freshness") is bool


static func validate_scent_sample(sample: Variant, schema := LATEST_SCHEMA) -> String:
	if not sample is Dictionary: return "Missing nose sample."
	for key in ["sample_id", "observer", "round_id", "sample_tick", "delivered_tick"]:
		if not integer(sample.get(key), 0, 4294967295): return "Invalid nose sample identity."
	if not vector(sample.get("position")) or not validate_olfaction_profile(sample.get("profile")): return "Invalid nose sample pose or profile."
	if sample.get("status") not in SENSE_STATUSES: return "Unknown nose status."
	if not _validate_scent_readings(sample.get("readings"), sample.get("reading_count")): return "Invalid scent readings."
	if sample.status != "Sampled" and int(sample.reading_count) > 0: return "Scent without a completed sample."
	if sample.status == "Sampled" and (not sample.profile.enabled or sample.profile.range <= 0 or sample.profile.range > 1024): return "Invalid active olfaction range."
	return _validate_scent_coverage(sample, schema)


# Coverage says what the nose measured, zone by zone. It arrived with schema 5; an
# unmeasured zone can hold no scent, and a sample that never happened measured nothing.
static func _validate_scent_coverage(sample: Dictionary, schema: int) -> String:
	if schema < 5: return "Coverage in a pre-coverage schema." if sample.has("coverage") else ""
	var coverage = sample.get("coverage")
	if not coverage is Array or coverage.size() != SCENT_ZONES: return "Missing nose coverage."
	for zone in SCENT_ZONES:
		if coverage[zone] not in SCENT_COVERAGE: return "Unknown nose coverage."
		if sample.status != "Sampled" and coverage[zone] != "Unsampled": return "Coverage without a completed sample."
	for index in int(sample.reading_count):
		for zone in SCENT_ZONES:
			if sample.readings[index].zones[zone] != "None" and coverage[zone] == "Unsampled": return "Scent in an unmeasured zone."
	return ""


static func validate_emitter(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled") is bool and value.get("class") in SCENT_CLASSES and finite(value.get("intensity"))


static func validate_vision_sample(sample: Variant) -> String:
	if not sample is Dictionary: return "Missing eye sample."
	for key in ["sample_id", "observer", "round_id", "sample_tick", "delivered_tick"]:
		if not integer(sample.get(key), 0, 4294967295): return "Invalid eye sample identity."
	var pose = sample.get("pose")
	if not pose is Dictionary or not vector(pose.get("position")) or not facing(pose.get("facing")): return "Invalid sampled pose."
	var profile = sample.get("profile")
	if not profile is Dictionary or not profile.get("enabled") is bool or not finite(profile.get("range")) or not finite(profile.get("focused_fov_degrees")) or not finite(profile.get("overall_fov_degrees")) or not integer(profile.get("sample_interval"), 0, 4294967295):
		return "Invalid vision profile."
	if sample.get("status") not in SENSE_STATUSES: return "Unknown sense status."
	if not _validate_bounded_list(sample.get("focused"), sample.get("focused_count"), _validate_sighting): return "Invalid focused sightings."
	if not _validate_bounded_list(sample.get("cues"), sample.get("cue_count"), _validate_cue): return "Invalid peripheral cues."
	if sample.status != "Sampled" and (int(sample.focused_count) > 0 or int(sample.cue_count) > 0): return "Evidence without a completed sample."
	return ""


static func _validate_focused_memory(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["observed_tick", "expires_tick", "sample_id"]:
		if not integer(value.get(key), 0, 4294967295): return false
	return integer(value.get("observation_id"), 1, 4294967295) and integer(value.get("subject"), 1, 4294967295) and value.get("kind") in SUBJECT_KINDS \
		and integer(value.get("appearance_id"), 1, 65535) and vector(value.get("position")) and facing(value.get("facing")) and value.get("locomotion") in LOCOMOTIONS


static func _validate_cue_memory(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["observed_tick", "expires_tick", "sample_id"]:
		if not integer(value.get(key), 0, 4294967295): return false
	return integer(value.get("observation_id"), 1, 4294967295) and integer(value.get("sector"), 0, 7) and value.get("band") in BANDS and facing(value.get("reference_facing"))


static func _validate_scent_memory_entry(value: Variant) -> bool:
	if not value is Dictionary or value.get("class") not in SCENT_CLASSES or value.get("strength") not in SCENT_STRENGTHS or value.get("freshness") not in SCENT_FRESHNESS: return false
	if not value.get("bearing_valid") is bool or not facing(value.get("bearing")) or not _validate_zones(value.get("zones")): return false
	if not vector(value.get("origin")) or not finite(value.get("range")): return false
	for key in ["observed_tick", "expires_tick", "sample_id"]:
		if not integer(value.get(key), 0, 4294967295): return false
	return integer(value.get("observation_id"), 1, 4294967295)


static func _validate_scent_memory(memory: Variant) -> bool:
	if not memory is Dictionary or not memory.get("last_sample_empty") is bool: return false
	for key in ["last_sample_id", "last_sample_tick", "ingested_samples"]:
		if not integer(memory.get(key), 0, 4294967295): return false
	if not memory.get("entries") is Array or memory.entries.size() != MAX_SCENT_READINGS or not integer(memory.get("count"), 0, MAX_SCENT_READINGS): return false
	for index in MAX_SCENT_READINGS:
		if index < int(memory.count):
			if not _validate_scent_memory_entry(memory.entries[index]): return false
		elif not _cleared(memory.entries[index]):
			return false
	return true


static func _validate_agent(agent: Variant, input: Dictionary, schema: int) -> String:
	if not agent is Dictionary or agent.get("entity_id") != input.entity_id or agent.get("round_id") != input.round_id:
		return "Agent state does not match the observer."
	if agent.get("controller") not in (["Observe", "Search"] if schema >= 3 else ["Observe"]): return "Unknown controller."
	if schema >= 3 and not SearchContract.valid(agent.get("search"), schema): return "Invalid private search state."
	if schema >= 4 and not _validate_scent_memory(agent.get("scent")): return "Invalid private scent memory."
	var memory = agent.get("memory")
	if not memory is Dictionary or not integer(memory.get("last_sample_id"), 0, 4294967295) or not integer(memory.get("ingested_samples"), 0, 4294967295):
		return "Invalid private memory."
	if not _validate_bounded_list(memory.get("focused"), memory.get("focused_count"), _validate_focused_memory): return "Invalid remembered sightings."
	if not _validate_bounded_list(memory.get("cues"), memory.get("cue_count"), _validate_cue_memory): return "Invalid remembered cues."
	var attention = agent.get("attention")
	if not attention is Dictionary or attention.get("state") not in ATTENTION_STATES or attention.get("evidence") not in EVIDENCE_KINDS or not attention.get("scan_armed") is bool:
		return "Invalid attention state."
	for key in ["subject", "observation_id", "evidence_tick", "scan_deadline"]:
		if not integer(attention.get(key), 0, 4294967295): return "Invalid attention reference."
	if not facing(attention.get("desired_facing")): return "Invalid desired facing."
	if not intent(agent.get("intent"), 2): return "Invalid intent."
	var last = agent.get("last")
	if not last is Dictionary or not intent(last.get("requested"), 2) or not action_result(last.get("result"), 2) or not integer(last.get("tick"), 0, 4294967295) or last.get("reason") not in (REASONS_V2 + SearchContract.REASONS if schema >= 3 else REASONS_V2):
		return "Invalid previous decision record."
	return ""


static func _validate_current(record: Dictionary) -> String:
	var input = record.get("input")
	if not input is Dictionary or not vector(input.get("position")) or not facing(input.get("facing")) or not input.get("can_act") is bool or not input.get("turn_ready") is bool:
		return "Invalid private input."
	for key in ["entity_id", "round_id", "tick"]:
		if not integer(input.get(key), 0, 4294967295): return "Invalid input identity/tick."
	if input.entity_id == 0: return "Missing runtime entity."
	var schema := int(record.schema_version)
	var senses = input.get("senses")
	if not senses is Dictionary or not senses.get("vision_is_new") is bool: return "Invalid sense input."
	var problem := validate_vision_sample(senses.get("vision"))
	if not problem.is_empty(): return problem
	var sample: Dictionary = senses.vision
	if sample.status == "Sampled" and (sample.observer != input.entity_id or sample.round_id != input.round_id or ((int(input.tick) - int(sample.sample_tick)) & 0xffffffff) > 0x7fffffff):
		return "Eye sample belongs to another observer or a later tick."
	if schema >= 4:
		if not senses.get("olfaction_is_new") is bool or not validate_emitter(input.get("own_emitter")): return "Invalid olfaction input."
		problem = validate_scent_sample(senses.get("olfaction"), schema)
		if not problem.is_empty(): return problem
		var nose: Dictionary = senses.olfaction
		if nose.status == "Sampled" and (nose.observer != input.entity_id or nose.round_id != input.round_id or ((int(input.tick) - int(nose.sample_tick)) & 0xffffffff) > 0x7fffffff):
			return "Nose sample belongs to another observer or a later tick."
	elif senses.has("olfaction") or input.has("own_emitter"):
		return "Olfaction data in a pre-olfaction schema."
	if record.get("decision_reason") not in (REASONS_V2 + SearchContract.REASONS if schema >= 3 else REASONS_V2): return "Unknown decision reason."
	if not integer(record.get("facing_after"), 0, 7): return "Invalid confirmed facing."
	for key in ["before", "after"]:
		problem = _validate_agent(record.get(key), input, int(record.schema_version))
		if not problem.is_empty(): return problem
	var config = record.get("config")
	if not config is Dictionary or not config.get("memory") is Dictionary or not integer(config.get("scan_interval_ticks"), 1, 3600) or not integer(config.get("scan_step"), 1, 7):
		return "Missing observe configuration."
	for key in ["focused_retention_ticks", "peripheral_retention_ticks"]:
		if not integer(config.memory.get(key), 1, 3600): return "Invalid retention."
	var audit = record.get("host_audit")
	if not audit is Dictionary or not integer(audit.get("sample_id"), 0, 4294967295) or not audit.get("origin_opaque") is bool or not audit.get("candidates") is Array or audit.candidates.size() > MAX_OBSERVATIONS:
		return "Invalid host audit."
	for key in ["sight_tests", "merged_cues"]:
		if not integer(audit.get(key)): return "Invalid host audit counter."
	for candidate in audit.candidates:
		if not candidate is Dictionary or not integer(candidate.get("entity_id"), 0, 4294967295) or candidate.get("verdict") not in VERDICTS or not finite(candidate.get("distance")) or not finite(candidate.get("alignment")) or not vector(candidate.get("position")):
			return "Invalid host audit candidate."
	if schema >= 4:
		var scent_audit = record.get("host_scent_audit")
		if not scent_audit is Dictionary or not integer(scent_audit.get("sample_id"), 0, 4294967295) or not integer(scent_audit.get("cells_sampled")) or not integer(scent_audit.get("cells_blind")):
			return "Invalid host scent audit."
		# Per-class values arrive keyed by class name, one entry per known class.
		for key in ["peak", "newest_age_ticks", "coherence"] + (["newest_detectable_age_ticks"] if schema >= 5 else []):
			var values = scent_audit.get(key)
			if not values is Dictionary or values.keys() != SCENT_CLASSES or not values.values().all(finite): return "Invalid host scent audit values."
		if schema >= 5 and not integer(scent_audit.get("cells_excluded")): return "Invalid host scent audit."
		if schema < 5 and (scent_audit.has("cells_excluded") or scent_audit.has("newest_detectable_age_ticks")): return "Coverage audit in a pre-coverage schema."
	var fan = record.get("sight_fan")
	if not fan is Array or fan.size() > MAX_FAN: return "Invalid sight fan."
	for point in fan:
		if not vector(point): return "Invalid sight fan point."
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
	if not value is Dictionary or schema_of(value.get("schema_version")) == 0 or value.get("run_id") != run_id or value.get("fingerprint") != fingerprint or value.get("owner_id") != owner:
		error = "Snapshot schema, run, content or creature mismatch."
		return false
	if not value.get("records") is Array or value.records.size() > 128:
		error = "Invalid snapshot history."
		return false
	for key in ["published_us", "dropped_records", "overwritten_records", "publish_us", "log_limit_bytes", "retained_segments"]:
		if not integer(value.get(key)):
			error = "Invalid snapshot counter."
			return false
	if schema_of(value.schema_version) >= 2 and (not integer(value.get("oversized_records")) or not integer(value.get("record_limit_bytes"), 1)):
		error = "Invalid snapshot record ceiling."
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


# Evidence a branch referenced, resolved only from the record's own delivered
# sample and private memory. Never from another record or a live world.
static func evidence_for(record: Dictionary, reference: int, subject: int) -> Dictionary:
	var found := {}
	if int(record.get("schema_version", 1)) < 2 or reference == 0 and subject == 0: return found
	var sample: Dictionary = record.input.senses.vision
	for index in int(sample.focused_count):
		if int(sample.focused[index].observation_id) == reference: found["focused_sighting"] = sample.focused[index]
	for index in int(sample.cue_count):
		if int(sample.cues[index].observation_id) == reference: found["peripheral_cue"] = sample.cues[index]
	if int(sample.sample_id) == reference: found["eye_sample"] = {"sample_id": sample.sample_id, "sample_tick": sample.sample_tick, "status": sample.status, "focused_count": sample.focused_count, "cue_count": sample.cue_count}
	if int(record.get("schema_version", 1)) >= 4:
		var nose: Dictionary = record.input.senses.olfaction
		for index in int(nose.reading_count):
			if int(nose.readings[index].observation_id) == reference: found["scent_reading"] = nose.readings[index]
		if int(nose.sample_id) == reference: found["nose_sample"] = {"sample_id": nose.sample_id, "sample_tick": nose.sample_tick, "status": nose.status, "reading_count": nose.reading_count}
		for key in ["before", "after"]:
			var scent: Dictionary = record[key].scent
			for index in int(scent.count):
				if int(scent.entries[index].observation_id) == reference: found["remembered_scent_" + key] = scent.entries[index]
	for key in ["before", "after"]:
		var memory: Dictionary = record[key].memory
		for index in int(memory.focused_count):
			var entry: Dictionary = memory.focused[index]
			if int(entry.observation_id) == reference or (subject != 0 and int(entry.subject) == subject): found["remembered_subject_" + key] = entry
		for index in int(memory.cue_count):
			if int(memory.cues[index].observation_id) == reference: found["remembered_cue_" + key] = memory.cues[index]
	return found
