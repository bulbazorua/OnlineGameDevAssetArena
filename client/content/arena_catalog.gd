class_name ArenaCatalog
extends RefCounted

class TerrainDefinition:
	extends RefCounted
	var id: int
	var key: String
	var display_name: String
	var symbol: String
	var walkable: bool

class ArenaDefinition:
	extends RefCounted
	var id: int
	var key: String
	var display_name: String
	var width: int
	var height: int
	var tile_size: int
	var cells := PackedInt32Array()
	var spawns: Array[Vector2i] = []

	func terrain_id_at(cell: Vector2i) -> int:
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			return 0
		return cells[cell.y * width + cell.x]

	func cell_center(cell: Vector2i) -> Vector2:
		return (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size

	func world_to_cell(position: Vector2) -> Vector2i:
		return Vector2i((position / tile_size).floor())

var terrains: Array[TerrainDefinition] = []
var terrains_by_id: Dictionary = {}
var by_symbol: Dictionary = {}
var arenas: Array[ArenaDefinition] = []
var arenas_by_id: Dictionary = {}


func clear() -> void:
	terrains.clear()
	terrains_by_id.clear()
	by_symbol.clear()
	arenas.clear()
	arenas_by_id.clear()


func parse_terrains(root: Variant) -> String:
	if not valid_root(root, "terrains") or root.terrains.is_empty() or root.terrains.size() > 94:
		return "Terrain catalog requires schema_version 1 and 1–94 terrain definitions."
	var keys: Dictionary = {}
	for entry: Variant in root.terrains:
		if not valid_identity(entry) or not entry.get("symbol") is String or not entry.get("walkable") is bool:
			return "Each terrain needs an ID, key, name, symbol, and walkable boolean."
		var symbol: String = entry.symbol
		if symbol.length() != 1 or symbol.unicode_at(0) < 33 or symbol.unicode_at(0) > 126:
			return "Terrain symbols must be one printable ASCII character."
		var id := int(entry.id)
		if terrains_by_id.has(id) or keys.has(entry.key) or by_symbol.has(symbol):
			return "Terrain IDs, keys, and symbols must be unique."
		var terrain := TerrainDefinition.new()
		terrain.id = id
		terrain.key = entry.key
		terrain.display_name = entry.display_name
		terrain.symbol = symbol
		terrain.walkable = entry.walkable
		terrains.append(terrain)
		terrains_by_id[id] = terrain
		by_symbol[symbol] = id
		keys[entry.key] = true
	return ""


func parse_arenas(root: Variant, footprint_radius: float) -> String:
	if not valid_root(root, "arenas") or root.arenas.is_empty() or root.arenas.size() > 65535:
		return "Arena catalog requires schema_version 1 and an arenas array."
	var keys: Dictionary = {}
	for entry: Variant in root.arenas:
		if not valid_identity(entry) or not integer_in(entry.get("width"), 3, 128) or not integer_in(entry.get("height"), 3, 128) or not integer_in(entry.get("tile_size"), 16, 128):
			return "An arena needs a valid identity, 3–128 cells per side, and 16–128 unit tiles."
		if not entry.get("rows") is Array or entry.rows.size() != int(entry.height) or not entry.get("spawns") is Array or entry.spawns.size() != 2:
			return "An arena needs one row per map row and two spawn cells."
		var id := int(entry.id)
		if arenas_by_id.has(id) or keys.has(entry.key):
			return "Arena IDs and keys must be unique."
		var arena := ArenaDefinition.new()
		arena.id = id
		arena.key = entry.key
		arena.display_name = entry.display_name
		arena.width = int(entry.width)
		arena.height = int(entry.height)
		arena.tile_size = int(entry.tile_size)
		for row: Variant in entry.rows:
			if not row is String or row.length() != arena.width:
				return "Arena %s has an invalid row length." % arena.key
			for symbol in row:
				if not by_symbol.has(symbol):
					return "Arena %s contains unknown terrain '%s'." % [arena.key, symbol]
				arena.cells.append(by_symbol[symbol])
		for spawn: Variant in entry.spawns:
			if not spawn is Array or spawn.size() != 2 or not integer_in(spawn[0], 0, arena.width - 1) or not integer_in(spawn[1], 0, arena.height - 1):
				return "Arena %s has an invalid spawn cell." % arena.key
			var cell := Vector2i(int(spawn[0]), int(spawn[1]))
			if not spawn_is_clear(arena, cell, footprint_radius):
				return "Arena %s has a blocked spawn or insufficient character clearance." % arena.key
			arena.spawns.append(cell)
		if arena.spawns[0] == arena.spawns[1] or arena.cell_center(arena.spawns[0]).distance_to(arena.cell_center(arena.spawns[1])) < 2 * footprint_radius:
			return "Arena %s has overlapping player spawns." % arena.key
		arenas.append(arena)
		arenas_by_id[id] = arena
		keys[arena.key] = true
	return ""


func is_blocked(arena: ArenaDefinition, cell: Vector2i) -> bool:
	var terrain: TerrainDefinition = terrains_by_id.get(arena.terrain_id_at(cell))
	return terrain == null or not terrain.walkable


func spawn_is_clear(arena: ArenaDefinition, cell: Vector2i, radius: float) -> bool:
	if is_blocked(arena, cell):
		return false
	return position_is_clear(arena, arena.cell_center(cell), radius)


func position_is_clear(arena: ArenaDefinition, center: Vector2, radius: float) -> bool:
	if center.x - radius < 0 or center.y - radius < 0 or center.x + radius > arena.width * arena.tile_size or center.y + radius > arena.height * arena.tile_size:
		return false
	var minimum := arena.world_to_cell(center - Vector2.ONE * radius)
	var maximum := arena.world_to_cell(center + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			if not is_blocked(arena, Vector2i(x, y)):
				continue
			var nearest := center.clamp(Vector2(x, y) * arena.tile_size, Vector2(x + 1, y + 1) * arena.tile_size)
			if center.distance_squared_to(nearest) < radius * radius:
				return false
	return true


static func integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))


static func valid_root(value: Variant, field: String) -> bool:
	return value is Dictionary and integer_in(value.get("schema_version"), 1, 1) and value.get(field) is Array


static func valid_identity(entry: Variant) -> bool:
	if not entry is Dictionary or not integer_in(entry.get("id"), 1, 65535) or not entry.get("key") is String or not entry.get("display_name") is String:
		return false
	if entry.key.is_empty() or entry.display_name.strip_edges().is_empty():
		return false
	for character in entry.key:
		if not (character >= "a" and character <= "z" or character >= "0" and character <= "9" or character == "_"):
			return false
	return true
