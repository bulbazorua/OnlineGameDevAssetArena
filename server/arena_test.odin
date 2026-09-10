package main

import "core:testing"

@(test)
arena_content_and_coordinate_fixture :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "tests/fixtures/content"))
    defer content_destroy(&content)
    expected := [32]u8{0xa7, 0xf4, 0x28, 0x37, 0x58, 0x93, 0x3a, 0x70, 0x83, 0x0e, 0xd2, 0xdc, 0xea, 0x06, 0x13, 0xda, 0x8a, 0x93, 0x88, 0x6d, 0x4b, 0x34, 0x20, 0xd5, 0x51, 0x9c, 0xad, 0x16, 0x9f, 0xcb, 0xed, 0x92}
    testing.expect(t, content.fingerprint == expected)
    arena := content_arena(&content, 1)
    testing.expect(t, arena != nil && len(arena.cells) == 12)
    testing.expect(t, arena_cell_center(arena, {1, 1}) == [2]f32{48, 48})
    testing.expect(t, arena_cell_center(arena, {2, 1}) == [2]f32{80, 48})
    testing.expect(t, arena_world_to_cell(arena, {-0.1, 0}) == [2]int{-1, 0})
    testing.expect(t, arena_terrain_id(arena, {1, 1}) == 1 && arena_terrain_id(arena, {0, 0}) == 5)
    testing.expect(t, arena_cell_is_blocked(arena, &content, {-1, 1}) && arena_cell_is_blocked(arena, &content, {0, 0}))
    testing.expect(t, arena_spawn_is_clear(arena, &content, {1, 1}, 16))
    testing.expect(t, !arena_spawn_is_clear(arena, &content, {1, 1}, 17))
}

@(test)
arena_rejects_invalid_cells_dimensions_and_spawns :: proc(t: ^testing.T) {
    terrain_json := `{"schema_version":1,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true},{"id":5,"key":"stone","display_name":"Stone","symbol":"#","walkable":false}]}`
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
        content: Game_Content
        testing.expect(t, content_parse(&content, transmute([]u8)string(CONTENT_FIXTURE)))
        testing.expect(t, content_parse_extra(&content, transmute([]u8)terrain_json, .Terrains))
        testing.expect(t, !content_parse_extra(&content, transmute([]u8)invalid, .Arenas), invalid)
        content_destroy(&content)
    }
}

@(test)
arena_selection_authority_and_ready_invalidation :: proc(t: ^testing.T) {
    content: Game_Content
    append(&content.characters, Character_Definition{id = 1})
    append(&content.arenas, Arena_Definition{id = 1}, Arena_Definition{id = 2})
    defer delete(content.characters)
    defer delete(content.arenas)
    session: Session
    session_join(&session, false)
    session_join(&session, false)
    session_apply(&session, &content, 1, {kind = .Start_Selection})
    for player in u8(1)..=2 {
        session_apply(&session, &content, player, {kind = .Select_Character, round_id = 1, character_id = 1})
        session_apply(&session, &content, player, {kind = .Set_Ready, round_id = 1, character_id = 1, map_id = 1, ready = player == 1})
    }
    testing.expect(t, session.players[0].ready && !session.players[1].ready)
    _, reason := session_apply(&session, &content, 0, {kind = .Select_Arena, round_id = 1, map_id = 2})
    testing.expect(t, reason == .Audience_Read_Only && session.map_id == 1)
    _, reason = session_apply(&session, &content, 1, {kind = .Select_Arena, round_id = 1, map_id = 65535})
    testing.expect(t, reason == .Unknown_Arena && session.players[0].ready)
    changed, rejection := session_apply(&session, &content, 2, {kind = .Select_Arena, round_id = 1, map_id = 2})
    testing.expect(t, changed && rejection == .None && session.map_id == 2 && session.round_id == 2)
    testing.expect(t, session.players[0].character_id == 1 && session.players[1].character_id == 1 && !session.players[0].ready && !session.players[1].ready)
    revision := session.revision
    changed, rejection = session_apply(&session, &content, 2, {kind = .Select_Arena, round_id = 2, map_id = 2})
    testing.expect(t, !changed && rejection == .None && session.revision == revision && session.round_id == 2)
    _, reason = session_apply(&session, &content, 1, {kind = .Set_Ready, round_id = 1, character_id = 1, map_id = 1, ready = true})
    testing.expect(t, reason == .Stale_Round)
    _, reason = session_apply(&session, &content, 1, {kind = .Set_Ready, round_id = 2, character_id = 1, map_id = 1, ready = true})
    testing.expect(t, reason == .Arena_Changed)
    session_apply(&session, &content, 1, {kind = .Select_Arena, round_id = 2, map_id = 1})
    session_apply(&session, &content, 1, {kind = .Select_Arena, round_id = 3, map_id = 2})
    _, reason = session_apply(&session, &content, 1, {kind = .Set_Ready, round_id = 2, character_id = 1, map_id = 2, ready = true})
    testing.expect(t, reason == .Stale_Round && !session.players[0].ready)
    session_leave(&session, 2)
    testing.expect(t, session.map_id == 0 && session.phase == .Lobby)
}

@(test)
arena_command_wire_fixtures :: proc(t: ^testing.T) {
    request := [12]u8{'O', 'G', 'A', 'A', 6, 9, 1, 2, 3, 4, 2, 0}
    command, valid := protocol_decode(request[:], 0)
    testing.expect(t, valid && command.kind == .Select_Arena && command.round_id == 0x04030201 && command.map_id == 2)
    ready := [15]u8{'O', 'G', 'A', 'A', 6, 6, 1, 2, 3, 4, 4, 0, 2, 0, 1}
    command, valid = protocol_decode(ready[:], 0)
    testing.expect(t, valid && command.kind == .Set_Ready && command.character_id == 4 && command.map_id == 2 && command.ready)
    for length in 0..<len(ready) {
        _, accepted := protocol_decode(ready[:length], 0)
        testing.expect(t, !accepted)
    }
    ready[14] = 2
    _, accepted := protocol_decode(ready[:], 0)
    testing.expect(t, !accepted)
}
