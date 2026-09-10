package main

import "core:testing"
import "core:time"
import "core:fmt"
import ai "ai"

battle_test_scenario :: proc(content: ^Game_Content, map_id, pick: u16, seed: u32 = 42) -> Simulation {
    sim := Simulation{seed = seed}
    sim.session.map_id = map_id
    sim.session.round_id = 1
    for &player in sim.session.players { player = {present = true, ready = true, character_id = pick} }
    session_enter_arena(&sim.session, content)
    return sim
}

@(test)
autonomous_characters_use_real_simulation_on_every_map_and_pick :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    for &arena in content.arenas {
        for pick in content.characters {
            sim := battle_test_scenario(&content, arena.id, pick.id)
            initial := sim.session.characters
            walked: [2]bool
            idle: [2]bool
            prepared: [2]bool
            for tick in 0..<1500 {
                previous := sim.session.characters
                simulation_tick(&sim, &content)
                for c, i in sim.session.characters {
                    delta := c.position - previous[i].position
                    distance_sq := delta.x * delta.x + delta.y * delta.y
                    testing.expect(t, distance_sq <= 1.139, "AI exceeded 64 world units/second")
                    testing.expect(t, arena_position_is_clear(&arena, &content, c.position, pick.footprint_radius))
                    testing.expect(t, arena_step_is_allowed(&arena, &content, previous[i].position, c.position))
                    offset := c.position - initial[i].position
                    testing.expect(t, offset.x * offset.x + offset.y * offset.y <= 128 * 128 + 0.01)
                    preparing := c.locomotion == .Walk && sim.session.server_tick - c.state_start_tick < CHARACTER_WALK_START_TICKS
                    testing.expect(t, (c.locomotion == .Walk && !preparing) == (distance_sq > 0.000001))
                    if preparing {
                        prepared[i] = true
                        testing.expect(t, distance_sq == 0 && sim.battle.agents[i].last.result.kind == .Preparing)
                    }
                    testing.expect(t, !serial_is_newer(c.state_start_tick, sim.session.server_tick))
                    testing.expect(t, c.input_mask == 0 && c.applied_input_sequence == 0)
                    if tick < 90 { testing.expect(t, c == initial[i]) }
                    if distance_sq > 0 { walked[i] = true }
                    if c.locomotion == .Idle { idle[i] = true }
                }
            }
            testing.expect(t, walked[0] && walked[1] && idle[0] && idle[1] && prepared[0] && prepared[1])
            testing.expect(t, sim.battle.agents[0].random != sim.battle.agents[1].random)
            session_reset(&sim.session)
            simulation_tick(&sim, &content)
            testing.expect(t, sim.battle == Battle_Runtime{})
            sim.session.map_id = arena.id
            for &player in sim.session.players { player = {present = true, ready = true, character_id = pick.id} }
            session_enter_arena(&sim.session, &content)
            simulation_tick(&sim, &content)
            testing.expect(t, sim.battle.agents[0].entity_id != initial[0].entity_id && !sim.battle.agents[0].wander.started)
        }
    }
}

@(test)
walk_plays_first_step_before_motion_and_can_be_cancelled :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    // Literal timing fixture shared with the client presentation check. Include wrap.
    starts := [2]u32{112, 0xfffffffc}
    for start in starts {
        sim := battle_test_scenario(&content, 1, 5)
        sim.session.summon_elapsed_ticks = 90
        c := &sim.session.characters[0]
        origin := c.position
        for age in u32(0)..<15 {
            sim.session.server_tick = start + age
            result := character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, {64, 128}, true)
            testing.expect(t, c.locomotion == .Walk && c.facing == .East && c.state_start_tick == start)
            if age < 12 {
                testing.expect(t, result.kind == .Preparing && result.displacement == [2]f32{} && c.position == origin)
            } else {
                testing.expect(t, result.kind == .Moved && result.displacement.x > 1 && c.position.x > origin.x)
            }
        }
        sim.session.server_tick += 1
        character_resolve_intent(c, &sim.session, &content, {}, origin, {64, 128}, true)
        testing.expect(t, c.locomotion == .Idle)
        // Interrupt preparation with a lock, then require a fresh first step.
        sim.session.server_tick += 1
        result := character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, {64, 128}, true)
        testing.expect(t, result.kind == .Preparing)
        sim.session.server_tick += 4
        result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, {64, 128}, false)
        testing.expect(t, result.kind == .Locked && c.locomotion == .Idle)
        sim.session.server_tick += 1
        result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, {64, 128}, true)
        testing.expect(t, result.kind == .Preparing && c.state_start_tick == sim.session.server_tick)
        // A wall encountered during preparation cancels it without displacement.
        c.position = {12, 12}
        sim.session.server_tick += 1
        result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {-1, 0}}, c.position, {64, 128}, true)
        testing.expect(t, result.kind == .Terrain_Blocked && result.displacement == [2]f32{} && c.locomotion == .Idle && c.facing == .East)
    }
}

