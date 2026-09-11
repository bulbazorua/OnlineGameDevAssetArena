package main

import "core:testing"
import "core:time"
import "core:fmt"
import "core:os"
import "core:strings"
import "perception"
import ai "ai"
import obs "observations"

battle_test_scenario :: proc(content: ^Game_Content, map_id, pick: u16, seed: u32 = 42) -> Simulation {
    sim := Simulation{seed = seed, observe_only = true}
    sim.session.map_id = map_id
    sim.session.round_id = 1
    for &player in sim.session.players { player = {present = true, ready = true, character_id = pick} }
    session_enter_arena(&sim.session, content)
    return sim
}

// Shipped content plus the staged QA arena that `make dev_vision` launches.
battle_test_content_with_qa :: proc(t: ^testing.T, content: ^Game_Content) -> u16 {
    testing.expect(t, content_load(content, "client/content/data"))
    data, error := os.read_entire_file("client/dev/fixtures/content/vision_range.arenas.json", context.allocator)
    testing.expect(t, error == nil)
    defer delete(data)
    testing.expect(t, content_parse_extra(content, data, .Arenas))
    return content.arenas[len(content.arenas) - 1].id
}

@(test)
autonomous_characters_observe_without_translating_on_every_map_and_pick :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    for &arena in content.arenas {
        for pick in content.characters {
            sim := battle_test_scenario(&content, arena.id, pick.id)
            initial := sim.session.characters
            turns: [2]int
            last_turn: [2]u32
            watched_trainer: [2]bool
            for tick in 0..<1500 {
                previous := sim.session.characters
                simulation_tick(&sim, &content)
                for c, i in sim.session.characters {
                    testing.expect(t, c.position == initial[i].position, "Observe translated a creature")
                    testing.expect(t, c.locomotion == .Idle && c.state_start_tick == initial[i].state_start_tick, "turning changed locomotion or its clock")
                    testing.expect(t, c.input_mask == 0 && c.applied_input_sequence == 0)
                    if tick < 90 { testing.expect(t, c == initial[i] && sim.battle.agents[i].last.reason == .Locked) }
                    if c.facing != previous[i].facing {
                        step := obs.facing_step(character_facing_to_observation(previous[i].facing), character_facing_to_observation(c.facing))
                        testing.expect(t, abs(step) == 1, "a turn exceeded one 45° step")
                        if turns[i] > 0 { testing.expect(t, sim.session.server_tick - last_turn[i] >= CHARACTER_TURN_INTERVAL_TICKS) }
                        turns[i] += 1
                        last_turn[i] = sim.session.server_tick
                    }
                    agent := sim.battle.agents[i]
                    if agent.last.reason == .Observe && agent.attention.subject == obs.Subject_Handle(sim.session.trainers[i].entity_id) { watched_trainer[i] = true }
                }
            }
            // Empty field ahead: both scan, then notice and watch their own nearby trainer.
            testing.expectf(t, turns[0] >= 3 && turns[1] >= 3 && watched_trainer[0] && watched_trainer[1], "%s/%s turns %v watched %v", arena.key, pick.key, turns, watched_trainer)
            testing.expect(t, sim.battle.agents[0].memory != sim.battle.agents[1].memory && sim.battle.agents[0].attention.subject != sim.battle.agents[1].attention.subject)
            session_reset(&sim.session)
            simulation_tick(&sim, &content)
            testing.expect(t, sim.battle == Battle_Runtime{})
            sim.session.map_id = arena.id
            for &player in sim.session.players { player = {present = true, ready = true, character_id = pick.id} }
            session_enter_arena(&sim.session, &content)
            simulation_tick(&sim, &content)
            testing.expect(t, sim.battle.agents[0].entity_id != initial[0].entity_id && sim.battle.agents[0].memory == ai.Visual_Memory{} && sim.battle.agents[0].attention == ai.Attention{})
            testing.expect(t, sim.battle.receptors[0].vision.profile == pick.vision && sim.battle.receptors[0].vision.schedule.sample_counter == 0)
        }
    }
}

