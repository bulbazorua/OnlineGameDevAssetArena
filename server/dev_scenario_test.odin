package main

import "content"
import "simulation"
import "core:testing"

@(test)
dev_scenario_waits_for_players_and_spawns_once :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    for &arena in catalog.arenas {
        for character in catalog.characters {
            for countdown in ([]u8{0, 5}) {
                session: simulation.Session
                scenario := Dev_Scenario{enabled = true, character_ids = {character.id, character.id}, map_id = arena.id, countdown_seconds = countdown}
                simulation.session_join(&session, true)
                simulation.session_join(&session, false)
                testing.expect(t, !dev_scenario_start(&scenario, &session, &catalog))
                testing.expect(t, !scenario.applied && session.phase == .Lobby)
                simulation.session_join(&session, false)
                testing.expect(t, dev_scenario_start(&scenario, &session, &catalog))
                testing.expect(t, session.map_id == arena.id && session.audience_count == 1 && session.round_id == 1)
                if countdown == 5 {
                    testing.expect(t, session.phase == .Countdown && session.character_count == 0)
                    for second in 0..<5 {
                        testing.expect(t, simulation.session_countdown_seconds(&session) == u8(5 - second))
                        for _ in 0..<60 { simulation.session_tick(&session, &catalog) }
                    }
                }
                testing.expect(t, session.phase == .In_Arena && session.character_count == 2)
                for entity, index in session.characters {
                    testing.expect(t, entity.definition_id == character.id && entity.owner_id == u8(index + 1))
                    testing.expect(t, session.trainers[index].position == content.arena_cell_center(&arena, arena.spawns[index]) && content.arena_position_is_clear(&arena, &catalog, entity.position, character.footprint_radius))
                }
                entity_id := session.characters[0].entity_id
                testing.expect(t, !dev_scenario_start(&scenario, &session, &catalog))
                testing.expect(t, session.characters[0].entity_id == entity_id)
                simulation.session_leave(&session, 1)
                simulation.session_join(&session, false)
                testing.expect(t, !dev_scenario_start(&scenario, &session, &catalog) && session.phase == .Lobby)
            }
        }
    }
}
