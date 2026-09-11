extends SceneTree

# Recorded olfaction survives pause and seeking without touching the live field,
# and older-schema frames stay honest about having no smell.
const Reader = preload("res://dev/ai/replay_reader.gd")
const Stage = preload("res://dev/ai/replay_stage.gd")
const Content = preload("res://content/game_content.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20).timeout.connect(func(): push_error("Scent replay check did not finish."); quit(1))
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): path = argument.trim_prefix("--fixture=")
	var content := Content.new()
	assert(content.load_catalog().is_empty())
	var reader := Reader.new()
	assert(reader.scan(path, content.fingerprint.hex_encode()), reader.error)
	assert(int(reader.header.schema_version) == 5 and int(reader.header.trace_schema) == 5)
	var smelled := -1
	var smelled_owner := 0
	var reset_rounds := {}
	for index in reader.entries.size():
		var decoded := reader.read_frame(index)
		assert(decoded.error.is_empty(), decoded.error)
		if decoded.snapshot.characters.size() == 2: reset_rounds[decoded.snapshot.round_id] = index
		for trace in decoded.frame.ai:
			var nose: Dictionary = trace.input.senses.olfaction
			assert(nose.status != "Sampled" or int(nose.sample_tick) <= int(trace.input.tick))
			assert(nose.status != "Sampled" or int(nose.reading_count) <= 2)
			assert(nose.coverage.size() == 16 and (nose.status == "Sampled" or nose.coverage.all(func(zone): return zone == "Unsampled")), "recorded coverage must be the nose's own footprint")
			if nose.status == "Sampled" and int(nose.reading_count) > 0 and smelled < 0:
				smelled = index
				smelled_owner = int(trace.owner_id)
			for search in [trace.before.search, trace.after.search]:
				if search.scent.valid: assert(search.scent.class in ["Human", "Orc"] and not search.scent.has("position"))
	assert(smelled >= 0, "The recording holds no delivered scent reading")
	assert(reset_rounds.size() >= 2, "The recording should cross the reset into a new round")
	var frame: Dictionary = reader.read_frame(smelled).frame
	var trace: Dictionary = frame.ai.filter(func(record): return int(record.owner_id) == smelled_owner)[0]
	var readings: Array = trace.input.senses.olfaction.readings.slice(0, int(trace.input.senses.olfaction.reading_count))
	# Seek away and back: the same recorded readings return, never a newer live field.
	var earlier: Dictionary = reader.read_frame(maxi(0, smelled - 40)).frame
	var again: Dictionary = reader.read_frame(smelled).frame
	var same: Dictionary = again.ai.filter(func(record): return int(record.owner_id) == smelled_owner)[0]
	assert(same.input.senses.olfaction.readings.slice(0, int(same.input.senses.olfaction.reading_count)) == readings, "Seeking back and forth changed the recorded scent")
	assert(earlier.tick < frame.tick)
	# Frames inside the reset round begin without smell memory, the recorded way.
	var fresh_index: int = reset_rounds.values()[-1]
	var fresh: Dictionary = reader.read_frame(fresh_index).frame
	for record in fresh.ai: assert(int(record.after.scent.count) == 0, "A fresh round carried scent memory from the old one")
	print("PASS: recorded nose samples with anonymous readings, stable seeking, no live-field borrowing and a clean reset round.")
	quit()
