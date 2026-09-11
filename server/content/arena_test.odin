package content

import "core:testing"

@(test)
arena_content_and_coordinate_fixture :: proc(t: ^testing.T) {
    catalog: Game_Content
    testing.expect(t, load(&catalog, "tests/fixtures/content"))
    defer destroy(&catalog)
    expected := [32]u8{0xd7, 0xa0, 0x53, 0x7c, 0xdf, 0xb3, 0x69, 0xd6, 0xe9, 0xd3, 0x61, 0xff, 0x53, 0xf2, 0x96, 0x33, 0xb0, 0x25, 0x5d, 0x45, 0x11, 0xee, 0xc9, 0xaf, 0x95, 0x4b, 0x31, 0x03, 0x08, 0x56, 0xaa, 0x41} // tests/fixtures/catalog.sha256, computed independently in Python
    testing.expect(t, catalog.fingerprint == expected)
    arena := find_arena(&catalog, 1)
    testing.expect(t, arena != nil && len(arena.cells) == 12)
    testing.expect(t, arena_cell_center(arena, {1, 1}) == [2]f32{48, 48})
    testing.expect(t, arena_cell_center(arena, {2, 1}) == [2]f32{80, 48})
    testing.expect(t, arena_world_to_cell(arena, {-0.1, 0}) == [2]int{-1, 0})
    testing.expect(t, arena_terrain_id(arena, {1, 1}) == 1 && arena_terrain_id(arena, {0, 0}) == 5)
    testing.expect(t, arena_cell_is_blocked(arena, &catalog, {-1, 1}) && arena_cell_is_blocked(arena, &catalog, {0, 0}))
    testing.expect(t, arena_spawn_is_clear(arena, &catalog, {1, 1}, 16))
    testing.expect(t, !arena_spawn_is_clear(arena, &catalog, {1, 1}, 17))
    testing.expect(t, catalog.characters[0].sense_profile == "starter_senses" && catalog.characters[0].vision == {true, 256, 60, 160, 6})
}

@(test)
sight_blocking_is_baked_independently_of_walkability :: proc(t: ^testing.T) {
    catalog: Game_Content
    testing.expect(t, load(&catalog, "client/content/data"))
    defer destroy(&catalog)
    opaque_keys := [?]string{"stone", "cliff", "forest", "building"}
    for terrain in catalog.terrains {
        expected := false
        for key in opaque_keys { if key == terrain.key { expected = true } }
        testing.expectf(t, terrain.blocks_vision == expected, "%s opacity", terrain.key)
    }
    arena := find_arena(&catalog, 4)
    grid := arena_opacity_grid(arena)
    testing.expect(t, grid.width == 60 && grid.height == 28 && grid.tile_size == 32 && len(grid.opaque) == 1680)
    water, forest, building, grass := [2]int{14, 21}, [2]int{0, 0}, [2]int{6, 8}, [2]int{12, 14}
    testing.expect(t, find_terrain(&catalog, arena_terrain_id(arena, water)).key == "water" && arena_cell_is_blocked(arena, &catalog, water) && !arena_cell_blocks_sight(arena, &catalog, water))
    testing.expect(t, arena_cell_blocks_sight(arena, &catalog, forest) && arena_cell_blocks_sight(arena, &catalog, building) && !arena_cell_blocks_sight(arena, &catalog, grass))
    testing.expect(t, grid.opaque[water.y * 60 + water.x] == false && grid.opaque[building.y * 60 + building.x] && grid.opaque[grass.y * 60 + grass.x] == false)
    testing.expect(t, arena_cell_blocks_sight(arena, &catalog, {-1, 0}) && arena_cell_blocks_sight(arena, &catalog, {60, 0}))
    arena.cells[grass.y * 60 + grass.x] = 5
    testing.expect(t, !grid.opaque[grass.y * 60 + grass.x], "opacity is baked, not live")
    arena_refresh_rules(arena, &catalog)
    testing.expect(t, grid.opaque[grass.y * 60 + grass.x])
}

@(test)
arena_rejects_invalid_cells_dimensions_and_spawns :: proc(t: ^testing.T) {
    terrain_json := `{"schema_version":3,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"blocks_vision":false,"scent":"open"},{"id":5,"key":"stone","display_name":"Stone","symbol":"#","walkable":false,"blocks_vision":true,"scent":"solid"}]}`
    for invalid in ([]string{
        `{"schema_version":1,"arenas":[{"id":0,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":129,"height":3,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3.5,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":0,"rows":["####","#..#","####"],"spawns":[[1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","#x.#","####"],"spawns":[[1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","...","####"],"spawns":[[1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[0,0],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[1,1],[1,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[-1,1],[2,1]]}]}`,
        `{"schema_version":1,"arenas":[{"id":1,"key":"fixture","display_name":"Fixture","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"spawns":[[1.5,1],[2,1]]}]}`,
    }) {
        catalog: Game_Content
        testing.expect(t, parse_characters(&catalog, transmute([]u8)string(CONTENT_FIXTURE)))
        testing.expect(t, parse_extra(&catalog, transmute([]u8)terrain_json, .Terrains))
        testing.expect(t, !parse_extra(&catalog, transmute([]u8)invalid, .Arenas), invalid)
        destroy(&catalog)
    }
}

