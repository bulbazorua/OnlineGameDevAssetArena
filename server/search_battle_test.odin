package main

import ai "ai"
import "core:testing"
import "core:fmt"
import "core:time"

@(test)
search_crosses_the_old_spawn_leash_and_acquires_opponents_on_real_maps :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    for &arena in content.arenas {
        sim := battle_test_scenario(&content, arena.id, 5, 42)
        sim.observe_only = false
        initial := sim.session.characters
        found: [2]u32
        traveled: [2]f32
        started := time.tick_now()
        for tick in 0..<18000 {
            simulation_tick(&sim, &content)
            for c, index in sim.session.characters {
                offset := c.position - initial[index].position
                traveled[index] = max(traveled[index], offset.x * offset.x + offset.y * offset.y)
                if c.target_alert && found[index] == 0 { found[index] = sim.session.server_tick }
                if tick < 90 { testing.expect(t, c == initial[index]) }
                testing.expect(t, c.input_mask == 0 && c.applied_input_sequence == 0)
                if c.target_alert {
                    search := sim.battle.agents[index].search
                    testing.expect(t, search.acquisition_count > 0 && c.target_acquired_tick == search.acquired_tick && sim.session.server_tick - c.target_acquired_tick < 60)
                }
            }
        }
        fmt.printfln("[search] %s: first acquisitions %v ticks, maximum squared travel %v, 18000 ticks in %v", arena.key, found, traveled, time.tick_since(started))
        testing.expect(t, traveled[0] > 128 * 128 && traveled[1] > 128 * 128, "search remained inside the obsolete spawn leash")
        testing.expectf(t, found[0] > 0 && found[1] > 0, "search did not encounter its opponent in the deterministic %s scenario", arena.key)
    }
}

@(test)
search_workers_match_serial_with_trace_loss_and_private_entity_lifecycle :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    a := battle_test_scenario(&content, map_id, 5, 72)
    a.observe_only = false
    b := a
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    debug := new(AI_Debug)
    defer free(debug)
    debug.origin = time.tick_now()
    for tick in 0..<2400 {
        simulation_tick(&a, &content)
        simulation_tick(&b, &content, workers, debug)
        testing.expect(t, a.battle == b.battle && a.session == b.session, "thread order or diagnostics changed search")
        if tick == 1200 {
            kept := a.battle.agents[1]
            kept_character := a.session.characters[1]
            a.session.characters[0].target_alert = true
            a.session.characters[0].target_acquired_tick = a.session.server_tick
            b.session.characters[0].target_alert = true
            b.session.characters[0].target_acquired_tick = b.session.server_tick
            a.session.characters[0].entity_id += 10
            b.session.characters[0].entity_id += 10
            battle_sync(&a.battle, &a.session, &content, a.seed, .Search)
            battle_sync(&b.battle, &b.session, &content, b.seed, .Search)
            testing.expect(t, a.battle.agents[1] == kept && a.battle.agents[0].search.visit_count == 0 && a.battle.agents[0].search.acquisition_count == 0)
            testing.expect(t, !a.session.characters[0].target_alert && a.session.characters[0].target_acquired_tick == 0 && a.session.characters[1] == kept_character)
        }
    }
    testing.expect(t, debug.dropped > 0 && workers.slots[0].response.worker_id != workers.slots[1].response.worker_id)
    session_reset(&a.session)
    simulation_tick(&a, &content)
    testing.expect(t, a.battle == Battle_Runtime{})
}

@(test)
search_cannot_read_hidden_opponents_or_the_other_brains_history :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    a := battle_test_scenario(&content, 1, 5, 42)
    a.observe_only = false
    b := a
    b.session.characters[1].position.y += 128
    b.session.characters[1].facing = .North
    for tick in 0..<240 {
        simulation_tick(&a, &content)
        simulation_tick(&b, &content)
        testing.expect(t, a.battle.agents[0] == b.battle.agents[0] && a.battle.receptors[0].vision.last == b.battle.receptors[0].vision.last && a.session.characters[0] == b.session.characters[0])
        b.battle.agents[1].search.visits[0] = {{1234, 5678}, b.session.server_tick, true}
        b.battle.agents[1].search.visit_count = 1
        b.battle.agents[1].search.random_state += 1
    }
    testing.expect(t, a.battle.agents[0].search.target == 0 && a.battle.agents[0].search.visit_count > 0)
}

@(test)
nearby_search_qa_produces_independent_target_alerts_from_focused_evidence :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    sim := battle_test_scenario(&content, map_id, 5, 42)
    sim.observe_only = false
    first: [2]u32
    for tick in 0..<1800 {
        simulation_tick(&sim, &content)
        for character, owner in sim.session.characters {
            if character.target_alert && first[owner] == 0 {
                first[owner] = sim.session.server_tick
                search := sim.battle.agents[owner].search
                testing.expect(t, search.target_visible && search.target != 0 && search.evidence == .Focused)
                sample := sim.battle.receptors[owner].vision.last
                matched := false
                for sighting in sample.focused[:sample.focused_count] {
                    if sighting.subject == search.target && sighting.position == search.target_position { matched = true }
                }
                testing.expect(t, matched)
            }
        }
    }
    fmt.printfln("[search] nearby QA first alerts: %v", first)
    testing.expect(t, first[0] > 0 && first[1] > 0)
}
