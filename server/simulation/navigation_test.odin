package simulation

import ai "../ai"
import obs "../observations"
import "../content"
import "../perception"
import "core:fmt"
import "core:testing"
import "core:time"

@(test)
visible_post_is_passed_without_the_old_contact_first_loop :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    arena := &catalog.arenas[0]
    floor, wall := u16(0), u16(0)
    for terrain in catalog.terrains {
        if terrain.walkable && !terrain.blocks_vision { floor = terrain.id }
        if !terrain.walkable && terrain.blocks_vision { wall = terrain.id }
    }
    testing.expect(t, floor != 0 && wall != 0 && arena.width > 20 && arena.height > 12)
    for &cell in arena.cells { cell = floor }
    for &height in arena.elevations { height = 0 }
    arena.cells[10 * arena.width + 11] = wall
    content.arena_refresh_rules(arena, &catalog)
    definition := content.find_character(&catalog, 5)
    tile := f32(arena.tile_size)
    start := [2]f32{9.5 * tile, 10.5 * tile}
    body := Character{entity_id = 3, definition_id = 5, owner_id = 1, position = start, facing = .East}
    contact_first := body
    session := Session{phase = .In_Arena, map_id = arena.id, round_id = 1, summon_elapsed_ticks = SUMMON_DURATION_TICKS}
    action, old_action: Character_Action_Runtime
    agent := ai.agent_reset(3, 1, .Search, 42)
    agent.search.started, agent.search.leg_active, agent.search.heading, agent.search.leg_deadline = true, true, .East, 100000
    sample: obs.Vision_Sample
    collisions, old_collisions := 0, 0
    avoided_before_contact := false
    started := time.tick_now()
    for tick in u32(1)..=600 {
        session.server_tick = tick
        fresh := (tick - 1) % 6 == 0
        if fresh {
            query := perception.Vision_Query{observer = {entity_id = 3, round_id = 1,
                pose = {body.position, character_facing_to_observation(body.facing)}},
                profile = definition.vision, grid = content.arena_opacity_grid(arena), terrain = arena.navigation}
            sample, _ = perception.vision_sample(query, tick, tick, tick)
        }
        ctx := ai.Decision_Context{entity_id = 3, round_id = 1, tick = tick, position = body.position,
            facing = character_facing_to_observation(body.facing), can_act = true, turn_ready = character_turn_ready(&action, tick),
            motion = {64, definition.footprint_radius, 1.0 / SIMULATION_HZ}, senses = {vision = sample, vision_is_new = fresh}}
        command := ai.agent_decide(&agent, ctx, ai.observe_defaults())
        if command.kind == .Face && body.position.x + definition.footprint_radius < 11 * tile &&
            agent.navigation.choices[int(obs.Facing.East)].rejection == .Solid { avoided_before_contact = true }
        result := character_resolve_intent(&body, &session, &catalog, command, start, {64, 0}, true, &action)
        ai.agent_record_result(&agent, result, tick, ai.observe_defaults())
        old := character_resolve_intent(&contact_first, &session, &catalog, {kind = .Move, direction = {1, 0}}, start, {64, 0}, true, &old_action)
        if result.kind == .Terrain_Blocked { collisions += 1 }
        if old.kind == .Terrain_Blocked { old_collisions += 1 }
        testing.expect(t, content.arena_position_is_clear(arena, &catalog, body.position, definition.footprint_radius))
    }
    fmt.printfln("[navigation] visible post: new blocked=%d, contact-first blocked=%d, start=%v, end=%v; 600 ticks in %v",
        collisions, old_collisions, start, body.position, time.tick_since(started))
    testing.expect(t, avoided_before_contact, "the controller waited for physical contact")
    testing.expectf(t, collisions == 0 && old_collisions > 100, "new blocked %d; contact-first blocked %d", collisions, old_collisions)
    testing.expectf(t, body.position.x > 12 * tile + definition.footprint_radius, "the creature did not finish passing the post: %v", body.position)
}
