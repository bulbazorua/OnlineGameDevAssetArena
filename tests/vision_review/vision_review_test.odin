package vision_review

import "core:testing"
import ai "../../server/ai"
import host "../../server"
import obs "../../server/observations"
import sight "../../server/perception"

review_query :: proc(grid: sight.Opacity_Grid, from, to: obs.Vector) -> sight.Vision_Query {
    facing, _ := obs.facing_toward(from, to)
    return {
        observer = {entity_id = 1, round_id = 1, pose = {from, facing}},
        profile = {enabled = true, range = 256, focused_fov_degrees = 60, overall_fov_degrees = 160, sample_interval = 6},
        grid = grid,
        candidates = {0 = {entity_id = 2, kind = .Creature, appearance_id = 1, position = to}},
        candidate_count = 1,
    }
}

@(test)
opaque_tile_edges_and_corners_block_from_both_directions :: proc(t: ^testing.T) {
    cells: [10 * 10]bool
    cells[4 * 10 + 4] = true
    grid := sight.Opacity_Grid{width = 10, height = 10, tile_size = 32, opaque = cells[:]}
    segments := [?][2]obs.Vector{
        {{128, 96}, {128, 192}},
        {{160, 96}, {160, 192}},
        {{96, 128}, {192, 128}},
        {{96, 160}, {192, 160}},
        {{192, 192}, {160, 160}},
    }
    for segment, index in segments {
        for reverse in 0..<2 {
            from, to := segment[reverse], segment[1 - reverse]
            clear := sight.line_of_sight(grid, from, to)
            sample, audit := sight.vision_sample(review_query(grid, from, to), 1, 1, 1)
            testing.expectf(t, !clear && sample.focused_count == 0 && sample.cue_count == 0,
                "edge/corner case %d reverse %d: clear=%v, focused=%d, cues=%d, verdict=%v",
                index, reverse, clear, sample.focused_count, sample.cue_count, audit.candidates[0].verdict)
        }
    }
    testing.expect(t, sight.line_of_sight(grid, {160.5, 96}, {160.5, 192}), "A ray just outside the wall should stay clear")
    testing.expect(t, !sight.line_of_sight(grid, {144, 96}, {144, 192}), "A ray through the wall should be blocked")
}

@(test)
accepted_range_sees_across_an_empty_arena_with_small_tiles :: proc(t: ^testing.T) {
    cells: [128 * 128]bool
    grid := sight.Opacity_Grid{width = 128, height = 128, tile_size = 16, opaque = cells[:]}
    query := review_query(grid, {8, 8}, {1448, 1448})
    query.profile.range = 64 * sight.WORLD_UNITS_PER_GAMEPLAY_UNIT
    testing.expect(t, sight.vision_profile_valid(query.profile), "The profile must be accepted before testing its range")
    sample, audit := sight.vision_sample(query, 1, 1, 1)
    testing.expectf(t, sample.focused_count == 1,
        "An in-range subject on an empty accepted grid was lost: distance=%v, range=%v, verdict=%v",
        audit.candidates[0].distance, query.profile.range, audit.candidates[0].verdict)
    query.candidates[0].position = {1000, 1000}
    sample, _ = sight.vision_sample(query, 2, 2, 2)
    testing.expect(t, sample.focused_count == 1, "The shorter control ray should remain visible")
}

@(test)
replacing_one_creature_preserves_the_other_creatures_private_state :: proc(t: ^testing.T) {
    content: host.Game_Content
    if !testing.expect(t, host.content_load(&content, "client/content/data")) { return }
    defer host.content_destroy(&content)
    sim: host.Simulation
    sim.session.map_id = content.arenas[0].id
    sim.session.round_id = 1
    for &player in sim.session.players {
        player = {present = true, ready = true, character_id = content.characters[0].id}
    }
    host.session_enter_arena(&sim.session, &content)
    for _ in 0..<900 { host.simulation_tick(&sim, &content) }
    before := sim.battle
    if !testing.expect(t, before.agents[1].memory.focused_count > 0, "The untouched creature must first gain real experience") { return }
    sim.session.characters[0].entity_id += 1000
    host.battle_sync(&sim.battle, &sim.session, &content)
    testing.expect(t, sim.battle.agents[0].entity_id == sim.session.characters[0].entity_id)
    testing.expect(t, sim.battle.agents[0].memory == ai.Visual_Memory{}, "The replacement must start without memories")
    testing.expect(t, sim.battle.agents[1] == before.agents[1], "Replacing P1 erased P2's agent state")
    testing.expect(t, sim.battle.receptors[1] == before.receptors[1], "Replacing P1 reset P2's eye sample or schedule")
    testing.expect(t, sim.battle.actions[1] == before.actions[1], "Replacing P1 reset P2's action timing")
}
