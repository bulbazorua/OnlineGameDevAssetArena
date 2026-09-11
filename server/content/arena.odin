package content

import "core:encoding/json"
import "core:math"
import "core:strings"
import "../perception"

// Walkability, sight blocking and scent behaviour are independent gameplay
// rules: each is authored per terrain, never derived from another.
Terrain_Definition :: struct {
    id: u16,
    key, display_name: string,
    symbol: u8,
    walkable: bool,
    blocks_vision: bool,
    scent: perception.Scent_Medium,
}

@(private)
scent_medium_from_key :: proc(key: string) -> (perception.Scent_Medium, bool) {
    switch key {
    case "open": return .Open, true
    case "water": return .Water, true
    case "solid": return .Solid, true
    }
    return .Solid, false
}

Arena_Definition :: struct {
    id: u16,
    key, display_name: string,
    width, height, tile_size: int,
    cells: []u16, // Terrain IDs, row-major. No renderer-specific tile indices.
    elevations: []u8, // Discrete land levels; stairs connect adjacent levels.
    opaque: []bool, // Planar sight blocking per cell, baked from terrain at load.
    scent_media: []perception.Scent_Medium, // How each cell holds scent, baked from terrain at load.
    spawns: [2][2]int,
}

// Borrowed: valid until destroy. Callers read definitions; only test fixtures write through them.
find_terrain :: proc(catalog: ^Game_Content, id: u16) -> ^Terrain_Definition {
    for &terrain in catalog.terrains { if terrain.id == id { return &terrain } }
    return nil
}

find_arena :: proc(catalog: ^Game_Content, id: u16) -> ^Arena_Definition {
    for &arena in catalog.arenas { if arena.id == id { return &arena } }
    return nil
}

arena_terrain_id :: proc(arena: ^Arena_Definition, cell: [2]int) -> u16 {
    if cell.x < 0 || cell.y < 0 || cell.x >= arena.width || cell.y >= arena.height { return 0 }
    return arena.cells[cell.y * arena.width + cell.x]
}

arena_cell_is_blocked :: proc(arena: ^Arena_Definition, catalog: ^Game_Content, cell: [2]int) -> bool {
    terrain := find_terrain(catalog, arena_terrain_id(arena, cell))
    return terrain == nil || !terrain.walkable
}

arena_cell_blocks_sight :: proc(arena: ^Arena_Definition, catalog: ^Game_Content, cell: [2]int) -> bool {
    terrain := find_terrain(catalog, arena_terrain_id(arena, cell))
    return terrain == nil || terrain.blocks_vision
}

@(private)
arena_cell_scent_medium :: proc(arena: ^Arena_Definition, catalog: ^Game_Content, cell: [2]int) -> perception.Scent_Medium {
    terrain := find_terrain(catalog, arena_terrain_id(arena, cell))
    return .Solid if terrain == nil else terrain.scent
}

// Rebuild the baked per-cell rules after cells change (content load or a test fixture).
arena_refresh_rules :: proc(arena: ^Arena_Definition, catalog: ^Game_Content) {
    for y in 0..<arena.height {
        for x in 0..<arena.width {
            index := y * arena.width + x
            arena.opaque[index] = arena_cell_blocks_sight(arena, catalog, {x, y})
            arena.scent_media[index] = arena_cell_scent_medium(arena, catalog, {x, y})
        }
    }
}

// Read-only view over the arena's own opaque cells, valid as long as the catalog is.
// Elevation is deliberately absent: opaque cells block at every height and height alone never occludes.
arena_opacity_grid :: proc(arena: ^Arena_Definition) -> perception.Opacity_Grid {
    return {width = arena.width, height = arena.height, tile_size = f32(arena.tile_size), opaque = arena.opaque}
}

arena_cell_center :: proc(arena: ^Arena_Definition, cell: [2]int) -> [2]f32 {
    return {(f32(cell.x) + 0.5) * f32(arena.tile_size), (f32(cell.y) + 0.5) * f32(arena.tile_size)}
}

