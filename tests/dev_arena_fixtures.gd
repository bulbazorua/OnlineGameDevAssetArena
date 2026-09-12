extends RefCounted

# Fixture builders shared by the dev arena overview checks: a rectangular arena,
# one delivered eye and nose sample, a published scent field with a wake, and one
# private memory record. Expected colours are computed here, apart from the painter.
const Reader = preload("res://dev/ai/trace_reader.gd")
const HUMAN := Color("ffb454")
const ORC := Color("7de2b2")


static func arena(id: int, width: int, height: int, tile: int, name: String) -> ArenaCatalog.ArenaDefinition:
	var definition := ArenaCatalog.ArenaDefinition.new()
	definition.id = id
	definition.key = name.to_lower()
	definition.display_name = name
	definition.width = width
	definition.height = height
	definition.tile_size = tile
	return definition


static func vision_record(facing: String) -> Dictionary:
	var position := [100.0, 100.0]
	var sample := {"status": "Sampled", "observer": 3, "round_id": 5, "sample_id": 3, "sample_tick": 10, "delivered_tick": 12,
		"pose": {"position": position, "facing": facing},
		"profile": {"enabled": true, "range": 160.0, "focused_fov_degrees": 60.0, "overall_fov_degrees": 160.0, "sample_interval": 6},
		"focused_count": 1, "focused": [{"observation_id": 1, "subject": 5, "kind": "Creature", "appearance_id": 1, "position": [190.0, 100.0], "facing": "West", "locomotion": "Idle"}],
		"cue_count": 1, "cues": [{"observation_id": 2, "sector": 2, "band": "Far"}]}
	var fan := []
	var axis := Reader.facing_index(facing) * PI / 4.0 - PI / 2.0
	for index in 65:
		var angle := axis - deg_to_rad(80) + deg_to_rad(160) * index / 64.0
		fan.append([position[0] + cos(angle) * 160.0, position[1] + sin(angle) * 160.0])
	return {"owner_id": 1, "entity_id": 3, "round_id": 5, "tick": 20, "definition_id": 1, "map_id": 7, "delivered_us": 100,
		"vision": sample, "sight_fan": fan, "scent_delivered_us": 100, "olfaction": nose_sample(), "own_emitter": {"enabled": true, "class": "Human", "intensity": 1.0}}


static func nose_sample() -> Dictionary:
	var zones := []
	for zone in 16: zones.append("None")
	zones[4] = "Strong"
	zones[5] = "Medium"
	var coverage := []
	for zone in 16: coverage.append("Sampled" if zone < 12 else "Unsampled")
	var cleared := {"observation_id": 0, "class": "Orc", "strength": "None", "freshness": "Unknown", "bearing_valid": false, "bearing": "North", "zones": []}
	for zone in 16: cleared.zones.append("None")
	return {"status": "Sampled", "observer": 3, "round_id": 5, "sample_id": 7, "sample_tick": 12, "delivered_tick": 14, "position": [100.0, 100.0],
		"profile": {"enabled": true, "range": 256.0, "sample_interval": 12, "estimates_freshness": true},
		"reading_count": 1, "readings": [{"observation_id": 2147483657, "class": "Human", "strength": "Strong", "freshness": "Recent", "bearing_valid": true, "bearing": "East", "zones": zones}, cleared],
		"coverage": coverage, "cells_solid": 0, "cells_off_map": 0}


static func layer(cells: Dictionary, width: int, height: int, fill := 0) -> String:
	var bytes := PackedByteArray()
	bytes.resize(width * height)
	bytes.fill(fill)
	for cell: Vector2i in cells: bytes[cell.y * width + cell.x] = cells[cell]
	return Marshalls.raw_to_base64(bytes)


static func field_fixture(levels: Dictionary, ages: Dictionary, tick := 600, width := 30, height := 16, tile := 32.0, round_id := 5, map_id := 7) -> Dictionary:
	var layers := []
	var age_layers := []
	for scent_class in ["Human", "Orc"]:
		layers.append(layer(levels.get(scent_class, {}), width, height))
		age_layers.append(layer(ages.get(scent_class, {}), width, height, 255))
	return {"schema_version": 1, "run_id": "fixture", "fingerprint": "fp", "published_us": 0,
		"world": {"active": true, "round_id": round_id, "map_id": map_id, "entities": [3, 4]},
		"field": {"valid": true, "round_id": round_id, "tick": tick, "map_id": map_id, "width": width, "height": height, "tile_size": tile, "step_ticks": 6,
			"classes": ["Human", "Orc"], "levels": layers, "ages": age_layers}}


static func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


# Three lone human cells, an eleven-cell wake fading behind a walker, and two orc cells.
static func trail_levels() -> Dictionary:
	var human := {Vector2i(1, 1): 255, Vector2i(2, 3): 128, Vector2i(5, 5): 1}
	for step in 11: human[Vector2i(10 + step, 8)] = 255 - step * 20
	return {"Human": human, "Orc": {Vector2i(4, 2): 200, Vector2i(2, 3): 64}}


static func trail_ages() -> Dictionary:
	var human := {Vector2i(1, 1): 3, Vector2i(2, 3): 255, Vector2i(5, 5): 40}
	for step in 11: human[Vector2i(10 + step, 8)] = 10 - step
	return {"Human": human, "Orc": {Vector2i(4, 2): 12, Vector2i(2, 3): 7}}


static func memory_record() -> Dictionary:
	return {"owner_id": 1, "entity_id": 3, "round_id": 5, "map_id": 7, "tick": 3600,
		"search": {"position": [160, 96], "target": 999, "target_position": [9999, 9999], "visit_count": 3,
			"profile": {"region_size": 64, "memory_capacity": 16, "history_ticks": 3600}, "visits": [
				{"position": [64, 96], "visited_tick": 3600, "opponent_seen": false},
				{"position": [150, 110], "visited_tick": 1800, "opponent_seen": true},
				{"position": [320, 80], "visited_tick": 0, "opponent_seen": false},
				{"position": [9999, 9999], "visited_tick": 3600, "opponent_seen": true}]}}


# Expected colour of one field cell on a fixed alpha ramp, written apart from the painter.
static func expected_cell(human: int, orc: int, floor_alpha: float, max_alpha: float) -> Color:
	var lh := human / 255.0
	var lo := orc / 255.0
	var total := lh + lo
	if total <= 0: return Color(0, 0, 0, 0)
	var rgb := (Vector3(HUMAN.r, HUMAN.g, HUMAN.b) * lh + Vector3(ORC.r, ORC.g, ORC.b) * lo) / total
	return Color(rgb.x, rgb.y, rgb.z, floor_alpha + max_alpha * minf(total, 1.0))


# What a translucent cell looks like over the frame's ground, the way the screen blends it.
static func over_ground(cell: Color, ground: Color) -> Color:
	return Color(cell.r * cell.a + ground.r * (1.0 - cell.a), cell.g * cell.a + ground.g * (1.0 - cell.a), cell.b * cell.a + ground.b * (1.0 - cell.a), 1.0)


static func close(actual: Color, expected: Color, tolerance := 2.0 / 255.0) -> bool:
	return absf(actual.r - expected.r) <= tolerance and absf(actual.g - expected.g) <= tolerance and absf(actual.b - expected.b) <= tolerance and absf(actual.a - expected.a) <= tolerance