@(test)
face_action_turns_in_place_and_respects_locks_and_intervals :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    sim := battle_test_scenario(&content, 1, 5)
    sim.session.summon_elapsed_ticks = 90
    c := &sim.session.characters[0]
    origin, spawn_tick := c.position, c.state_start_tick
    runtime: Character_Action_Runtime
    face :: proc(f: obs.Facing) -> ai.Intent { return {kind = .Face, facing = f} }
    testing.expect(t, character_turn_ready(&runtime, 0) && character_turn_ready(nil, 0xffffffff))
    sim.session.server_tick = 200
    result := character_resolve_intent(c, &sim.session, &content, face(.West), origin, BATTLE_MOVE_LIMITS, true, &runtime)
    // East to West is 180°: the fixed tie turns clockwise, one step, immediately.
    testing.expect(t, result.kind == .Turned && c.facing == .South_East && result.facing == .South_East && result.displacement == [2]f32{})
    testing.expect(t, c.position == origin && c.locomotion == .Idle && c.state_start_tick == spawn_tick)
    for tick in u32(201)..<206 {
        sim.session.server_tick = tick
        result = character_resolve_intent(c, &sim.session, &content, face(.West), origin, BATTLE_MOVE_LIMITS, true, &runtime)
        testing.expect(t, result.kind == .Turn_Pending && c.facing == .South_East && !character_turn_ready(&runtime, tick))
    }
    expected := [?]Character_Facing{.South, .South_West, .West}
    for facing, index in expected {
        sim.session.server_tick = 206 + u32(index) * CHARACTER_TURN_INTERVAL_TICKS
        result = character_resolve_intent(c, &sim.session, &content, face(.West), origin, BATTLE_MOVE_LIMITS, true, &runtime)
        testing.expect(t, result.kind == .Turned && c.facing == facing)
    }
    sim.session.server_tick = 230
    result = character_resolve_intent(c, &sim.session, &content, face(.West), origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Held && c.facing == .West && result.facing == .West)
    result = character_resolve_intent(c, &sim.session, &content, face(.North_West), origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Turned && c.facing == .North_West)
    // Locks and invalid requests preserve facing and the turn interval state.
    saved := runtime
    sim.session.server_tick = 240
    result = character_resolve_intent(c, &sim.session, &content, face(.South), origin, BATTLE_MOVE_LIMITS, false, &runtime)
    testing.expect(t, result.kind == .Locked && c.facing == .North_West && runtime == saved)
    result = character_resolve_intent(c, &sim.session, &content, {kind = .Face, facing = ai.Facing(9)}, origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Invalid_Request && c.facing == .North_West && runtime == saved)
    // Counter-clockwise shortest path: North_West to South is -3 steps, so West first.
    result = character_resolve_intent(c, &sim.session, &content, face(.South), origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Turned && c.facing == .West)
    testing.expect(t, c.position == origin && c.locomotion == .Idle && c.state_start_tick == spawn_tick)
    // A turn cancels walk preparation without translating or faking a walk.
    sim.session.server_tick = 300
    result = character_resolve_intent(c, &sim.session, &content, {kind = .Move, direction = {1, 0}}, origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Preparing && c.locomotion == .Walk && c.facing == .East && result.facing == .East)
    sim.session.server_tick = 301
    result = character_resolve_intent(c, &sim.session, &content, face(.South), origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Turned && c.facing == .South_East && c.locomotion == .Idle && c.state_start_tick == 301 && c.position == origin)
    // Idle holds keep the idle clock; a Hold intent never changes facing.
    sim.session.server_tick = 320
    result = character_resolve_intent(c, &sim.session, &content, {}, origin, BATTLE_MOVE_LIMITS, true, &runtime)
    testing.expect(t, result.kind == .Held && c.facing == .South_East && c.state_start_tick == 301)
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
audience_attachment_and_diagnostics_cannot_change_decisions :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    a := battle_test_scenario(&content, 4, 5)
    b := a
    session_join(&b.session, true)
    // No writer: a full diagnostics queue also exercises non-blocking record loss.
    debug := new(AI_Debug)
    defer free(debug)
    debug.origin = time.tick_now()
    stream := audience_init(5000)
    defer audience_destroy(&stream)
    audience_advance(&stream, &a.session, 0)
    historical := a.session.characters
    for tick in u32(1)..<1800 {
        simulation_tick(&a, &content)
        simulation_tick(&b, &content, nil, debug)
        testing.expect(t, a.session.characters == b.session.characters && a.battle == b.battle)
    }
    testing.expect(t, debug.count == AI_DEBUG_QUEUE && debug.dropped > 0)
    testing.expect(t, audience_advance(&stream, &a.session, 5000 * time.Millisecond))
    testing.expect(t, stream.latest.characters == historical && stream.latest.summon_elapsed_ticks == 0)
    testing.expect(t, a.session.characters != historical, "creatures never turned")
}

