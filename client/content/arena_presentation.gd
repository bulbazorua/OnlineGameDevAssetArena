class_name ArenaPresentation
extends RefCounted

const ArenaCatalog = preload("res://content/arena_catalog.gd")
const AssetScale = preload("res://presentation/asset_scale.gd")

var theme := "ninja_adventure"
var props: Array[Dictionary] = []


func load_definition(arena: ArenaCatalog.ArenaDefinition, catalog: ArenaCatalog) -> String:
	var path := "res://content/presentation/arenas/%s.json" % arena.key
	if not FileAccess.file_exists(path):
		for id in arena.cells:
			if catalog.terrains_by_id[id].key == "building":
				return "Building terrain requires an arena presentation: %s" % path
		return ""
	var root = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not root is Dictionary or root.get("schema_version") != 1 or root.get("terrain_theme") != "tiny_swords" or not root.get("props") is Array:
		return "Invalid arena presentation: %s" % path
	theme = root.terrain_theme
	var keys: Dictionary = {}
	var covered: Dictionary = {}
	for entry: Variant in root.props:
		if not entry is Dictionary or not entry.get("key") is String or entry.key.is_empty() or keys.has(entry.key) or not entry.get("texture") is String or not entry.texture.begins_with("res://assets/tiny_swords/") or ".." in entry.texture:
			return "Each static prop needs a unique key and a Tiny Swords texture."
		keys[entry.key] = true
		for field in ["reference_span_px", "gameplay_size"]:
			var value: Variant = entry.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or value <= 0:
				return "Prop %s has invalid %s." % [entry.key, field]
		if not entry.get("footprint_cells") is Array or entry.footprint_cells.size() != 4 or not entry.get("foot_anchor_px") is Array or entry.foot_anchor_px.size() != 2:
			return "A prop needs a cell footprint and source foot anchor."
		var values: Array = entry.footprint_cells
		for value: Variant in values:
			if not ArenaCatalog.integer_in(value, 0, 128): return "Invalid building footprint."
		var footprint := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
		if footprint.size.x == 0 or footprint.size.y == 0 or not Rect2i(0, 0, arena.width, arena.height).encloses(footprint):
			return "Building footprint lies outside the arena."
		if not ResourceLoader.exists(entry.texture):
			return "Missing Tiny Swords art. Run make import_tiny_swords, then import the Godot project."
		var texture = load(entry.texture)
		if not texture is Texture2D: return "Invalid building texture."
		for axis in 2:
			var value: Variant = entry.foot_anchor_px[axis]
			if not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value > texture.get_size()[axis]: return "Invalid building foot anchor."
		var scale := AssetScale.factor(entry.reference_span_px, entry.gameplay_size)
		if not is_finite(scale) or scale <= 0 or not is_finite(texture.get_width() * scale):
			return "Invalid building scale."
		if ceili(texture.get_width() * scale / arena.tile_size) != footprint.size.x:
			return "Building visual width and shared footprint disagree; regenerate the map after sizing edits."
		for y in range(footprint.position.y, footprint.end.y):
			for x in range(footprint.position.x, footprint.end.x):
				var cell := Vector2i(x, y)
				var terrain: ArenaCatalog.TerrainDefinition = catalog.terrains_by_id.get(arena.terrain_id_at(cell))
				if terrain == null or terrain.key != "building" or terrain.walkable or covered.has(cell) or arena.elevation_at(cell) != arena.elevation_at(footprint.position):
					return "Building footprints must match non-overlapping blocked building cells at one elevation."
				covered[cell] = true
		props.append({"key": entry.key, "texture": texture, "scale": scale, "footprint": footprint,
			"anchor": Vector2(entry.foot_anchor_px[0], entry.foot_anchor_px[1]),
			"position": Vector2(footprint.position.x + footprint.size.x * 0.5, footprint.end.y) * arena.tile_size})
	for y in arena.height:
		for x in arena.width:
			var cell := Vector2i(x, y)
			if catalog.terrains_by_id[arena.terrain_id_at(cell)].key == "building" and not covered.has(cell):
				return "A blocked building cell has no visible building."
	return ""
