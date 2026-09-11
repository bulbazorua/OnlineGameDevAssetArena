package simulation

import "../content"
import "core:math"
import "core:testing"

movement_test_ready :: proc(session: ^Session, catalog: ^content.Game_Content) {
    session_join(session, false)
    session_join(session, false)
    session_apply(session, catalog, 1, {kind = .Start_Selection, round_id = session.round_id})
    for owner in u8(1)..=2 {
        session_apply(session, catalog, owner, {kind = .Select_Character, round_id = session.round_id, character_id = u16(owner + 2)})
        session_apply(session, catalog, owner, {kind = .Set_Ready, round_id = session.round_id, character_id = u16(owner + 2), map_id = session.map_id, ready = true})
    }
}

@(test)
countdown_spawns_once_and_reset_invalidates_input :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    session: Session
    movement_test_ready(&session, &catalog)
    testing.expect(t, session.phase == .Countdown && session_countdown_seconds(&session) == 5 && session.character_count == 0)
    for kind in ([]Message_Kind{.Select_Character, .Select_Arena, .Set_Ready, .Input}) {
        _, rejection := session_apply(&session, &catalog, 1, {kind = kind, round_id = session.round_id, character_id = 1, map_id = 2})
        testing.expect(t, rejection == .Wrong_Phase)
    }
    for second in 0..<5 {
        testing.expect(t, session_countdown_seconds(&session) == u8(5 - second))
        for tick in 0..<60 {
            testing.expect(t, session.character_count == 0)
            changed := session_tick(&session, &catalog)
            testing.expect(t, changed == (tick == 59))
        }
    }
    testing.expect(t, session.server_tick == 300 && session.phase == .In_Arena && session.character_count == 2)
    arena := content.find_arena(&catalog, session.map_id)
    testing.expect(t, session.trainers[0].position == content.arena_cell_center(arena, arena.spawns[0]) && session.trainers[1].position == content.arena_cell_center(arena, arena.spawns[1]))
    testing.expect(t, session.characters[0].definition_id == 3 && session.characters[1].definition_id == 4)
    testing.expect(t, session.characters[0].owner_id == 1 && session.characters[1].owner_id == 2)
    first_id := session.characters[0].entity_id
    session_tick(&session, &catalog)
    testing.expect(t, session.characters[0].entity_id == first_id)
    old_round := session.round_id
    session_join(&session, true)
    session_leave(&session, 0)
    testing.expect(t, session.phase == .In_Arena && session.characters[0].entity_id == first_id)
    _, rejection := session_apply(&session, &catalog, 0, {kind = .Return_To_Lobby, round_id = session.round_id})
    testing.expect(t, rejection == .Audience_Read_Only)
    session_apply(&session, &catalog, 2, {kind = .Return_To_Lobby, round_id = session.round_id})
    testing.expect(t, session.phase == .Lobby && session.character_count == 0 && session.round_id == old_round + 1 && session_player_mask(&session) == 3)
    _, rejection = session_apply(&session, &catalog, 1, {kind = .Input, round_id = old_round, input_sequence = 1, input_mask = 2})
    testing.expect(t, rejection == .Stale_Round)
    // Start another match without rejoining; runtime IDs must not be reused.
    session_apply(&session, &catalog, 1, {kind = .Start_Selection, round_id = session.round_id})
    for owner in u8(1)..=2 {
        session_apply(&session, &catalog, owner, {kind = .Select_Character, round_id = session.round_id, character_id = u16(owner)})
        session_apply(&session, &catalog, owner, {kind = .Set_Ready, round_id = session.round_id, character_id = u16(owner), map_id = session.map_id, ready = true})
    }
    for _ in 0..<300 { session_tick(&session, &catalog) }
    testing.expect(t, session.characters[0].entity_id > first_id && session.characters[0].definition_id == 1)
    session_leave(&session, 1)
    testing.expect(t, session.phase == .Lobby && session.character_count == 0 && session.countdown_ticks == 0)
}