arena_world_to_cell :: proc(arena: ^Arena_Definition, position: [2]f32) -> [2]int {
    return {int(math.floor(position.x / f32(arena.tile_size))), int(math.floor(position.y / f32(arena.tile_size)))}
}

arena_elevation_at :: proc(arena: ^Arena_Definition, cell: [2]int) -> int {
    if arena_terrain_id(arena, cell) == 0 { return -1 }
    if len(arena.elevations) == 0 { return 0 }
    return int(arena.elevations[cell.y * arena.width + cell.x])
}

arena_step_is_allowed :: proc(arena: ^Arena_Definition, catalog: ^Game_Content, from, to: [2]f32) -> bool {
    a, b := arena_world_to_cell(arena, from), arena_world_to_cell(arena, to)
    height_a, height_b := arena_elevation_at(arena, a), arena_elevation_at(arena, b)
    if height_a == height_b { return true }
    first, second := find_terrain(catalog, arena_terrain_id(arena, a)), find_terrain(catalog, arena_terrain_id(arena, b))
    return first != nil && second != nil && abs(height_a - height_b) == 1 && (first.key == "stairs" || second.key == "stairs")
}

// Spawn validation and movement use the same circular footprint.
arena_spawn_is_clear :: proc(arena: ^Arena_Definition, catalog: ^Game_Content, cell: [2]int, radius: f32) -> bool {
    if arena_cell_is_blocked(arena, catalog, cell) { return false }
    return arena_position_is_clear(arena, catalog, arena_cell_center(arena, cell), radius)
}

arena_position_is_clear :: proc(arena: ^Arena_Definition, catalog: ^Game_Content, center: [2]f32, radius: f32) -> bool {
    if center.x - radius < 0 || center.y - radius < 0 || center.x + radius > f32(arena.width * arena.tile_size) || center.y + radius > f32(arena.height * arena.tile_size) { return false }
    minimum := arena_world_to_cell(arena, center - [2]f32{radius, radius})
    maximum := arena_world_to_cell(arena, center + [2]f32{radius, radius})
    for y in minimum.y..=maximum.y {
        for x in minimum.x..=maximum.x {
            if !arena_cell_is_blocked(arena, catalog, {x, y}) { continue }
            nearest := [2]f32{clamp(center.x, f32(x * arena.tile_size), f32((x + 1) * arena.tile_size)), clamp(center.y, f32(y * arena.tile_size), f32((y + 1) * arena.tile_size))}
            delta := center - nearest
            if delta.x * delta.x + delta.y * delta.y < radius * radius { return false }
        }
    }
    return true
}

@(private)
key_is_valid :: proc(key: string) -> bool {
    if len(key) == 0 { return false }
    for character in key {
        if !(character >= 'a' && character <= 'z' || character >= '0' && character <= '9' || character == '_') { return false }
    }
    return true
}

@(private)
parse_terrains :: proc(catalog: ^Game_Content, root: json.Object) -> bool {
    entries, ok := root["terrains"].(json.Array)
    if !ok || len(entries) == 0 || len(entries) > 94 { return false }
    for entry in entries {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        id, id_ok := json_integer(fields["id"])
        key, key_ok := fields["key"].(json.String)
        name, name_ok := fields["display_name"].(json.String)
        symbol, symbol_ok := fields["symbol"].(json.String)
        walkable, walkable_ok := fields["walkable"].(json.Boolean)
        blocks_vision, blocks_ok := fields["blocks_vision"].(json.Boolean)
        scent_key, scent_key_ok := fields["scent"].(json.String)
        if !id_ok || id < 1 || id > 65535 || !key_ok || !key_is_valid(string(key)) || !name_ok || len(strings.trim_space(string(name))) == 0 || !symbol_ok || len(symbol) != 1 || symbol[0] < 33 || symbol[0] > 126 || !walkable_ok || !blocks_ok || !scent_key_ok { return false }
        scent, scent_ok := scent_medium_from_key(string(scent_key))
        if !scent_ok { return false }
        for previous in catalog.terrains {
            if previous.id == u16(id) || previous.key == string(key) || previous.symbol == symbol[0] { return false }
        }
        append(&catalog.terrains, Terrain_Definition{u16(id), strings.clone(string(key)), strings.clone(string(name)), symbol[0], bool(walkable), bool(blocks_vision), scent})
    }
    return true
}