@(test)
hidden_world_changes_do_not_reach_the_brain_until_sensed :: proc(t: ^testing.T) {
    content_a, content_b: Game_Content
    testing.expect(t, content_load(&content_a, "client/content/data") && content_load(&content_b, "client/content/data"))
    defer content_destroy(&content_a)
    defer content_destroy(&content_b)
    a := battle_test_scenario(&content_a, 1, 5)
    b := a
    // Hidden differences in B: the unseen opponent stands elsewhere, its trainer moved,
    // its private memory differs, and distant terrain became opaque.
    b.session.characters[1].position += {0, -96}
    b.session.characters[1].facing = .North
    b.session.trainers[1].position += {32, 64}
    arena_b := content_arena(&content_b, 1)
    arena_b.cells[10 * arena_b.width + 45] = 5 // stone, 33 units east of P1
    arena_refresh_rules(arena_b, &content_b)
    for tick in u32(1)..<900 {
        simulation_tick(&a, &content_a)
        simulation_tick(&b, &content_b)
        if tick == 200 { b.battle.agents[1].memory = {}; b.battle.agents[1].attention = {} }
        testing.expect(t, a.battle.agents[0] == b.battle.agents[0], "hidden changes altered P1's private state")
        testing.expect(t, a.battle.receptors[0].vision.last == b.battle.receptors[0].vision.last, "hidden changes altered P1's delivered evidence")
        testing.expect(t, a.session.characters[0] == b.session.characters[0], "hidden changes altered P1's actions")
    }
    testing.expect(t, a.battle.agents[0].memory.ingested_samples > 100)
    // Positive case: a visible opponent legitimately changes attention and decisions.
    c := battle_test_scenario(&content_a, 1, 5)
    c.session.characters[1].position = c.session.characters[0].position + {160, 0}
    for _ in 0..<96 { simulation_tick(&c, &content_a) }
    d := battle_test_scenario(&content_a, 1, 5)
    for _ in 0..<96 { simulation_tick(&d, &content_a) }
    testing.expect(t, c.battle.agents[0].last.reason == .Observe && c.battle.agents[0].attention.subject == obs.Subject_Handle(c.session.characters[1].entity_id))
    testing.expect(t, c.battle.agents[0].memory.focused_count == 1 && c.battle.agents[0].memory.focused[0].position == c.session.characters[1].position)
    testing.expect(t, d.battle.agents[0].last.reason == .Scan && c.battle.agents[0] != d.battle.agents[0])
    // Equivalent peripheral cues: different exact positions with the same sector/band
    // deliver identical evidence and identical decisions until focus supplies detail.
    e := battle_test_scenario(&content_a, 1, 5)
    f := battle_test_scenario(&content_a, 1, 5)
    e.session.characters[1].position = e.session.characters[0].position + {141.42, 141.42}
    f.session.characters[1].position = f.session.characters[0].position + {120, 207.85}
    for tick in u32(1)..<97 {
        simulation_tick(&e, &content_a)
        simulation_tick(&f, &content_a)
        testing.expect(t, e.battle.agents[0] == f.battle.agents[0] && e.battle.receptors[0].vision.last == f.battle.receptors[0].vision.last && e.session.characters[0] == f.session.characters[0])
        if tick == 91 {
            testing.expect(t, e.battle.receptors[0].vision.last.cue_count == 1 && e.battle.receptors[0].vision.last.cues[0].sector == 1 && e.battle.receptors[0].vision.last.cues[0].band == .Far)
            testing.expect(t, e.battle.agents[0].last.reason == .Orient && e.session.characters[0].facing == .South_East)
        }
    }
    testing.expect(t, e.battle.receptors[0].vision.audit != f.battle.receptors[0].vision.audit, "host audit keeps the exact positions")
    simulation_tick(&e, &content_a)
    simulation_tick(&f, &content_a)
    testing.expect(t, e.battle.receptors[0].vision.last.focused_count == 1 && f.battle.receptors[0].vision.last.focused_count == 1 && e.battle.receptors[0].vision.last != f.battle.receptors[0].vision.last)
}

