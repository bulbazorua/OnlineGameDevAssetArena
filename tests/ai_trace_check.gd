extends SceneTree

const Reader = preload("res://dev/ai/trace_reader.gd")
var failed := false


func check(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error(message)


func _initialize() -> void:
	var fixture := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
	var snapshot = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not snapshot is Dictionary:
		push_error("Missing real host trace fixture.")
		quit(1)
		return
	var reader := Reader.new()
	check(reader.read_snapshot(fixture, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)), "Valid production snapshot was rejected: " + reader.error)
	if reader.records.is_empty(): quit(1); return
	var record: Dictionary = reader.records.back()
	check(Reader.validate_record(record, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Valid decision rejected.")
	for mutate in [
		func(r): r.nodes[1].parent = r.nodes[1].id,
		func(r): r.nodes[1].elapsed_us = -1,
		func(r): r.nodes[0].direction = [INF, 0],
		func(r): r.input.position = [0],
		func(r): r.after.entity_id += 1,
		func(r): r.started_us = r.finished_us + 1,
		func(r): r.nodes[0].status = "Invented",
		func(r): r.nodes.resize(49),
	]:
		var broken: Dictionary = record.duplicate(true)
		mutate.call(broken)
		check(not Reader.validate_record(broken, snapshot.run_id, snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Malformed record accepted.")
	check(not Reader.validate_record(record, "different-run", snapshot.fingerprint, int(snapshot.owner_id)).is_empty(), "Cross-run record accepted.")
	check(not Reader.validate_record(record, snapshot.run_id, snapshot.fingerprint, 3 - int(snapshot.owner_id)).is_empty(), "Other creature's record accepted.")
	check(not reader.read_snapshot(fixture, "different-run", snapshot.fingerprint, int(snapshot.owner_id)), "Cross-run snapshot accepted.")
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
	if not failed: print("PASS: production trace parsing, identity, ancestry, timings, journal replay, truncation and size limits.")
	quit(1 if failed else 0)
