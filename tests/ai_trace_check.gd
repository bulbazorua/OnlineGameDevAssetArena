extends SceneTree

const Reader = preload("res://dev/ai/trace_reader.gd")
var failed := false


func check(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error(message)


func _initialize() -> void:
	var fixture := ""
	var legacy := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--legacy="): legacy = argument.trim_prefix("--legacy=")
	var snapshot = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not snapshot is Dictionary:
		push_error("Missing real host trace fixture.")
		quit(1)
		return
	var reader := Reader.new()
	check(reader.read_snapshot(fixture, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)), "Valid production snapshot was rejected: " + reader.error)
	if reader.records.is_empty(): quit(1); return
	check(int(snapshot.schema_version) == 4 and reader.records.all(func(r): return int(r.schema_version) == 4), "Production snapshot is not schema 4.")
	var record: Dictionary = reader.records.back()
	var sampled: Dictionary = record
	for candidate in reader.records:
		if candidate.input.senses.vision.status == "Sampled" and int(candidate.input.senses.vision.focused_count) + int(candidate.input.senses.vision.cue_count) > 0: sampled = candidate
	check(Reader.validate_record(record, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Valid decision rejected.")
	check(sampled.input.senses.vision.sample_tick <= sampled.input.tick, "Eye sample is newer than its decision.")
	check(sampled.sight_fan.size() == Reader.MAX_FAN and sampled.host_audit.sample_id == sampled.input.senses.vision.sample_id, "Sampled record lacks its fan or host audit.")
	var referenced := 0
	for node in sampled.nodes:
		var evidence := Reader.evidence_for(sampled, int(node.reference), int(node.subject))
		if not evidence.is_empty(): referenced += 1
	check(referenced > 0, "No branch of a sampled decision references delivered evidence.")
	for key in ["input", "before", "after"]:
		check(not _mentions_hidden_fields(record[key]), "Brain-side record %s carries host audit fields." % key)
	for mutate in [
		func(r): r.nodes[1].parent = r.nodes[1].id,
		func(r): r.nodes[1].elapsed_us = -1,
		func(r): r.nodes[0].direction = [INF, 0],
		func(r): r.input.position = [0],
		func(r): r.after.entity_id += 1,
		func(r): r.started_us = r.finished_us + 1,
		func(r): r.nodes[0].status = "Invented",
		func(r): r.nodes.resize(49),
		func(r): r.nodes[0].reference = -1,
		func(r): r.input.senses.vision.observer += 1,
		func(r): r.input.senses.vision.sample_tick = r.input.tick + 5,
		func(r): r.input.senses.vision.status = "Guessing",
		func(r): r.input.senses.vision.cues[0] = {"observation_id": 1, "sector": 1, "band": "Near", "position": [1, 2]}; r.input.senses.vision.cue_count = 1,
		func(r): r.input.senses.vision.cues[0] = {"observation_id": 1, "sector": 9, "band": "Near"}; r.input.senses.vision.cue_count = 1,
		func(r): r.input.senses.vision.focused[2].observation_id = 77; r.input.senses.vision.focused_count = 0,
		func(r): r.input.senses.vision.focused_count = 4,
		func(r): r.after.attention.state = "Chase",
		func(r): r.after.attention.evidence = "Telepathy",
		func(r): r.after.memory.focused_count = 1; r.after.memory.focused[0] = {},
		func(r): r.after.last.requested.kind = "Teleport",
		func(r): r.result.facing = "Up",
		func(r): r.decision_reason = "Wander",
		func(r): r.config.memory.focused_retention_ticks = 0,
		func(r): r.host_audit.candidates.resize(4),
		func(r): r.host_audit.candidates = [{"entity_id": 1, "verdict": "Seen", "distance": 1, "alignment": 1, "position": [0, 0]}],
		func(r): r.sight_fan.resize(66),
		func(r): r.schema_version = 5,
		func(r): r.input.senses.erase("olfaction"),
		func(r): r.input.senses.olfaction.readings[0] = {"observation_id": 1, "class": "Human", "strength": "Weak", "freshness": "Old", "bearing_valid": true, "bearing": "North", "zones": r.input.senses.olfaction.readings[0].zones, "position": [1, 2]}; r.input.senses.olfaction.reading_count = 1,
		func(r): r.input.senses.olfaction.readings[0] = {"observation_id": 1, "class": "Robot", "strength": "Weak", "freshness": "Old", "bearing_valid": true, "bearing": "North", "zones": r.input.senses.olfaction.readings[0].zones}; r.input.senses.olfaction.reading_count = 1,
		func(r): r.input.senses.olfaction.readings[1].observation_id = 9; r.input.senses.olfaction.reading_count = 0,
		func(r): r.input.senses.olfaction.reading_count = 3,
		func(r): r.input.senses.olfaction.observer += 1,
		func(r): r.input.senses.olfaction.sample_tick = r.input.tick + 5,
		func(r): r.input.own_emitter.class = "Blood",
		func(r): r.after.scent.count = 1; r.after.scent.entries[0] = {},
		func(r): r.after.search.scent.strength = "Overwhelming",
		func(r): r.after.search.transition = "Scent_Guess",
		func(r): r.host_scent_audit.peak = {"Human": 1},
		func(r): r.host_scent_audit.coherence.Orc = "high",
	]:
		var broken: Dictionary = record.duplicate(true)
		mutate.call(broken)
		check(not Reader.validate_record(broken, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Malformed record accepted.")
	check(not Reader.validate_record(record, "different-run", snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Cross-run record accepted.")
	check(not Reader.validate_record(record, snapshot.run_id, snapshot.fingerprint, 3 - int(snapshot.owner_id)).is_empty(), "Other creature's record accepted.")
	check(not reader.read_snapshot(fixture, "different-run", snapshot.fingerprint, int(snapshot.owner_id)), "Cross-run snapshot accepted.")
	# A schema-3 record has no nose: it stays readable and honest, never gaining smell.
	var pre_olfaction: Dictionary = record.duplicate(true)
	pre_olfaction.schema_version = 3
	pre_olfaction.input.senses.erase("olfaction")
	pre_olfaction.input.senses.erase("olfaction_is_new")
	pre_olfaction.input.erase("own_emitter")
	pre_olfaction.erase("host_scent_audit")
	for key in ["before", "after"]:
		pre_olfaction[key].erase("scent")
		for field in ["scent", "scent_episodes", "cue_from_scent"]: pre_olfaction[key].search.erase(field)
		pre_olfaction[key].search.profile.erase("self_trail_ticks")
		pre_olfaction[key].search.profile.erase("scent_weight")
	if pre_olfaction.after.search.evidence in ["Scent", "Scent_Memory"]: pre_olfaction.after.search.evidence = "None"
	if pre_olfaction.after.search.transition in ["Scent_Trail", "Scent_Presence", "Scent_Faded"]: pre_olfaction.after.search.transition = "No_Evidence"
	if pre_olfaction.before.search.evidence in ["Scent", "Scent_Memory"]: pre_olfaction.before.search.evidence = "None"
	if pre_olfaction.before.search.transition in ["Scent_Trail", "Scent_Presence", "Scent_Faded"]: pre_olfaction.before.search.transition = "No_Evidence"
	check(Reader.validate_record(pre_olfaction, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Schema-3 record without olfaction was rejected.")
	check(Reader.evidence_for(pre_olfaction, int(record.input.senses.olfaction.sample_id), 0).is_empty(), "Smell was invented for a schema-3 record.")
	var smuggled: Dictionary = pre_olfaction.duplicate(true)
	smuggled.input.senses["olfaction"] = record.input.senses.olfaction
	check(not Reader.validate_record(smuggled, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Schema-3 record with olfaction data was accepted.")
	check(reader.last_sequence == int(record.sequence), "Rejected snapshot mutated history.")
	var journal := fixture.trim_suffix(".json") + ".jsonl"
	var replay := Reader.new()
	check(replay.load_journal(journal, snapshot.fingerprint, int(snapshot.owner_id)), "Journal could not be replayed: " + replay.error)
	var truncated := fixture + ".truncated.jsonl"
	var file := FileAccess.open(truncated, FileAccess.WRITE)
	file.store_string(JSON.stringify(record) + "\n{\"incomplete\"")
	file.close()
	check(replay.load_journal(truncated, snapshot.fingerprint, int(snapshot.owner_id)) and not replay.warning.is_empty(), "Incomplete final line was not reported.")
	DirAccess.remove_absolute(truncated)
	var large := fixture + ".oversized.json"
	file = FileAccess.open(large, FileAccess.WRITE)
	file.store_string(" ".repeat(Reader.MAX_SNAPSHOT_BYTES + 1))
	file.close()
	check(not replay.read_snapshot(large, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)), "Oversized snapshot accepted.")
	DirAccess.remove_absolute(large)
	# Historical schema-1 wander records still decode; no eyes are invented for them.
	if not legacy.is_empty():
		var old = JSON.parse_string(FileAccess.get_file_as_string(legacy))
		var legacy_reader := Reader.new()
		check(old is Dictionary and legacy_reader.read_snapshot(legacy, old.run_id, old.fingerprint, int(old.owner_id)), "Legacy schema-1 snapshot rejected: " + legacy_reader.error)
		check(legacy_reader.records.size() == 3 and int(legacy_reader.records[0].schema_version) == 1 and legacy_reader.records[0].after.has("wander"), "Legacy records lost their original fields.")
		check(Reader.evidence_for(legacy_reader.records[0], 1, 1).is_empty(), "Evidence was fabricated for a schema-1 record.")
		var mixed: Dictionary = legacy_reader.records[0].duplicate(true)
		mixed.schema_version = 2
		check(not Reader.validate_record(mixed, old.run_id, old.fingerprint, int(old.owner_id)).is_empty(), "Schema-1 payload accepted as schema 2.")
	if not failed: print("PASS: schema-4 parsing, olfaction and scent-memory validation, evidence references, hidden-field isolation, identity, ancestry, timings, journal replay, truncation, size limits, schema-3 honesty and legacy schema-1 decoding.")
	quit(1 if failed else 0)


static func _mentions_hidden_fields(value: Variant) -> bool:
	if value is Dictionary:
		for key in value.keys():
			if key in ["verdict", "candidates", "host_audit", "sight_tests", "origin_opaque"]: return true
			if _mentions_hidden_fields(value[key]): return true
	elif value is Array:
		for item in value:
			if _mentions_hidden_fields(item): return true
	return false
