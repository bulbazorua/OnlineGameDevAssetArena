extends SceneTree

const GameContent = preload("res://content/game_content.gd")
const GameProtocol = preload("res://network/protocol.gd")
const FIXTURE := '{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12}]}'
const FIXTURE_DIGEST := "29168231dea59a12b14e13482d71a2a7c90324dfddacbacb50a543b5882f58e8"
const OLFACTION := '"olfaction":{"receptor":{"enabled":true,"range_units":5.0,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":1.0}}'
const SENSES := '{"schema_version":2,"profiles":[{"key":"starter_senses","vision":{"enabled":true,"range_units":8.0,"focused_fov_degrees":60.0,"overall_fov_degrees":160.0,"sample_interval_ticks":6},' + OLFACTION + '}],"trainer_emitter":{"enabled":true,"scent_class":"human","intensity":1.0},"bindings":[{"character":"circle","profile":"starter_senses"}]}'
var failures: Array[String] = []


func _initialize() -> void:
	var directory := "user://content-check-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	for filename in ["terrains.json", "arenas.json"]:
		DirAccess.copy_absolute("res://content/data/" + filename, directory.path_join(filename))
	var catalog := GameContent.new()
	_write_fixture(directory, FIXTURE)
	_write_senses(directory, SENSES)
	_expect(catalog.load_catalog(directory).is_empty(), "Valid catalog failed to load.")
	_expect(catalog.sense_catalog.profiles.size() == 1 and catalog.by_id[1].vision != null and catalog.by_id[1].vision.range == 256.0 and catalog.by_id[1].sense_profile == "starter_senses", "Sense profile did not resolve to world units.")
	_expect(catalog.by_id[1].olfaction != null and catalog.by_id[1].olfaction.range == 160.0 and catalog.by_id[1].olfaction.sample_interval == 12 and catalog.by_id[1].olfaction.estimates_freshness, "Olfaction receptor did not resolve to world units.")
	_expect(catalog.by_id[1].emitter != null and catalog.by_id[1].emitter.enabled and catalog.by_id[1].emitter.scent_class == "human" and catalog.sense_catalog.trainer_emitter.scent_class == "human", "Scent emitters did not load.")
	_expect(GameContent.digest_files({"characters.json": FIXTURE.to_utf8_buffer()}).hex_encode() == FIXTURE_DIGEST, "Godot digest differs from independent SHA-256 fixture.")
	_write_fixture(directory, FIXTURE.replace('"id":1', '"id":1.0'))
	_expect(catalog.load_catalog(directory).is_empty(), "Integral decimal character ID was rejected.")
	for invalid in [
		"{", "[]", FIXTURE.replace('"schema_version":1', '"schema_version":2'),
		FIXTURE.replace('"id":1', '"id":0'), FIXTURE.replace('"id":1', '"id":65536'),
		FIXTURE.replace('"id":1', '"id":1.5'), FIXTURE.replace('"id":1', '"id":true'),
		FIXTURE.replace('"circle"', '"../circle"'), FIXTURE.replace('"Circle"', '" "'),
		FIXTURE.replace('"footprint_radius":12', '"footprint_radius":0'),
		FIXTURE.replace('"footprint_radius":12', '"footprint_radius":-2'),
		FIXTURE.replace('"footprint_radius":12', '"footprint_radius":1e100'),
		FIXTURE.replace('"footprint_radius":12', '"footprint_radius":1e-100'),
		FIXTURE.replace('"circle"', '"missing_visual"'), FIXTURE.replace('"id":1', '"id":2'),
		FIXTURE.replace('}]}', '},{"id":1,"key":"square","display_name":"Square","footprint_radius":12}]}'),
	]:
		_write_fixture(directory, invalid)
		_expect(not catalog.load_catalog(directory).is_empty(), "Invalid catalog was accepted: " + invalid)
		_expect(catalog.fingerprint.is_empty() and catalog.characters.is_empty(), "Invalid load left usable content.")
	_write_fixture(directory, FIXTURE)
	for invalid_senses in [
		"{", SENSES.replace('"schema_version":2', '"schema_version":1'), SENSES.replace('"enabled":true,"range_units":8.0', '"enabled":1,"range_units":8.0'),
		SENSES.replace(OLFACTION, '"olfaction":{"receptor":{"enabled":true,"range_units":5.0,"sample_interval_ticks":12,"estimates_freshness":true}}'),
		SENSES.replace('"range_units":5.0', '"range_units":0'), SENSES.replace('"range_units":5.0', '"range_units":32.5'),
		SENSES.replace('"sample_interval_ticks":12', '"sample_interval_ticks":61'), SENSES.replace('"estimates_freshness":true', '"estimates_freshness":"yes"'),
		SENSES.replace('"scent_class":"human","intensity":1.0}}', '"scent_class":"robot","intensity":1.0}}'), SENSES.replace('"intensity":1.0}}', '"intensity":0}}'),
		SENSES.replace('"intensity":1.0}}', '"intensity":4.5}}'), SENSES.replace(',"trainer_emitter":{"enabled":true,"scent_class":"human","intensity":1.0}', ''),
		SENSES.replace('"trainer_emitter":{"enabled":true,"scent_class":"human","intensity":1.0}', '"trainer_emitter":{"enabled":true,"intensity":1.0}'),
		SENSES.replace('"range_units":8.0', '"range_units":0'), SENSES.replace('"range_units":8.0', '"range_units":64.5'),
		SENSES.replace('"enabled":true', '"enabled":false').replace('"range_units":8.0', '"range_units":-1'),
		SENSES.replace('"focused_fov_degrees":60.0', '"focused_fov_degrees":44.9'), SENSES.replace('"focused_fov_degrees":60.0', '"focused_fov_degrees":160.0'),
		SENSES.replace('"overall_fov_degrees":160.0', '"overall_fov_degrees":180.5'), SENSES.replace('"sample_interval_ticks":6', '"sample_interval_ticks":0'),
		SENSES.replace('"sample_interval_ticks":6', '"sample_interval_ticks":61'), SENSES.replace('"sample_interval_ticks":6', '"sample_interval_ticks":1.5'),
		SENSES.replace('"character":"circle"', '"character":"square"'), SENSES.replace('"profile":"starter_senses"}]', '"profile":"missing"}]'),
		SENSES.replace('"bindings":[', '"bindings":[{"character":"circle","profile":"starter_senses"},'), SENSES.replace('"bindings":[{"character":"circle","profile":"starter_senses"}]', '"bindings":[]'),
		SENSES.replace('"key":"starter_senses"', '"key":"Starter"'),
	]:
		_write_senses(directory, invalid_senses)
		_expect(not catalog.load_catalog(directory).is_empty(), "Invalid sense catalog was accepted: " + invalid_senses)
		_expect(catalog.fingerprint.is_empty() and catalog.sense_catalog.profiles.is_empty(), "Invalid sense load left usable content.")
	_write_senses(directory, SENSES)
	var terrains := FileAccess.get_file_as_string(directory.path_join("terrains.json"))
	_write_terrains(directory, terrains.replace('"schema_version": 3', '"schema_version": 2'))
	_expect(not catalog.load_catalog(directory).is_empty(), "Schema-2 terrain catalog without scent media was accepted.")
	_write_terrains(directory, terrains.replace('"blocks_vision": false', '"walkable": true'))
	_expect(not catalog.load_catalog(directory).is_empty(), "Terrain without blocks_vision was accepted.")
	_write_terrains(directory, terrains.replace('"scent": "water"', '"scent": "mud"'))
	_expect(not catalog.load_catalog(directory).is_empty(), "Terrain with an unknown scent medium was accepted.")
	_write_terrains(directory, terrains.replace(',\n      "scent": "open"', ''))
	_expect(not catalog.load_catalog(directory).is_empty(), "Terrain without a scent medium was accepted.")
	_write_terrains(directory, terrains)
	_expect(catalog.load_catalog(directory).is_empty(), "Restored terrain catalog failed.")
	DirAccess.remove_absolute(directory.path_join("characters.json"))
	_expect(not catalog.load_catalog(directory).is_empty(), "Missing catalog was accepted.")
	for filename in ["terrains.json", "arenas.json", "senses.json"]:
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	_expect(catalog.load_catalog().is_empty() and catalog.characters.size() == 6 and catalog.character_art.size() == 2 and catalog.sense_catalog.bindings.size() == 6, "Shipped catalog, sense bindings or processed character art failed to load.")
	for definition in catalog.characters:
		_expect(definition.vision != null and definition.vision.enabled and definition.vision.range == 256.0 and definition.vision.focused_fov_degrees == 60.0 and definition.vision.overall_fov_degrees == 160.0 and definition.vision.sample_interval == 6, "Shipped starter vision profile differs from the documented tuning.")
		_expect(definition.olfaction != null and definition.olfaction.sample_interval == 12 and definition.emitter != null, "Shipped olfaction profile is missing.")
	_expect(catalog.by_id[5].olfaction.enabled and catalog.by_id[5].emitter.enabled and catalog.by_id[6].olfaction.enabled and catalog.by_id[6].emitter.enabled, "Archer and Orc must smell and emit.")
	_expect(catalog.by_id[5].olfaction.range == 160.0 and catalog.by_id[6].olfaction.range == 256.0 and catalog.by_id[5].emitter.scent_class == "human" and catalog.by_id[6].emitter.scent_class == "orc", "Archer/Orc olfaction differs from the documented tuning.")
	_expect(catalog.by_id[4].olfaction.enabled and not catalog.by_id[4].olfaction.estimates_freshness and not catalog.by_id[4].emitter.enabled, "Diamond must be the scentless sensor with unknown freshness.")
	for shape in [1, 2, 3]:
		_expect(not catalog.by_id[shape].olfaction.enabled and not catalog.by_id[shape].emitter.enabled, "Placeholder shapes neither smell nor emit.")
	_expect(catalog.sense_catalog.trainer_emitter.enabled and catalog.sense_catalog.trainer_emitter.scent_class == "human", "Trainers must emit generic human scent.")
	var water = catalog.arena_catalog.terrains.filter(func(terrain): return terrain.key == "water")[0]
	var stone = catalog.arena_catalog.terrains.filter(func(terrain): return terrain.key == "stone")[0]
	_expect(not water.walkable and not water.blocks_vision and not stone.walkable and stone.blocks_vision, "Terrain walkability and sight blocking must stay independent.")
	_expect(water.scent == "water" and stone.scent == "solid", "Terrain scent media differ from the authored rules.")
	_check_protocol()
	if failures.is_empty():
		print("PASS: catalog validation, sense profiles/bindings, terrain sight blocking, SHA-256 fixture, four visual resources, protocol fixtures and invalid states.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_protocol() -> void:
	var welcome := PackedByteArray([79, 71, 65, 65, 11, 2, 0, 136, 19, 0, 0])
	var welcomed := GameProtocol.decode(welcome, 0)
	_expect(welcomed.error_title.is_empty() and welcomed.player_id == 0 and welcomed.audience_delay_ms == 5000, "Audience Welcome delay differs from Odin.")
	for invalid in [welcome.slice(0, 7), PackedByteArray([79, 71, 65, 65, 5, 2, 0, 136, 19, 0, 0]), PackedByteArray([79, 71, 65, 65, 11, 2, 1, 136, 19, 0, 0]), PackedByteArray([79, 71, 65, 65, 11, 2, 0, 97, 234, 0, 0])]:
		_expect(not GameProtocol.decode(invalid, 0).error_title.is_empty(), "Invalid or old Welcome delay was accepted.")
	var packet := PackedByteArray([79, 71, 65, 65, 11, 3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 3, 1, 2, 1, 0, 4, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0])
	var state := GameProtocol.decode(packet, 0).session
	_expect(state != null and state.round_id == 0x04030201 and state.revision == 0x08070605 and state.audience_count == 513 and state.players[0].character_id == 4 and state.players[0].ready, "Session wire fixture differs from Odin.")
	var command := GameProtocol.encode_command(GameProtocol.MessageKind.SELECT_CHARACTER, 0x04030201, 4)
	_expect(command == PackedByteArray([79, 71, 65, 65, 11, 5, 1, 2, 3, 4, 4, 0]), "SelectCharacter wire fixture differs from Odin.")
	for length in packet.size():
		_expect(not GameProtocol.decode(packet.slice(0, length), 0).error_title.is_empty(), "Truncated state accepted.")
	for edit in [[14, 2], [15, 1], [18, 0], [26, 1], [20, 0], [22, 2], [14, 0]]:
		var corrupt := packet.duplicate()
		corrupt[edit[0]] = edit[1]
		_expect(not GameProtocol.decode(corrupt, 0).error_title.is_empty(), "Invalid state accepted: " + str(edit))
	_expect(not GameProtocol.decode(packet, 1).error_title.is_empty(), "Wrong channel accepted.")
	var reset := GameProtocol.encode_command(GameProtocol.MessageKind.DEV_RESET_SEARCH, 0x04030201)
	_expect(reset == PackedByteArray([79, 71, 65, 65, 11, 12, 1, 2, 3, 4]), "Search reset must contain only its expected round.")
	for reason in [GameProtocol.CommandRejectReason.DEV_ONLY, GameProtocol.CommandRejectReason.SEARCH_RESET_UNAVAILABLE]:
		var rejected := GameProtocol.decode(PackedByteArray([79, 71, 65, 65, 11, 8, 1, 2, 3, 4, 12, reason]), 0)
		_expect(rejected.error_title.is_empty() and rejected.rejected_kind == GameProtocol.MessageKind.DEV_RESET_SEARCH and rejected.rejection_reason == reason, "Search-reset rejection lost its command identity or reason.")


func _write_fixture(directory: String, text: String) -> void:
	var file := FileAccess.open(directory.path_join("characters.json"), FileAccess.WRITE)
	file.store_string(text)


func _write_senses(directory: String, text: String) -> void:
	var file := FileAccess.open(directory.path_join("senses.json"), FileAccess.WRITE)
	file.store_string(text)


func _write_terrains(directory: String, text: String) -> void:
	var file := FileAccess.open(directory.path_join("terrains.json"), FileAccess.WRITE)
	file.store_string(text)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		failures.append(failure)
