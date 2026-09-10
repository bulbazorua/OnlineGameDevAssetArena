extends SceneTree

const GameContent = preload("res://content/game_content.gd")
const GameProtocol = preload("res://network/protocol.gd")
const ArenaCatalog = preload("res://content/arena_catalog.gd")
const Movement = preload("res://world/character_movement.gd")
const WORLD_SCENE = preload("res://world/arena_world.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var content := GameContent.new()
	var fixture_path := ProjectSettings.globalize_path("res://../tests/fixtures/content")
	_expect(content.load_catalog(fixture_path).is_empty(), "Shared content fixture failed to load.")
	var digest := FileAccess.get_file_as_string(fixture_path.get_base_dir().path_join("content.sha256")).strip_edges()
	_expect(content.fingerprint.hex_encode() == digest, "Full content fingerprint differs from Python/Odin fixture.")
	var fixture: ArenaCatalog.ArenaDefinition = content.arena_catalog.arenas[0]
	_expect(fixture.cell_center(Vector2i(1, 1)) == Vector2(48, 48), "Spawn center mismatch.")
	_expect(fixture.world_to_cell(Vector2(-0.1, 0)) == Vector2i(-1, 0), "Negative world coordinate truncated instead of floored.")
	_expect(content.arena_catalog.is_blocked(fixture, Vector2i(-1, 0)), "Outside map should be blocked.")
	_expect(content.arena_catalog.spawn_is_clear(fixture, Vector2i(1, 1), 16) and not content.arena_catalog.spawn_is_clear(fixture, Vector2i(1, 1), 17), "Spawn clearance against adjacent walls is wrong.")
	_check_invalid_definitions(fixture_path)
	_check_elevation(fixture_path)
	_expect(content.load_catalog().is_empty(), "Shipped arenas failed to load.")
	_expect(content.arena_catalog.arenas.size() == 4 and content.arena_catalog.terrains.size() == 10, "Expected four arenas and ten terrain types.")
	var world = WORLD_SCENE.instantiate()
	root.add_child(world)
	var seen: Dictionary = {}
	for arena in content.arena_catalog.arenas:
		_expect(arena.width == 60 and arena.height == 28 and arena.tile_size == 32, "Arena must contain six times the original area.")
		world.load_arena(content, arena)
		world.terrain_layer.update_internals()
		_expect(world.terrain_layer.get_used_cells().size() == arena.width * arena.height, "A map contains missing rendered cells.")
		for y in arena.height:
			for x in arena.width:
				var cell := Vector2i(x, y)
				var terrain: ArenaCatalog.TerrainDefinition = content.arena_catalog.terrains_by_id[arena.terrain_id_at(cell)]
				var data: TileData = world.terrain_layer.get_cell_tile_data(cell)
				_expect(data != null and data.get_custom_data("terrain_id") == terrain.id and data.get_custom_data("terrain_key") == terrain.key and data.get_custom_data("walkable") == terrain.walkable, "Rendered tile metadata differs from shared terrain data.")
				_expect(data != null and data.get_custom_data("elevation") == arena.elevation_at(cell), "Rendered elevation differs from shared map data.")
				seen[terrain.id] = true
		for spawn in arena.spawns:
			var center: Vector2 = world.to_local(world.terrain_layer.to_global(world.terrain_layer.map_to_local(spawn)))
			_expect(center.is_equal_approx(arena.cell_center(spawn)), "TileMapLayer center differs from shared world coordinates.")
	_expect(seen.size() == 10, "Shipped maps do not demonstrate every terrain type.")
	world.queue_free()
	await process_frame
	_expect(GameProtocol.encode_command(GameProtocol.MessageKind.SELECT_ARENA, 0x04030201, 0, false, 2) == PackedByteArray([79, 71, 65, 65, 9, 9, 1, 2, 3, 4, 2, 0]), "SelectArena bytes differ from Odin.")
	_expect(GameProtocol.encode_command(GameProtocol.MessageKind.SET_READY, 0x04030201, 4, true, 2) == PackedByteArray([79, 71, 65, 65, 9, 6, 1, 2, 3, 4, 4, 0, 2, 0, 1]), "SetReady bytes differ from Odin.")
	if failures.is_empty():
		print("PASS: full content digest, terrain/map validation, all 6720 rendered cells, terrain/elevation metadata, coordinates, spawn clearance, and arena command fixtures.")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check_invalid_definitions(directory: String) -> void:
	var terrain_root: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("terrains.json")))
	var arena_root: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("arenas.json")))
	for mutation in [["id", 0], ["width", 129], ["height", 3.5], ["tile_size", 0], ["rows", ["####", "#x.#", "####"]], ["rows", ["####", "...", "####"]], ["spawns", [[0, 0], [2, 1]]], ["spawns", [[1, 1], [1, 1]]], ["spawns", [[-1, 1], [2, 1]]]]:
		var catalog := ArenaCatalog.new()
		_expect(catalog.parse_terrains(terrain_root).is_empty(), "Terrain test fixture failed.")
		var invalid := arena_root.duplicate(true)
		invalid.arenas[0][mutation[0]] = mutation[1]
		_expect(not catalog.parse_arenas(invalid, 12).is_empty(), "Invalid map was accepted: " + str(mutation))
	for mutation in [["id", 0], ["key", "../grass"], ["symbol", ".."], ["walkable", 1]]:
		var catalog := ArenaCatalog.new()
		var invalid := terrain_root.duplicate(true)
		invalid.terrains[0][mutation[0]] = mutation[1]
		_expect(not catalog.parse_terrains(invalid).is_empty(), "Invalid terrain was accepted.")
	var duplicates := terrain_root.duplicate(true)
	duplicates.terrains.append(duplicates.terrains[0].duplicate())
	_expect(not ArenaCatalog.new().parse_terrains(duplicates).is_empty(), "Duplicate terrain was accepted.")

func _expect(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)


func _check_elevation(directory: String) -> void:
	var terrains: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("terrains.json")))
	var maps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("arenas.json")))
	maps.schema_version = 2
	for rows: Variant in [null, ["0000"], ["0000", "000", "0000"], ["0000", "0040", "0000"], ["0000", "00x0", "0000"], ["0000", 12, "0000"]]:
		var catalog := ArenaCatalog.new()
		catalog.parse_terrains(terrains)
		maps.arenas[0].elevation_rows = rows
		_expect(not catalog.parse_arenas(maps, 12).is_empty(), "Invalid elevation rows were accepted.")
	maps.arenas[0].elevation_rows = ["0000", "0010", "0000"]
	var catalog := ArenaCatalog.new()
	catalog.parse_terrains(terrains)
	_expect(catalog.parse_arenas(maps, 12).is_empty(), "Valid elevation map failed.")
	var arena: ArenaCatalog.ArenaDefinition = catalog.arenas[0]
	_expect(Movement.move(Vector2(63,48), 2, 12, arena, catalog) == Vector2(63,48), "Walked onto high ground without stairs.")
	catalog.terrains_by_id[arena.cells[6]].key = "stairs"
	_expect(Movement.move(Vector2(63,48), 2, 12, arena, catalog) == Vector2(65,48), "Stairs did not permit climbing.")
	_expect(catalog.step_is_allowed(arena, Vector2(80,48), Vector2(48,48)), "Stairs did not permit descending.")
	arena.elevations[6] = 2
	_expect(not catalog.step_is_allowed(arena, Vector2(48,48), Vector2(80,48)), "Stairs skipped multiple elevation levels.")
