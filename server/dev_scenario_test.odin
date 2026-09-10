package main

import "core:testing"

@(test)
dev_scenario_waits_for_players_and_spawns_once :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    for &arena in content.arenas {
        for character in content.characters {
            for countdown in ([]u8{0, 5}) {
                session: Session
                scenario := Dev_Scenario{enabled = true, character_ids = {character.id, character.id}, map_id = arena.id, countdown_seconds = countdown}
                session_join(&session, true)
                session_join(&session, false)
                testing.expect(t, !dev_scenario_start(&scenario, &session, &content))
                testing.expect(t, !scenario.applied && session.phase == .Lobby)
                session_join(&session, false)
                testing.expect(t, dev_scenario_start(&scenario, &session, &content))
                testing.expect(t, session.map_id == arena.id && session.audience_count == 1 && session.round_id == 1)
                if countdown == 5 {
                    testing.expect(t, session.phase == .Countdown && session.character_count == 0)
                    for second in 0..<5 {
                        testing.expect(t, session_countdown_seconds(&session) == u8(5 - second))
                        for _ in 0..<60 { session_tick(&session, &content) }
                    }
                }
                testing.expect(t, session.phase == .In_Arena && session.character_count == 2)
                for entity, index in session.characters {
                    testing.expect(t, entity.definition_id == character.id && entity.owner_id == u8(index + 1))
                    testing.expect(t, session.trainers[index].position == arena_cell_center(&arena, arena.spawns[index]) && arena_position_is_clear(&arena, &content, entity.position, character.footprint_radius))
                }
                entity_id := session.characters[0].entity_id
                testing.expect(t, !dev_scenario_start(&scenario, &session, &content))
                testing.expect(t, session.characters[0].entity_id == entity_id)
                session_leave(&session, 1)
                session_join(&session, false)
                testing.expect(t, !dev_scenario_start(&scenario, &session, &content) && session.phase == .Lobby)
            }
        }
    }
}
