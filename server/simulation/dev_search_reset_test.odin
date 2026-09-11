package simulation

import "../content"
import ai "../ai"
import "core:testing"

@(test)
search_reset_places_both_creatures_out_of_sight_on_all_shipped_and_qa_maps :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    for &arena in catalog.arenas {
        sim := battle_test_scenario(&catalog, arena.id, 5, 42)
        sim.session.players[1].character_id = 6
        placements, valid := dev_search_reset_placements(&sim.session, &catalog)
        testing.expectf(t, valid, "No separated search placement in %s", arena.key)
        if !valid { continue }
        for placement, index in placements {
            definition := content.find_character(&catalog, sim.session.players[index].character_id)
            other := content.find_character(&catalog, sim.session.players[1 - index].character_id)
            testing.expect(t, content.arena_position_is_clear(&arena, &catalog, placement.creature, definition.footprint_radius))
            testing.expect(t, content.arena_position_is_clear(&arena, &catalog, placement.trainer, TRAINER_RADIUS))
            minimum := definition.vision.range + other.footprint_radius + f32(arena.tile_size * 2)
            testing.expect(t, dev_search_distance_squared(placement.creature, placements[1 - index].creature) > minimum * minimum)
            testing.expect(t, dev_search_distance_squared(placement.creature, placements[1 - index].trainer) > minimum * minimum)
            testing.expect(t, dev_search_distance_squared(placement.creature, placement.trainer) > (definition.footprint_radius + TRAINER_RADIUS) * (definition.footprint_radius + TRAINER_RADIUS))
        }
    }
}

@(test)
search_reset_is_authorized_atomic_and_clears_both_private_lifecycles :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    sim := battle_test_scenario(&catalog, map_id, 5, 42)
    sim.observe_only = false
    for tick in 0..<1500 { advance(&sim, &catalog) }
    testing.expect(t, sim.battle.agents[0].search.acquisition_count > 0 && sim.battle.agents[1].search.visit_count > 0)
    before := sim.session
    command := Client_Command{kind = .Dev_Reset_Search, round_id = before.round_id}
    changed, rejected := session_apply(&sim.session, &catalog, 0, command, true)
    testing.expect(t, !changed && rejected == .Audience_Read_Only && sim.session == before)
    changed, rejected = session_apply(&sim.session, &catalog, 1, command)
    testing.expect(t, !changed && rejected == .Dev_Only && sim.session == before)
    changed, rejected = session_apply(&sim.session, &catalog, 1, command, true)
    when !ODIN_DEBUG {
        testing.expect(t, !changed && rejected == .Dev_Only && sim.session == before)
        return
    }
    testing.expect(t, changed && rejected == .None && sim.session.round_id == before.round_id + 1 && sim.session.revision == before.revision + 1)
    testing.expect(t, sim.session.server_tick == before.server_tick && sim.session.phase == .In_Arena && sim.session.summon_elapsed_ticks == 0)
    testing.expect(t, sim.session.players == before.players && sim.session.map_id == before.map_id && sim.session.audience_count == before.audience_count)
    battle_sync(&sim.battle, &sim.session, &catalog, sim.seed, .Search)
    for character, index in sim.session.characters {
        testing.expect(t, character.entity_id != before.characters[index].entity_id && character.position != before.characters[index].position)
        testing.expect(t, !character.target_alert && character.target_acquired_tick == 0 && character.locomotion == .Idle)
        testing.expect(t, sim.battle.agents[index] == ai.agent_reset(character.entity_id, sim.session.round_id, .Search, sim.seed))
        testing.expect(t, sim.battle.receptors[index].vision.last.sample_id == 0 && sim.battle.actions[index] == Character_Action_Runtime{})
    }
    fresh := sim.session
    changed, rejected = session_apply(&sim.session, &catalog, 2, command, true)
    testing.expect(t, !changed && rejected == .Stale_Round && sim.session == fresh)
    command.round_id = fresh.round_id
    changed, rejected = session_apply(&sim.session, &catalog, 2, command, true)
    testing.expect(t, !changed && rejected == .Wrong_Phase && sim.session == fresh)
    for tick in 0..<96 { advance(&sim, &catalog) }
    for agent in sim.battle.agents { testing.expect(t, agent.search.target == 0 && agent.search.acquisition_count == 0 && agent.search.visit_count > 0) }
}

@(test)
search_reset_rejects_small_or_disconnected_ground_without_changing_the_match :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    sim := battle_test_scenario(&catalog, map_id, 5)
    sim.session.summon_elapsed_ticks = SUMMON_DURATION_TICKS
    before := sim.session
    definition := content.find_character(&catalog, 5)
    definition.vision.range = 2048
    _, valid := dev_search_reset_placements(&sim.session, &catalog)
    testing.expect(t, !valid && sim.session == before)
    when ODIN_DEBUG {
        changed, rejection := session_apply(&sim.session, &catalog, 1, {kind = .Dev_Reset_Search, round_id = before.round_id}, true)
        testing.expect(t, !changed && rejection == .Search_Reset_Unavailable && sim.session == before)
    }
    definition.vision.range = 256
    arena := content.find_arena(&catalog, map_id)
    wall, ground: u16
    for terrain in catalog.terrains {
        if terrain.walkable { ground = terrain.id } else { wall = terrain.id }
    }
    for &cell in arena.cells { cell = wall }
    for y in 1..=4 { for x in 1..=4 { arena.cells[y * arena.width + x] = ground } }
    for y in 9..=12 { for x in 19..=22 { arena.cells[y * arena.width + x] = ground } }
    arena.spawns = {{2, 2}, {20, 10}}
    _, valid = dev_search_reset_placements(&sim.session, &catalog)
    testing.expect(t, !valid && sim.session == before, "Reset used a distant but disconnected island")
}
