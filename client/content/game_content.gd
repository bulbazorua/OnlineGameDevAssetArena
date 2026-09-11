class_name GameContent
extends RefCounted

const CharacterVisual = preload("res://characters/character_visual.gd")
const CharacterArtifact = preload("res://characters/character_artifact.gd")
const CharacterView = preload("res://characters/character_view.gd")
const ArenaCatalog = preload("res://content/arena_catalog.gd")
const ArenaPresentation = preload("res://content/arena_presentation.gd")
const TinySwordsTileset = preload("res://world/tiny_swords_tileset.gd")
const TerrainTileset = preload("res://world/terrain_tileset.gd")
const PlayerContent = preload("res://content/player_content.gd")
const SenseCatalog = preload("res://content/sense_catalog.gd")
# Sorted paths are part of the compatibility contract.
const DATA_FILES := ["arenas.json", "characters.json", "senses.json", "terrains.json"]

class CharacterDefinition:
	extends RefCounted
	var id: int
	var key: String
	var display_name: String
	var footprint_radius: float
	var sense_profile: String
	var vision: SenseCatalog.VisionProfile
	var olfaction: SenseCatalog.OlfactionProfile
	var emitter: SenseCatalog.ScentEmitter

var characters: Array[CharacterDefinition] = []
var by_id: Dictionary = {}
var visuals: Dictionary = {}
var character_art: Dictionary = {}
var player_content := PlayerContent.new()
var arena_catalog := ArenaCatalog.new()
var sense_catalog := SenseCatalog.new()
var tile_set: TileSet
var presentations: Dictionary = {}
var tile_sets: Dictionary = {}
var fingerprint := PackedByteArray()


func load_catalog(directory := "res://content/data") -> String:
	_clear()
	var parsed: Dictionary = {}
	var files: Dictionary = {}
	for relative_path in DATA_FILES:
		var path := directory.path_join(relative_path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return "Cannot read game content: %s" % path
		var bytes := file.get_buffer(file.get_length())
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) != OK:
			return "Invalid JSON in %s: %s" % [relative_path, parser.get_error_message()]
		files[relative_path] = bytes
		parsed[relative_path] = parser.data
	var error := _parse_characters(parsed["characters.json"])
	if error.is_empty():
		error = player_content.load_catalog()
	if error.is_empty():
		error = arena_catalog.parse_terrains(parsed["terrains.json"])
	if error.is_empty():
		error = sense_catalog.parse(parsed["senses.json"], characters.map(func(definition): return definition.key))
		for definition in characters:
			definition.sense_profile = sense_catalog.bindings.get(definition.key, "")
			definition.vision = sense_catalog.vision_for(definition.key)
			definition.olfaction = sense_catalog.olfaction_for(definition.key)
			definition.emitter = sense_catalog.emitter_for(definition.key)
	if error.is_empty():
		var radius := 0.0
		for character in characters:
			radius = maxf(radius, character.footprint_radius)
		error = arena_catalog.parse_arenas(parsed["arenas.json"], radius)
	if error.is_empty():
		error = TerrainTileset.validate(arena_catalog)
	if not error.is_empty():
		_clear()
		return error
	tile_set = TerrainTileset.build(arena_catalog)
	tile_sets["ninja_adventure"] = tile_set
	for arena in arena_catalog.arenas:
		var presentation := ArenaPresentation.new()
		error = presentation.load_definition(arena, arena_catalog)
		if error.is_empty() and presentation.theme == "tiny_swords" and not tile_sets.has("tiny_swords"):
			error = TinySwordsTileset.validate(arena_catalog)
			if error.is_empty():
				tile_sets["tiny_swords"] = TinySwordsTileset.build(arena_catalog)
		if not error.is_empty():
			_clear()
			return error
		presentations[arena.id] = presentation
	fingerprint = digest_files(files)
	return ""


func _clear() -> void:
	characters.clear()
	by_id.clear()
	visuals.clear()
	character_art.clear()
	player_content.art = null
	fingerprint.clear()
	arena_catalog.clear()
	sense_catalog.clear()
	tile_set = null
	presentations.clear()
	tile_sets.clear()


static func digest_files(files: Dictionary) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var paths := files.keys()
	paths.sort()
	for path: String in paths:
		var encoded_path := path.to_utf8_buffer()
		var bytes: PackedByteArray = files[path]
		hash.update(_length_bytes(encoded_path.size()))
		hash.update(encoded_path)
		hash.update(_length_bytes(bytes.size()))
		hash.update(bytes)
	return hash.finish()