@(test)
audience_and_trainer_input_cannot_change_ai_random_stream_or_paths :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    a := battle_test_scenario(&content, 4, 5)
    b := a
    session_join(&b.session, true)
    stream := audience_init(5000)
    defer audience_destroy(&stream)
    audience_advance(&stream, &a.session, 0)
    historical := a.session.characters
    for tick in u32(1)..<1800 {
        session_apply(&b.session, &content, 1, {kind = .Input, round_id = b.session.round_id, input_sequence = tick, input_mask = 2})
        simulation_tick(&a, &content)
        simulation_tick(&b, &content)
        testing.expect(t, a.session.characters == b.session.characters && a.battle == b.battle)
    }
    testing.expect(t, audience_advance(&stream, &a.session, 5000 * time.Millisecond))
    testing.expect(t, stream.latest.characters == historical && stream.latest.summon_elapsed_ticks == 0)
    testing.expect(t, a.session.characters != historical)
}

@(test)
action_resolver_enforces_limits_and_reports_contact :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    sim := battle_test_scenario(&content, 1, 5)
    sim.session.summon_elapsed_ticks = 90
    c := &sim.session.characters[0]
    origin := c.position
    limits := Character_Action_Limits{64, 128}
    result := character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, limits, false)
    testing.expect(t, result.kind == .Locked && c.position == origin)
    result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {100, 0}}, origin, limits, true)
    testing.expect(t, result.kind == .Invalid_Request && c.position == origin)
    result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, {64, 0.5}, true)
    testing.expect(t, result.kind == .Anchor_Limit && c.position == origin)
    // Put the character exactly against a known map boundary, then request outward.
    c.position = {12, 12}
    result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {-1, 0}}, c.position, limits, true)
    testing.expect(t, result.kind == .Terrain_Blocked && c.position == [2]f32{12, 12} && c.locomotion == .Idle)
}

@(test)
blocked_battle_remains_bounded_and_has_no_tick_allocations :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    sim := battle_test_scenario(&content, 1, 5)
    arena := content_arena(&content, 1)
    // A real one-cell room. Radius 16 touches every wall, so every direction fails.
    for &cell in arena.cells { cell = 4 } // water, validated below
    testing.expect(t, !content_terrain(&content, 4).walkable)
    center := [2]int{5, 5}
    arena.cells[center.y * arena.width + center.x] = 1 // grass
    for &definition in content.characters { definition.footprint_radius = 16 }
    for &c in sim.session.characters { c.position = arena_cell_center(arena, center) }
    for &trainer in sim.session.trainers { trainer.position = arena_cell_center(arena, center) }
    sim.session.summon_elapsed_ticks = 90
    blocked := 0
    worst: time.Duration
    started := time.tick_now()
    saved_allocator := context.allocator
    saved_temp_allocator := context.temp_allocator
    context.temp_allocator = {}
    context.allocator = {} // Any allocation inside the production tick fails loudly.
    for _ in 0..<3600 {
        before := time.tick_now()
        simulation_tick(&sim, &content)
        worst = max(worst, time.tick_since(before))
        for agent in sim.battle.agents { if agent.last.result.kind == .Terrain_Blocked { blocked += 1 } }
    }
    context.allocator = saved_allocator
    context.temp_allocator = saved_temp_allocator
    testing.expect(t, blocked > 20 && blocked < 160)
    fmt.printf("[AI] 3600 enclosed-world ticks: %v total, %v max, %d blocked attempts, no tick allocations\n", time.tick_since(started), worst, blocked)
}