@(private)
parse_arenas :: proc(catalog: ^Game_Content, root: json.Object) -> bool {
    entries, ok := root["arenas"].(json.Array)
    if !ok || len(entries) == 0 || len(entries) > 65535 { return false }
    symbols: [128]u16
    for terrain in catalog.terrains { symbols[terrain.symbol] = terrain.id }
    radius: f32
    for character in catalog.characters { radius = max(radius, character.footprint_radius) }
    for entry in entries {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        id, id_ok := json_integer(fields["id"])
        key, key_ok := fields["key"].(json.String)
        name, name_ok := fields["display_name"].(json.String)
        width, width_ok := json_integer(fields["width"])
        height, height_ok := json_integer(fields["height"])
        tile_size, size_ok := json_integer(fields["tile_size"])
        rows, rows_ok := fields["rows"].(json.Array)
        spawns, spawns_ok := fields["spawns"].(json.Array)
        if !id_ok || id < 1 || id > 65535 || !key_ok || !key_is_valid(string(key)) || !name_ok || len(strings.trim_space(string(name))) == 0 || !width_ok || width < 3 || width > perception.MAX_GRID_SIDE || !height_ok || height < 3 || height > perception.MAX_GRID_SIDE || !size_ok || tile_size < 16 || tile_size > 128 || !rows_ok || len(rows) != int(height) || !spawns_ok || len(spawns) != 2 { return false }
        for previous in catalog.arenas { if previous.id == u16(id) || previous.key == string(key) { return false } }
        // Own allocations before parsing cells so a failed load can release everything.
        append(&catalog.arenas, Arena_Definition{id = u16(id), key = strings.clone(string(key)), display_name = strings.clone(string(name)), width = int(width), height = int(height), tile_size = int(tile_size), cells = make([]u16, int(width * height))})
        arena := &catalog.arenas[len(catalog.arenas) - 1]
        arena.elevations = make([]u8, arena.width * arena.height)
        arena.opaque = make([]bool, arena.width * arena.height)
        arena.scent_media = make([]perception.Scent_Medium, arena.width * arena.height)
        for row_value, y in rows {
            row, row_ok := row_value.(json.String)
            if !row_ok || len(row) != arena.width { return false }
            for x in 0..<arena.width {
                if row[x] >= 128 || symbols[row[x]] == 0 { return false }
                arena.cells[y * arena.width + x] = symbols[row[x]]
            }
        }
        if schema, _ := json_integer(root["schema_version"]); schema == 2 {
            heights, heights_ok := fields["elevation_rows"].(json.Array)
            if !heights_ok || len(heights) != arena.height { return false }
            for value, y in heights {
                row, valid := value.(json.String)
                if !valid || len(row) != arena.width { return false }
                for x in 0..<arena.width {
                    if row[x] < '0' || row[x] > '3' { return false }
                    arena.elevations[y * arena.width + x] = row[x] - '0'
                }
            }
        } else if _, exists := fields["elevation_rows"]; exists { return false }
        arena_refresh_rules(arena, catalog)
        for spawn_value, index in spawns {
            coordinates, coord_ok := spawn_value.(json.Array)
            if !coord_ok || len(coordinates) != 2 { return false }
            x, x_ok := json_integer(coordinates[0])
            y, y_ok := json_integer(coordinates[1])
            if !x_ok || !y_ok || x < 0 || x >= width || y < 0 || y >= height { return false }
            arena.spawns[index] = {int(x), int(y)}
            if !arena_spawn_is_clear(arena, catalog, arena.spawns[index], radius) { return false }
        }
        a := arena_cell_center(arena, arena.spawns[0])
        b := arena_cell_center(arena, arena.spawns[1])
        d := a - b
        if arena.spawns[0] == arena.spawns[1] || d.x * d.x + d.y * d.y < 4 * radius * radius { return false }
    }
    return true
}