func _parse_characters(root: Variant) -> String:
	var declarations = JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/characters.json"))
	if not declarations is Dictionary or declarations.get("schema_version") != 1 or not declarations.get("modules") is Dictionary:
		return "Invalid character presentation declarations."
	if not root is Dictionary or not _is_integer(root.get("schema_version"), 1, 1) or not root.get("characters") is Array:
		return "Character catalog must have schema_version 1 and a characters array."
	var entries: Array = root.characters
	if entries.is_empty() or entries.size() > 65535:
		return "Character catalog must contain between 1 and 65535 characters."
	var keys: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary or not _is_integer(entry.get("id"), 1, 65535):
			return "Every character needs an integer ID between 1 and 65535."
		if not entry.get("key") is String or not entry.get("display_name") is String:
			return "Every character needs a key and display name."
		var key: String = entry.key
		var character_id := int(entry.id)
		if key.is_empty() or entry.display_name.strip_edges().is_empty() or by_id.has(character_id) or keys.has(key):
			return "Character IDs and keys must be unique; keys and names cannot be empty."
		for character in key:
			if not (character >= "a" and character <= "z" or character >= "0" and character <= "9" or character == "_"):
				return "Character keys can only contain lowercase letters, digits, and underscores."
		var radius: Variant = entry.get("footprint_radius")
		if not (radius is float or radius is int) or not is_finite(float(radius)) or radius <= 0 or radius > 3.4028234663852886e38 or radius < 1.401298464324817e-45:
			return "Character footprint radius must be a finite, positive float32 value."
		if declarations.modules.has(key):
			var art_error := _load_character_art(key, character_id, float(radius))
			if not art_error.is_empty(): return art_error
		else:
			var visual_path := "res://characters/visuals/%s.tres" % key
			if not ResourceLoader.exists(visual_path):
				return "Missing character visual: %s" % visual_path
			var visual = load(visual_path)
			if not visual is CharacterVisual or visual.character_id != character_id or visual.placeholder_kind < 0 or visual.placeholder_kind > 3:
				return "Character visual does not match catalog ID %d." % character_id
			visuals[character_id] = visual
		var definition := CharacterDefinition.new()
		definition.id = character_id
		definition.key = key
		definition.display_name = entry.display_name
		definition.footprint_radius = PackedFloat32Array([float(radius)])[0] # Match Odin f32 storage.
		characters.append(definition)
		by_id[character_id] = definition
		keys[key] = true
	return ""


func _load_character_art(key: String, id: int, radius: float) -> String:
	var path := "res://generated/characters/catalog.json"
	if not FileAccess.file_exists(path): return "Missing processed character bundle. Run make prepare_characters."
	var bundle = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not bundle is Dictionary or bundle.get("schema_version") != 1 or not bundle.get("modules") is Dictionary:
		return "Invalid processed character bundle."
	var entry = bundle.modules.get(key)
	if not entry is Dictionary or not entry.get("artifact") is String or not entry.get("digest") is String or entry.digest.length() != 64 or not entry.artifact.begins_with("res://generated/characters/" + key + "/") or ".." in entry.artifact.split("/"):
		return "Missing/invalid processed character: " + key
	var result := CharacterArtifact.read(entry.artifact, entry.digest)
	if not result.error.is_empty(): return result.error
	if not result.report.art_pass or result.candidate.contract_id != "character.basic_combat" or result.candidate.module_key != key or result.candidate.gameplay_definition.get("identity", {}).get("key") != key:
		return "Character does not satisfy the animation contract: " + key
	var definition: Dictionary = result.candidate.gameplay_definition
	if not is_equal_approx(float(definition.footprint_radius_units) * float(definition.gameplay_size) * 32.0, radius):
		return "Character art/gameplay footprint mismatch: " + key
	character_art[id] = result.candidate
	return ""


func configure_character(view: CharacterView, id: int, owner := 0, shape_radius := 24.0, art_multiplier := 1.0) -> void:
	if view.character_id == id and view.player_id == owner: return
	if character_art.has(id):
		var exported = character_art[id]
		view.configure_art(exported.art, owner, exported.gameplay_definition.gameplay_size * art_multiplier, exported.gameplay_definition.footprint_radius_units)
	else:
		view.configure(visuals.get(id), owner, shape_radius)
	view.character_id = id
	view.start_animation()


static func _is_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))


static func _length_bytes(value: int) -> PackedByteArray:
	return PackedByteArray([value & 255, (value >> 8) & 255, (value >> 16) & 255, (value >> 24) & 255])
