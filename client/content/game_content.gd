class_name GameContent
extends RefCounted

const CharacterVisual = preload("res://characters/character_visual.gd")
const ArenaCatalog = preload("res://content/arena_catalog.gd")
const TerrainTileset = preload("res://world/terrain_tileset.gd")
# Sorted paths are part of the compatibility contract.
const DATA_FILES := ["arenas.json", "characters.json", "terrains.json"]

class CharacterDefinition:
	extends RefCounted
	var id: int
	var key: String
	var display_name: String
	var footprint_radius: float

var characters: Array[CharacterDefinition] = []
var by_id: Dictionary = {}
var visuals: Dictionary = {}
var arena_catalog := ArenaCatalog.new()
var tile_set: TileSet
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
		error = arena_catalog.parse_terrains(parsed["terrains.json"])
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
	fingerprint = digest_files(files)
	return ""


func _clear() -> void:
	characters.clear()
	by_id.clear()
	visuals.clear()
	fingerprint.clear()
	arena_catalog.clear()
	tile_set = null


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
		var visual_path := "res://characters/visuals/%s.tres" % key
		if not ResourceLoader.exists(visual_path):
			return "Missing character visual: %s" % visual_path
		var visual = load(visual_path)
		if not visual is CharacterVisual or visual.character_id != character_id or visual.placeholder_kind < 0 or visual.placeholder_kind > 3:
			return "Character visual does not match catalog ID %d." % character_id
		var definition := CharacterDefinition.new()
		definition.id = character_id
		definition.key = key
		definition.display_name = entry.display_name
		definition.footprint_radius = PackedFloat32Array([float(radius)])[0] # Match Odin f32 storage.
		characters.append(definition)
		by_id[character_id] = definition
		visuals[character_id] = visual
		keys[key] = true
	return ""


static func _is_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))


static func _length_bytes(value: int) -> PackedByteArray:
	return PackedByteArray([value & 255, (value >> 8) & 255, (value >> 16) & 255, (value >> 24) & 255])
