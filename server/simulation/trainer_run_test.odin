package simulation

import "../content"
import "core:math"
import "core:testing"

trainer_run_test_ground :: proc(t: ^testing.T, catalog: ^content.Game_Content) -> ^content.Arena_Definition {
    testing.expect(t, content.load(catalog, "client/content/data"))
    arena := content.find_arena(catalog, 1)
    for &cell in arena.cells { cell = 1 }
    for &height in arena.elevations { height = 0 }
    return arena
}

@(test)
trainer_running_lasts_five_seconds_and_exhaustion_requires_recovery_and_release :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    arena := trainer_run_test_ground(t, &catalog)
    defer content.destroy(&catalog)
    trainer := Trainer{position = {256, 256}, energy = TRAINER_ENERGY_MAX}
    travelled: f32
    for step in u32(0)..<308 {
        trainer.input_mask = (u8(2) if (step / 75) % 2 == 0 else u8(1)) | TRAINER_RUN_INPUT
        previous := trainer.position
        trainer_tick_motion(&trainer, 100 + step, arena, &catalog)
        travelled += abs(trainer.position.x - previous.x)
        testing.expect(t, trainer.locomotion == .Run)
        if step < 8 { testing.expect(t, trainer.position == previous && trainer.energy == 600) }
        else { testing.expect(t, trainer.energy == 600 - u16(step - 7) * 2) }
    }
    testing.expect(t, travelled == 1200 && trainer.energy == 0 && trainer.run_exhausted)
    trainer.input_mask = 2 | TRAINER_RUN_INPUT
    previous := trainer.position
    trainer_tick_motion(&trainer, 408, arena, &catalog)
    testing.expect(t, trainer.locomotion == .Walk && trainer.position == previous + [2]f32{2, 0})
    for tick in u32(409)..<588 { trainer_tick_motion(&trainer, tick, arena, &catalog) }
    testing.expect(t, trainer.energy == 120 && trainer.run_exhausted && trainer.locomotion != .Run)
    trainer.input_mask = 2
    trainer_tick_motion(&trainer, 588, arena, &catalog)
    testing.expect(t, !trainer.run_exhausted && trainer.energy == 121)
    trainer.input_mask = 1 | TRAINER_RUN_INPUT
    trainer_tick_motion(&trainer, 589, arena, &catalog)
    testing.expect(t, trainer.locomotion == .Run)
}

@(test)
trainer_run_preserves_movement_clock_collision_and_stationary_energy :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    arena := trainer_run_test_ground(t, &catalog)
    defer content.destroy(&catalog)
    trainer := Trainer{position = {256, 256}, energy = 600, input_mask = 2}
    for tick in u32(100)..=108 { trainer_tick_motion(&trainer, tick, arena, &catalog) }
    testing.expect(t, trainer.position == [2]f32{258, 256} && trainer.energy == 600)
    trainer.input_mask = 2 | TRAINER_RUN_INPUT
    trainer_tick_motion(&trainer, 109, arena, &catalog)
    testing.expect(t, trainer.position == [2]f32{262, 256} && trainer.state_start_tick == 109 && trainer.movement_start_tick == 100 && trainer.energy == 598)
    trainer.input_mask = 2
    trainer_tick_motion(&trainer, 110, arena, &catalog)
    testing.expect(t, trainer.position == [2]f32{264, 256} && trainer.locomotion == .Walk && trainer.energy == 598)
    trainer = {position = {256, 256}, energy = 600, input_mask = 18, locomotion = .Run}
    trainer.input_mask |= 4
    trainer_tick_motion(&trainer, 10, arena, &catalog)
    delta := trainer.position - [2]f32{256, 256}
    testing.expect(t, abs(math.sqrt(delta.x * delta.x + delta.y * delta.y) - 4) < 0.001)
    for mask in ([]u8{16, 19, 28}) {
        trainer = {position = {256, 256}, energy = 600, input_mask = mask}
        for tick in u32(0)..<30 { trainer_tick_motion(&trainer, tick, arena, &catalog) }
        testing.expect(t, trainer.position == [2]f32{256, 256} && trainer.energy == 600 && trainer.locomotion == .Idle)
    }
    trainer = {position = {TRAINER_RADIUS, 256}, energy = 600, input_mask = 17}
    for tick in u32(0)..<30 { trainer_tick_motion(&trainer, tick, arena, &catalog) }
    testing.expect(t, trainer.position.x == TRAINER_RADIUS && trainer.energy == 600 && trainer.locomotion == .Idle)
    trainer = {position = {256, 256}, energy = 600, input_mask = 18}
    for age in u32(0)..=8 { trainer_tick_motion(&trainer, u32(0xfffffffc) + age, arena, &catalog) }
    testing.expect(t, trainer.position == [2]f32{260, 256} && trainer.energy == 598 && trainer.movement_start_tick == 0xfffffffc)
}

@(test)
trainer_energy_is_host_timed_private_to_each_trainer_and_reset_with_the_round :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    _ = trainer_run_test_ground(t, &catalog)
    defer content.destroy(&catalog)
    session: Session
    movement_test_ready(&session, &catalog)
    session_enter_arena(&session, &catalog)
    for sequence in u32(1)..=1000 {
        session_apply(&session, &catalog, 1, {kind = .Input, round_id = session.round_id, input_sequence = sequence, input_mask = 18})
    }
    testing.expect(t, session.trainers[0].energy == 600 && session.trainers[0].input_mask == 0)
    session.summon_elapsed_ticks = 90
    session_apply(&session, &catalog, 1, {kind = .Input, round_id = session.round_id, input_sequence = 1001, input_mask = 18})
    for _ in 0..<20 { session_tick(&session, &catalog) }
    testing.expect(t, session.trainers[0].energy == 586 && session.trainers[0].input_mask == 0 && session.trainers[0].locomotion == .Idle)
    testing.expect(t, session.trainers[1].energy == 600 && session.trainers[1].energy_recovery_ticks == 0)
    session.trainers[0].run_exhausted = true
    session_enter_arena(&session, &catalog)
    for trainer in session.trainers { testing.expect(t, trainer.energy == 600 && !trainer.run_exhausted && trainer.energy_recovery_ticks == 0) }
}
