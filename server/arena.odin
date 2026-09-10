package main

import "core:encoding/json"
import "core:math"
import "core:strings"

Terrain_Definition :: struct {
    id: u16,
    key, display_name: string,
    symbol: u8,
    walkable: bool,
}

Arena_Definition :: struct {
    id: u16,
    key, display_name: string,
    width, height, tile_size: int,
    cells: []u16, // Terrain IDs, row-major. No renderer-specific tile indices.
    elevations: []u8, // Discrete land levels; stairs connect adjacent levels.
    spawns: [2][2]int,
}

content_terrain :: proc(content: ^Game_Content, id: u16) -> ^Terrain_Definition {
    for &terrain in content.terrains { if terrain.id == id { return &terrain } }
    return nil
}

content_arena :: proc(content: ^Game_Content, id: u16) -> ^Arena_Definition {
    for &arena in content.arenas { if arena.id == id { return &arena } }
    return nil
}

arena_terrain_id :: proc(arena: ^Arena_Definition, cell: [2]int) -> u16 {
    if cell.x < 0 || cell.y < 0 || cell.x >= arena.width || cell.y >= arena.height { return 0 }
    return arena.cells[cell.y * arena.width + cell.x]
}

arena_cell_is_blocked :: proc(arena: ^Arena_Definition, content: ^Game_Content, cell: [2]int) -> bool {
    terrain := content_terrain(content, arena_terrain_id(arena, cell))
    return terrain == nil || !terrain.walkable
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

arena_step_is_allowed :: proc(arena: ^Arena_Definition, content: ^Game_Content, from, to: [2]f32) -> bool {
    a, b := arena_world_to_cell(arena, from), arena_world_to_cell(arena, to)
    height_a, height_b := arena_elevation_at(arena, a), arena_elevation_at(arena, b)
    if height_a == height_b { return true }
    first, second := content_terrain(content, arena_terrain_id(arena, a)), content_terrain(content, arena_terrain_id(arena, b))
    return first != nil && second != nil && abs(height_a - height_b) == 1 && (first.key == "stairs" || second.key == "stairs")
}

// Spawn validation and movement use the same circular footprint.
arena_spawn_is_clear :: proc(arena: ^Arena_Definition, content: ^Game_Content, cell: [2]int, radius: f32) -> bool {
    if arena_cell_is_blocked(arena, content, cell) { return false }
    return arena_position_is_clear(arena, content, arena_cell_center(arena, cell), radius)
}

arena_position_is_clear :: proc(arena: ^Arena_Definition, content: ^Game_Content, center: [2]f32, radius: f32) -> bool {
    if center.x - radius < 0 || center.y - radius < 0 || center.x + radius > f32(arena.width * arena.tile_size) || center.y + radius > f32(arena.height * arena.tile_size) { return false }
    minimum := arena_world_to_cell(arena, center - [2]f32{radius, radius})
    maximum := arena_world_to_cell(arena, center + [2]f32{radius, radius})
    for y in minimum.y..=maximum.y {
        for x in minimum.x..=maximum.x {
            if !arena_cell_is_blocked(arena, content, {x, y}) { continue }
            nearest := [2]f32{clamp(center.x, f32(x * arena.tile_size), f32((x + 1) * arena.tile_size)), clamp(center.y, f32(y * arena.tile_size), f32((y + 1) * arena.tile_size))}
            delta := center - nearest
            if delta.x * delta.x + delta.y * delta.y < radius * radius { return false }
        }
    }
    return true
}

content_key_is_valid :: proc(key: string) -> bool {
    if len(key) == 0 { return false }
    for character in key {
        if !(character >= 'a' && character <= 'z' || character >= '0' && character <= '9' || character == '_') { return false }
    }
    return true
}

content_parse_terrains :: proc(content: ^Game_Content, root: json.Object) -> bool {
    entries, ok := root["terrains"].(json.Array)
    if !ok || len(entries) == 0 || len(entries) > 94 { return false }
    for entry in entries {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        id, id_ok := content_integer(fields["id"])
        key, key_ok := fields["key"].(json.String)
        name, name_ok := fields["display_name"].(json.String)
        symbol, symbol_ok := fields["symbol"].(json.String)
        walkable, walkable_ok := fields["walkable"].(json.Boolean)
        if !id_ok || id < 1 || id > 65535 || !key_ok || !content_key_is_valid(string(key)) || !name_ok || len(strings.trim_space(string(name))) == 0 || !symbol_ok || len(symbol) != 1 || symbol[0] < 33 || symbol[0] > 126 || !walkable_ok { return false }
        for previous in content.terrains {
            if previous.id == u16(id) || previous.key == string(key) || previous.symbol == symbol[0] { return false }
        }
        append(&content.terrains, Terrain_Definition{u16(id), strings.clone(string(key)), strings.clone(string(name)), symbol[0], bool(walkable)})
    }
    return true
}

content_parse_arenas :: proc(content: ^Game_Content, root: json.Object) -> bool {
    entries, ok := root["arenas"].(json.Array)
    if !ok || len(entries) == 0 || len(entries) > 65535 { return false }
    symbols: [128]u16
    for terrain in content.terrains { symbols[terrain.symbol] = terrain.id }
    radius: f32
    for character in content.characters { radius = max(radius, character.footprint_radius) }
    for entry in entries {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        id, id_ok := content_integer(fields["id"])
        key, key_ok := fields["key"].(json.String)
        name, name_ok := fields["display_name"].(json.String)
        width, width_ok := content_integer(fields["width"])
        height, height_ok := content_integer(fields["height"])
        tile_size, size_ok := content_integer(fields["tile_size"])
        rows, rows_ok := fields["rows"].(json.Array)
        spawns, spawns_ok := fields["spawns"].(json.Array)
        if !id_ok || id < 1 || id > 65535 || !key_ok || !content_key_is_valid(string(key)) || !name_ok || len(strings.trim_space(string(name))) == 0 || !width_ok || width < 3 || width > 128 || !height_ok || height < 3 || height > 128 || !size_ok || tile_size < 16 || tile_size > 128 || !rows_ok || len(rows) != int(height) || !spawns_ok || len(spawns) != 2 { return false }
        for previous in content.arenas { if previous.id == u16(id) || previous.key == string(key) { return false } }
        // Own allocations before parsing cells so a failed load can release everything.
        append(&content.arenas, Arena_Definition{id = u16(id), key = strings.clone(string(key)), display_name = strings.clone(string(name)), width = int(width), height = int(height), tile_size = int(tile_size), cells = make([]u16, int(width * height))})
        arena := &content.arenas[len(content.arenas) - 1]
        arena.elevations = make([]u8, arena.width * arena.height)
        for row_value, y in rows {
            row, row_ok := row_value.(json.String)
            if !row_ok || len(row) != arena.width { return false }
            for x in 0..<arena.width {
                if row[x] >= 128 || symbols[row[x]] == 0 { return false }
                arena.cells[y * arena.width + x] = symbols[row[x]]
            }
        }
        if schema, _ := content_integer(root["schema_version"]); schema == 2 {
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
        for spawn_value, index in spawns {
            coordinates, coord_ok := spawn_value.(json.Array)
            if !coord_ok || len(coordinates) != 2 { return false }
            x, x_ok := content_integer(coordinates[0])
            y, y_ok := content_integer(coordinates[1])
            if !x_ok || !y_ok || x < 0 || x >= width || y < 0 || y >= height { return false }
            arena.spawns[index] = {int(x), int(y)}
            if !arena_spawn_is_clear(arena, content, arena.spawns[index], radius) { return false }
        }
        a := arena_cell_center(arena, arena.spawns[0])
        b := arena_cell_center(arena, arena.spawns[1])
        d := a - b
        if arena.spawns[0] == arena.spawns[1] || d.x * d.x + d.y * d.y < 4 * radius * radius { return false }
    }
    return true
}