@(test)
movement_is_fixed_step_owner_bound_and_times_out :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    session: Session
    movement_test_ready(&session, &catalog)
    for _ in 0..<int(300 + SUMMON_DURATION_TICKS) { session_tick(&session, &catalog) }
    start := session.trainers[0].position
    other_start := session.trainers[1].position
    for sequence in u32(1)..=1000 {
        changed, reason := session_apply(&session, &catalog, 1, {kind = .Input, round_id = session.round_id, input_sequence = sequence, input_mask = 2})
        testing.expect(t, !changed && reason == .None)
    }
    testing.expect(t, session.trainers[0].position == start)
    session_tick(&session, &catalog)
    testing.expect(t, session.trainers[0].position == start && session.trainers[0].locomotion == .Walk && session.trainers[1].position == other_start)
    testing.expect(t, session.trainers[0].applied_input_sequence == 1000)
    _, rejection := session_apply(&session, &catalog, 0, {kind = .Input, round_id = session.round_id, input_sequence = 5000, input_mask = 1})
    testing.expect(t, rejection == .Audience_Read_Only)
    for _ in 0..<60 {
        session_apply(&session, &catalog, 1, {kind = .Input, round_id = session.round_id, input_sequence = 1000, input_mask = 1})
        session_tick(&session, &catalog)
    }
    // One retained input lasts 15 ticks: eight prepare, seven translate at 2 units.
    testing.expect(t, session.trainers[0].input_mask == 0 && session.trainers[0].position == start + [2]f32{14, 0} && session.trainers[0].locomotion == .Idle)
    testing.expect(t, serial_is_newer(0, 0xffffffff) && !serial_is_newer(0xffffffff, 0) && !serial_is_newer(1, 1))
    session.trainers[0].pending_input_sequence = 0xffffffff
    session_apply(&session, &catalog, 1, {kind = .Input, round_id = session.round_id, input_sequence = 0, input_mask = 1})
    session_tick(&session, &catalog)
    testing.expect(t, session.trainers[0].applied_input_sequence == 0 && session.trainers[0].position == start + [2]f32{14, 0})
    for sequence in u32(1)..=8 {
        session_apply(&session, &catalog, 1, {kind = .Input, round_id = session.round_id, input_sequence = sequence, input_mask = 1})
        session_tick(&session, &catalog)
    }
    testing.expect(t, session.trainers[0].position == start + [2]f32{12, 0})
}

@(test)
movement_normalizes_diagonals_and_blocks_terrain :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "tests/fixtures/movement"))
    defer content.destroy(&catalog)
    arena := content.find_arena(&catalog, 1)
    start := [2]f32{144, 240}
    diagonal := character_move(start, 10, 12, arena, &catalog) - start
    testing.expect(t, math.abs(math.sqrt(diagonal.x * diagonal.x + diagonal.y * diagonal.y) - 2) < 0.001)
    testing.expect(t, character_move(start, 15, 12, arena, &catalog) == start)
    position := start
    for _ in 0..<200 { position = character_move(position, 4, 12, arena, &catalog) }
    testing.expect(t, position.y >= 140 && position.y < 143) // Water ends at y=128, plus radius.
    testing.expect(t, content.arena_position_is_clear(arena, &catalog, position, 12))
    position = start
    for _ in 0..<200 { position = character_move(position, 1, 12, arena, &catalog) }
    testing.expect(t, position.x >= 44 && position.x < 47) // Border stone.
    slid := character_move(position, 9, 12, arena, &catalog)
    testing.expect(t, slid.x == position.x && slid.y > position.y)
    testing.expect(t, !content.arena_position_is_clear(arena, &catalog, {5, 240}, 12))
}

@(test)
elevation_changes_require_stairs_in_both_directions :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "tests/fixtures/content"))
    defer content.destroy(&catalog)
    arena := content.find_arena(&catalog, 1)
    arena.elevations[6] = 1 // Adjacent walkable cell (2,1).
    testing.expect(t, !content.arena_step_is_allowed(arena, &catalog, {48,48}, {80,48}))
    testing.expect(t, character_move({63,48}, 2, 12, arena, &catalog) == [2]f32{63,48})
    // Reuse one fixture terrain as a stair; the owned key is restored afterward.
    terrain := content.find_terrain(&catalog, arena.cells[6])
    previous := terrain.key
    terrain.key = "stairs"
    testing.expect(t, content.arena_step_is_allowed(arena, &catalog, {48,48}, {80,48}))
    testing.expect(t, content.arena_step_is_allowed(arena, &catalog, {80,48}, {48,48}))
    testing.expect(t, character_move({63,48}, 2, 12, arena, &catalog) == [2]f32{65,48})
    arena.elevations[6] = 2
    testing.expect(t, !content.arena_step_is_allowed(arena, &catalog, {48,48}, {80,48}))
    terrain.key = previous
}
