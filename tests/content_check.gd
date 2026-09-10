extends SceneTree

const GameContent = preload("res://content/game_content.gd")
const GameProtocol = preload("res://network/protocol.gd")
const FIXTURE := '{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12}]}'
const FIXTURE_DIGEST := "29168231dea59a12b14e13482d71a2a7c90324dfddacbacb50a543b5882f58e8"
var failures: Array[String] = []


func _initialize() -> void:
	var directory := "user://content-check-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	for filename in ["terrains.json", "arenas.json"]:
		DirAccess.copy_absolute("res://content/data/" + filename, directory.path_join(filename))
	var catalog := GameContent.new()
	_write_fixture(directory, FIXTURE)
	_expect(catalog.load_catalog(directory).is_empty(), "Valid catalog failed to load.")
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
	DirAccess.remove_absolute(directory.path_join("characters.json"))
	_expect(not catalog.load_catalog(directory).is_empty(), "Missing catalog was accepted.")
	for filename in ["terrains.json", "arenas.json"]:
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	_expect(catalog.load_catalog().is_empty() and catalog.characters.size() == 6 and catalog.character_art.size() == 2, "Shipped catalog or processed character art failed to load.")
	_check_protocol()
	if failures.is_empty():
		print("PASS: catalog validation, SHA-256 fixture, four visual resources, protocol fixtures and invalid states.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_protocol() -> void:
	var welcome := PackedByteArray([79, 71, 65, 65, 9, 2, 0, 136, 19, 0, 0])
	var welcomed := GameProtocol.decode(welcome, 0)
	_expect(welcomed.error_title.is_empty() and welcomed.player_id == 0 and welcomed.audience_delay_ms == 5000, "Audience Welcome delay differs from Odin.")
	for invalid in [welcome.slice(0, 7), PackedByteArray([79, 71, 65, 65, 5, 2, 0, 136, 19, 0, 0]), PackedByteArray([79, 71, 65, 65, 9, 2, 1, 136, 19, 0, 0]), PackedByteArray([79, 71, 65, 65, 9, 2, 0, 97, 234, 0, 0])]:
		_expect(not GameProtocol.decode(invalid, 0).error_title.is_empty(), "Invalid or old Welcome delay was accepted.")
	var packet := PackedByteArray([79, 71, 65, 65, 9, 3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 3, 1, 2, 1, 0, 4, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0])
	var state := GameProtocol.decode(packet, 0).session
	_expect(state != null and state.round_id == 0x04030201 and state.revision == 0x08070605 and state.audience_count == 513 and state.players[0].character_id == 4 and state.players[0].ready, "Session wire fixture differs from Odin.")
	var command := GameProtocol.encode_command(GameProtocol.MessageKind.SELECT_CHARACTER, 0x04030201, 4)
	_expect(command == PackedByteArray([79, 71, 65, 65, 9, 5, 1, 2, 3, 4, 4, 0]), "SelectCharacter wire fixture differs from Odin.")
	for length in packet.size():
		_expect(not GameProtocol.decode(packet.slice(0, length), 0).error_title.is_empty(), "Truncated state accepted.")
	for edit in [[14, 2], [15, 1], [18, 0], [26, 1], [20, 0], [22, 2], [14, 0]]:
		var corrupt := packet.duplicate()
		corrupt[edit[0]] = edit[1]
		_expect(not GameProtocol.decode(corrupt, 0).error_title.is_empty(), "Invalid state accepted: " + str(edit))
	_expect(not GameProtocol.decode(packet, 1).error_title.is_empty(), "Wrong channel accepted.")


func _write_fixture(directory: String, text: String) -> void:
	var file := FileAccess.open(directory.path_join("characters.json"), FileAccess.WRITE)
	file.store_string(text)


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		failures.append(failure)