@(test)
enclosed_battle_remains_bounded_and_has_no_tick_allocations :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    sim := battle_test_scenario(&content, 1, 5)
    arena := content_arena(&content, 1)
    // A real one-cell room. Both creatures share it and stay coincident.
    for &cell in arena.cells { cell = 5 } // stone: opaque and unwalkable
    arena_refresh_rules(arena, &content)
    center := [2]int{5, 5}
    arena.cells[center.y * arena.width + center.x] = 1 // grass
    arena_refresh_rules(arena, &content)
    for &c in sim.session.characters { c.position = arena_cell_center(arena, center) }
    for &trainer in sim.session.trainers { trainer.position = arena_cell_center(arena, center) }
    sim.session.summon_elapsed_ticks = 90
    observed := 0
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
        for agent in sim.battle.agents { if agent.last.reason == .Observe { observed += 1 } }
    }
    context.allocator = saved_allocator
    context.temp_allocator = saved_temp_allocator
    testing.expect(t, observed > 3000, "coincident subjects should be focused every tick")
    for c in sim.session.characters { testing.expect(t, c.position == arena_cell_center(arena, center)) }
    fmt.printf("[AI] 3600 enclosed-world ticks: %v total, %v max, %d observe decisions, no tick allocations\n", time.tick_since(started), worst, observed)
}

@(test)
vision_workload_measurement_on_the_qa_arena :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    sim := battle_test_scenario(&content, map_id, 5)
    worst: time.Duration
    total: time.Duration
    samples := 0
    saved_allocator := context.allocator
    saved_temp_allocator := context.temp_allocator
    context.temp_allocator = {}
    context.allocator = {}
    for _ in 0..<3600 {
        before := time.tick_now()
        simulation_tick(&sim, &content)
        elapsed := time.tick_since(before)
        total += elapsed
        worst = max(worst, elapsed)
    }
    context.allocator = saved_allocator
    context.temp_allocator = saved_temp_allocator
    for receptor in sim.battle.receptors { samples += int(receptor.vision.schedule.sample_counter) }
    testing.expect(t, samples == 2 * ((3600 - 91) / 6 + 1) && sim.battle.agents[0].memory.focused_count == 1 && sim.battle.agents[1].memory.focused_count == 1)
    fmt.printf("[vision] 3600 QA-arena ticks (serial reference): %v total, %v mean, %v max, %d eye samples, %d bytes per Sense_Input, %d bytes per Agent\n",
        total, total / 3600, worst, samples, size_of(obs.Sense_Input), size_of(ai.Agent))
}

@(test)
replacing_one_creature_keeps_the_other_creatures_private_runtime :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    for replaced in 0..<MAX_PLAYERS {
        kept := 1 - replaced
        sim := battle_test_scenario(&content, map_id, 5)
        for _ in 0..<300 { simulation_tick(&sim, &content) }
        before := sim.battle
        testing.expect(t, before.agents[kept].memory.focused_count > 0 && before.actions[kept].turn_started, "the kept creature must first gain experience")
        sim.session.characters[replaced].entity_id += 1000
        battle_sync(&sim.battle, &sim.session, &content)
        // The replaced slot is fresh: empty mind, bound eye, no turn timing, new anchor.
        testing.expect(t, sim.battle.agents[replaced] == ai.agent_reset(sim.session.characters[replaced].entity_id, sim.session.round_id, sim.battle.controller, sim.battle.seed))
        testing.expect(t, sim.battle.receptors[replaced] == Receptor{vision = {profile = before.receptors[replaced].vision.profile}, olfaction = {profile = before.receptors[replaced].olfaction.profile}} && sim.battle.actions[replaced] == Character_Action_Runtime{})
        // The kept slot and the round-wide settings are byte-for-byte unchanged.
        testing.expect(t, sim.battle.agents[kept] == before.agents[kept] && sim.battle.receptors[kept] == before.receptors[kept], "replacement touched the other creature's mind or eye")
        testing.expect(t, sim.battle.actions[kept] == before.actions[kept] && sim.battle.anchors[kept] == before.anchors[kept], "replacement touched the other creature's timing or anchor")
        testing.expect(t, sim.battle.bound && sim.battle.round_id == before.round_id && sim.battle.config == before.config && sim.battle.limits == before.limits)
        // The kept eye stays on its own schedule; its old memory of the replaced entity ages until expiry.
        old_subject := before.agents[kept].memory.focused[0].subject
        for _ in 0..<6 { simulation_tick(&sim, &content) }
        testing.expect(t, sim.battle.receptors[kept].vision.schedule.sample_counter == before.receptors[kept].vision.schedule.sample_counter + 1)
        testing.expect(t, sim.battle.receptors[kept].vision.last.sample_tick == before.receptors[kept].vision.schedule.next_sample_tick)
        testing.expect(t, sim.battle.receptors[replaced].vision.schedule.sample_counter == 1 && sim.battle.agents[replaced].memory.ingested_samples == 1)
        remembered := false
        for entry in sim.battle.agents[kept].memory.focused[:sim.battle.agents[kept].memory.focused_count] { if entry.subject == old_subject { remembered = true } }
        testing.expect(t, remembered, "the kept creature lost its memory of the old subject without expiry")
        // A round change still clears both creatures.
        sim.session.round_id += 1
        battle_sync(&sim.battle, &sim.session, &content)
        for index in 0..<MAX_PLAYERS {
            testing.expect(t, sim.battle.agents[index] == ai.agent_reset(sim.session.characters[index].entity_id, sim.session.round_id))
            testing.expect(t, sim.battle.receptors[index].vision.schedule.sample_counter == 0 && sim.battle.actions[index] == Character_Action_Runtime{})
        }
    }
}

