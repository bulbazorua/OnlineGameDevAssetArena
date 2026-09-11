package simulation

import "../content"
import "core:os"
import "core:testing"

// Scenario builders shared by the simulation tests and the host package's tests.
battle_test_scenario :: proc(catalog: ^content.Game_Content, map_id, pick: u16, seed: u32 = 42) -> Simulation {
    sim := Simulation{seed = seed, observe_only = true}
    sim.session.map_id = map_id
    sim.session.round_id = 1
    for &player in sim.session.players { player = {present = true, ready = true, character_id = pick} }
    session_enter_arena(&sim.session, catalog)
    return sim
}

// Shipped content plus the staged QA arena that `make dev_vision` launches.
battle_test_content_with_qa :: proc(t: ^testing.T, catalog: ^content.Game_Content) -> u16 {
    testing.expect(t, content.load(catalog, "client/content/data"))
    data, error := os.read_entire_file("client/dev/fixtures/content/vision_range.arenas.json", context.allocator)
    testing.expect(t, error == nil)
    defer delete(data)
    testing.expect(t, content.parse_extra(catalog, data, .Arenas))
    return catalog.arenas[len(catalog.arenas) - 1].id
}

// QA arena, two picks, no creature movement (Observe) so trails come only from
// trainers that the test walks with real input commands.
scent_test_scenario :: proc(catalog: ^content.Game_Content, map_id: u16, picks: [2]u16, seed: u32 = 42) -> Simulation {
    sim := Simulation{seed = seed, observe_only = true}
    sim.session.map_id = map_id
    sim.session.round_id = 1
    for &player, index in sim.session.players { player = {present = true, ready = true, character_id = picks[index]} }
    session_enter_arena(&sim.session, catalog)
    return sim
}
