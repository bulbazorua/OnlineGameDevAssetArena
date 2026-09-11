package simulation

import "../content"
import "core:fmt"
import "core:testing"
import "core:time"

@(test)
search_crosses_the_old_spawn_leash_and_acquires_opponents_on_real_maps :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    for &arena in catalog.arenas {
        sim := battle_test_scenario(&catalog, arena.id, 5, 42)
        sim.observe_only = false
        initial := sim.session.characters
        found: [2]u32
        traveled: [2]f32
        started := time.tick_now()
        for tick in 0..<18000 {
            advance(&sim, &catalog)
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
search_cannot_read_hidden_opponents_or_the_other_brains_history :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    a := battle_test_scenario(&catalog, 1, 5, 42)
    a.observe_only = false
    b := a
    b.session.characters[1].position.y += 128
    b.session.characters[1].facing = .North
    for tick in 0..<240 {
        advance(&a, &catalog)
        advance(&b, &catalog)
        testing.expect(t, a.battle.agents[0] == b.battle.agents[0] && a.battle.receptors[0].vision.last == b.battle.receptors[0].vision.last && a.session.characters[0] == b.session.characters[0])
        b.battle.agents[1].search.visits[0] = {{1234, 5678}, b.session.server_tick, true}
        b.battle.agents[1].search.visit_count = 1
        b.battle.agents[1].search.random_state += 1
    }
    testing.expect(t, a.battle.agents[0].search.target == 0 && a.battle.agents[0].search.visit_count > 0)
}

@(test)
nearby_search_qa_produces_independent_target_alerts_from_focused_evidence :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    sim := battle_test_scenario(&catalog, map_id, 5, 42)
    sim.observe_only = false
    first: [2]u32
    for tick in 0..<1800 {
        advance(&sim, &catalog)
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
