package main

import "core:testing"
import "core:time"

@(test)
trainers_summon_selected_gladiators_on_land_and_own_input :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    for &arena in content.arenas {
        for pick in content.characters {
            session := Session{map_id = arena.id}
            for &player in session.players { player = {present = true, character_id = pick.id, ready = true} }
            session_enter_arena(&session, &content)
            testing.expect(t, session.summon_elapsed_ticks == 0 && session.character_count == 2)
            for index in 0..<2 {
                trainer, gladiator := session.trainers[index], session.characters[index]
                testing.expect(t, trainer.definition_id == TRAINER_DEFINITION_ID && trainer.owner_id == gladiator.owner_id)
                testing.expect(t, gladiator.definition_id == pick.id && trainer.entity_id != gladiator.entity_id)
                testing.expect(t, trainer.position == arena_cell_center(&arena, arena.spawns[index]))
                testing.expect(t, arena_position_is_clear(&arena, &content, trainer.position, TRAINER_RADIUS))
                testing.expect(t, arena_position_is_clear(&arena, &content, gladiator.position, pick.footprint_radius))
                testing.expect(t, trainer.position != gladiator.position && session.characters[0].position != session.characters[1].position)
                testing.expect(t, arena_elevation_at(&arena, arena_world_to_cell(&arena, trainer.position)) == arena_elevation_at(&arena, arena_world_to_cell(&arena, gladiator.position)))
            }
            testing.expect(t, session.trainers[0].entity_id != session.trainers[1].entity_id && session.characters[0].entity_id != session.characters[1].entity_id)
            trainer_start := session.trainers[0].position
            gladiators := session.characters
            stream := audience_init(5000)
            audience_advance(&stream, &session, 0)
            for tick in u16(0)..<SUMMON_DURATION_TICKS {
                session_apply(&session, &content, 1, {kind = .Input, round_id = session.round_id, input_sequence = u32(tick + 1), input_mask = 2})
                session_tick(&session, &content)
                testing.expect(t, session.summon_elapsed_ticks == tick + 1 && session.trainers[0].position == trainer_start)
                testing.expect(t, session.characters == gladiators)
            }
            testing.expect(t, !audience_advance(&stream, &session, 4999 * time.Millisecond))
            testing.expect(t, audience_advance(&stream, &session, 5000 * time.Millisecond))
            testing.expect(t, stream.latest.summon_elapsed_ticks == 0 && stream.latest.trainers[0].position == trainer_start && stream.latest.characters == gladiators)
            audience_destroy(&stream)
            for step in u32(0)..=8 {
                session_apply(&session, &content, 1, {kind = .Input, round_id = session.round_id, input_sequence = 100 + step, input_mask = 2})
                session_tick(&session, &content)
                testing.expect(t, session.trainers[0].locomotion == .Walk && session.trainers[0].state_start_tick == 91)
                if step < 8 { testing.expect(t, session.trainers[0].position == trainer_start) }
            }
            testing.expect(t, session.trainers[0].position == trainer_start + [2]f32{2, 0})
            testing.expect(t, session.characters == gladiators && session.summon_elapsed_ticks == SUMMON_DURATION_TICKS)
            session_reset(&session)
            testing.expect(t, session.character_count == 0 && session.summon_elapsed_ticks == 0 && session.trainers[0].entity_id == 0 && session.characters[0].entity_id == 0)
        }
    }
}
