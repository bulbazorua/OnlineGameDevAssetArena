extends Node

# Local launcher IPC only. Never enabled by normal clients or release exports.
const CharacterView = preload("res://characters/character_view.gd")
const CharacterVisual = preload("res://characters/character_visual.gd")
const GameConnection = preload("res://network/game_connection.gd")
var _app: Node
var _directory := ""
var _slot := ""
var _generation := 0
var _elapsed := 0.0
var _error := ""


func configure(app: Node) -> void:
	_app = app
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-session-dir="):
			_directory = argument.trim_prefix("--dev-session-dir=")
		elif argument.begins_with("--dev-slot="):
			_slot = argument.trim_prefix("--dev-slot=")
	if not OS.is_debug_build() or "--dev" not in OS.get_cmdline_user_args() or not _directory.is_absolute_path() or not _slot.is_valid_identifier():
		queue_free()
		return
	DisplayServer.window_set_title("Asset Arena · %s · DEV" % _slot)
	_write_status()


func _process(delta: float) -> void:
	if _directory.is_empty() or _app == null:
		return
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	var path := _directory.path_join("reload.json")
	if FileAccess.file_exists(path):
		var request = JSON.parse_string(FileAccess.get_file_as_string(path))
		if request is Dictionary and int(request.get("generation", 0)) > _generation:
			_reload_visuals(request)
	_write_status()


func _reload_visuals(request: Dictionary) -> void:
	_generation = int(request.generation)
	_error = ""
	for path: String in request.paths:
		# The runner has imported and validated this immutable candidate first.
		if not path.begins_with("res://") or not _refresh_resource(path):
			_error = "Could not reload %s" % path
			push_error(_error)
			return
	_redraw_characters(_app)
	print("[dev] Visuals reloaded: generation %d" % _generation)


func _refresh_resource(path: String) -> bool:
	var cached := ResourceLoader.get_cached_ref(path)
	if cached is CharacterVisual:
		# Parse a fresh instance so deleting a .tres property restores its
		# default, then copy stored values into the instance all views share.
		var candidate := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not candidate is CharacterVisual:
			return false
		for property: Dictionary in candidate.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0 and property.name not in ["script", "resource_path"]:
				cached.set(property.name, candidate.get(property.name))
		cached.emit_changed()
		return true
	if cached is CompressedTexture2D:
		# Re-read imported pixels into the texture already bound to the TileSet.
		# Cache replacement alone does not refresh these GPU contents in 4.6.
		var metadata := ConfigFile.new()
		if metadata.load(path + ".import") != OK:
			return false
		return cached.load(metadata.get_value("remap", "path", "")) == OK
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) != null


func _redraw_characters(node: Node) -> void:
	if node is CharacterView:
		node.queue_redraw()
	for child in node.get_children():
		_redraw_characters(child)


func _write_status() -> void:
	var network = _app.network
	var snapshot = network.session
	var characters: Array = []
	if snapshot != null:
		for character in snapshot.characters:
			characters.append({"id": character.entity_id, "definition": character.definition_id,
				"owner": character.owner_id, "x": character.position.x, "y": character.position.y,
				"ack": character.applied_input_sequence, "locomotion": character.locomotion,
				"facing": character.facing, "state_start_tick": character.state_start_tick})
	var trainers: Array = []
	if snapshot != null:
		for trainer in snapshot.trainers:
			trainers.append({"id": trainer.entity_id, "definition": trainer.definition_id, "owner": trainer.owner_id,
				"x": trainer.position.x, "y": trainer.position.y, "ack": trainer.applied_input_sequence,
				"locomotion": trainer.locomotion, "facing": trainer.facing, "state_start_tick": trainer.state_start_tick})
	var visuals := {}
	for id: int in _app.content.visuals:
		var visual = _app.content.visuals[id]
		visuals[str(id)] = {"kind": visual.placeholder_kind, "tint": visual.tint.to_html()}
	var status := {"pid": OS.get_process_id(), "connected": network.connection_state == GameConnection.ConnectionState.CONNECTED,
		"player_id": network.player_id, "audience_delay_ms": network.audience_delay_ms, "phase": -1 if snapshot == null else snapshot.phase,
		"round": -1 if snapshot == null else snapshot.round_id, "tick": -1 if snapshot == null else snapshot.server_tick,
		"map": 0 if snapshot == null else snapshot.map_id, "characters": characters, "trainers": trainers,
		"summon_elapsed_ticks": 0 if snapshot == null else snapshot.summon_elapsed_ticks,
		"fingerprint": _app.content.fingerprint.hex_encode(), "sequence": _app.game_arena._sequence,
		"visual_generation": _generation, "visuals": visuals, "reload_error": _error,
		"camera_enabled": _app.game_arena.camera.enabled, "ping": network.get_ping_ms(),
		"audience": 0 if snapshot == null else snapshot.audience_count}
	var overlay := _app.get_node_or_null("DebugOverlay")
	if overlay != null: status["senses"] = overlay.senses.diagnostics()
	var path := _directory.path_join("%s.json" % _slot)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(status))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