// Largest accepted map, smallest tile and longest range: both creatures and both
// trainers sit near the far end of each other's sight across an empty field.
@(test)
worst_supported_vision_envelope_stays_bounded :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, `{"schema_version": 2, "arenas": [{"id": 9, "key": "envelope_qa", "display_name": "Envelope QA", "width": 128, "height": 128, "tile_size": 16, "rows": [`)
    for y in 0..<128 {
        if y > 0 { strings.write_string(&builder, ",") }
        strings.write_string(&builder, `"`)
        for _ in 0..<128 { strings.write_string(&builder, ".") }
        strings.write_string(&builder, `"`)
    }
    strings.write_string(&builder, `], "elevation_rows": [`)
    for y in 0..<128 {
        if y > 0 { strings.write_string(&builder, ",") }
        strings.write_string(&builder, `"`)
        for _ in 0..<128 { strings.write_string(&builder, "0") }
        strings.write_string(&builder, `"`)
    }
    strings.write_string(&builder, `], "spawns": [[2, 2], [125, 125]]}]}`)
    testing.expect(t, content_parse_extra(&content, transmute([]u8)strings.to_string(builder), .Arenas))
    arena := content.arenas[len(content.arenas) - 1]
    sim := battle_test_scenario(&content, arena.id, 5)
    sim.session.summon_elapsed_ticks = 90
    battle_sync(&sim.battle, &sim.session, &content)
    corners := [2][2]int{{1, 1}, {90, 90}} // cell centers about 2,014 units apart, inside a 2,048 range
    for index in 0..<MAX_PLAYERS {
        sim.session.characters[index].position = arena_cell_center(&arena, corners[index])
        sim.session.characters[index].facing = .South_East if index == 0 else .North_West
        sim.session.trainers[index].position = arena_cell_center(&arena, corners[index] + {2, 0})
        sim.battle.receptors[index].vision.profile.range = perception.MAX_RANGE_GAMEPLAY_UNITS * perception.WORLD_UNITS_PER_GAMEPLAY_UNIT
    }
    worst, total: time.Duration
    saved_allocator := context.allocator
    saved_temp_allocator := context.temp_allocator
    context.temp_allocator = {}
    context.allocator = {}
    for _ in 0..<3600 {
        before := time.tick_now()
        simulation_tick(&sim, &content)
        elapsed := time.tick_since(before)
        total += elapsed
        worst = max(worst, elapsed)
    }
    context.allocator = saved_allocator
    context.temp_allocator = saved_temp_allocator
    for agent, index in sim.battle.agents {
        other := sim.session.characters[1 - index]
        testing.expectf(t, agent.memory.focused_count >= 1 && agent.attention.subject == obs.Subject_Handle(other.entity_id), "creature %d never focused the far creature: %v", index, agent.attention)
        testing.expect(t, sim.battle.receptors[index].vision.audit.candidates[0].verdict == .Focused, "the far creature must be seen across the empty map")
    }
    fmt.printf("[vision] 3600 worst-envelope ticks (128x128 map, 16-unit tiles, 2048-unit range, serial reference): %v total, %v mean, %v max\n", total, total / 3600, worst)
}
