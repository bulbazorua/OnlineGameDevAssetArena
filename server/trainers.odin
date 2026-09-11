package main

import "core:math"

// Shared action/lifecycle constants for the first trainer style. Art remains client-only.
TRAINER_DEFINITION_ID :: u16(1)
TRAINER_RADIUS :: f32(9.6)
// Player1 plays its first two poses in two ticks each (plant at tick 4),
// then resumes normal clip speed. Keep a visible plant before translation.
TRAINER_WALK_START_TICKS :: u32(8)
SUMMON_DURATION_TICKS :: u16(90)
SUMMON_REVEAL_TICKS :: u16(36)
TRAINER_RUN_INPUT :: u8(16)
TRAINER_RUN_SPEED :: f32(240)
TRAINER_ENERGY_MAX :: u16(600)
TRAINER_RUN_COST :: u16(2)
TRAINER_RECOVERY_DELAY :: u8(60)
TRAINER_RECOVERY_THRESHOLD :: u16(120)
Trainer :: struct {
    using body: Character,
    energy: u16,
    energy_recovery_ticks: u8,
    run_exhausted: bool,
    movement_start_tick: u32,
}

trainer_tick_motion :: proc(trainer: ^Trainer, tick: u32, arena: ^Arena_Definition, content: ^Game_Content) {
    wants_run := trainer.input_mask & TRAINER_RUN_INPUT != 0
    if !wants_run && trainer.energy >= TRAINER_RECOVERY_THRESHOLD { trainer.run_exhausted = false }
    running := wants_run && !trainer.run_exhausted && trainer.energy >= TRAINER_RUN_COST
    speed := TRAINER_RUN_SPEED if running else CHARACTER_SPEED
    next := character_move(trainer.position, trainer.input_mask, TRAINER_RADIUS, arena, content, speed)
    delta := next - trainer.position
    locomotion: Character_Locomotion = .Walk if delta.x * delta.x + delta.y * delta.y > 0.000001 else .Idle
    if locomotion == .Walk && running { locomotion = .Run }
    if trainer.locomotion == .Idle && locomotion != .Idle { trainer.movement_start_tick = tick }
    if trainer.locomotion != locomotion {
        trainer.locomotion = locomotion
        trainer.state_start_tick = tick
    }
    moving := locomotion != .Idle && tick - trainer.movement_start_tick >= TRAINER_WALK_START_TICKS
    if locomotion != .Idle {
        angle := math.atan2(delta.x, -delta.y)
        trainer.facing = Character_Facing((int(math.round(angle / (math.PI / 4))) + 8) % 8)
        if moving { trainer.position = next }
    }
    trainer_tick_energy(trainer, moving && running)
}

trainer_tick_energy :: proc(trainer: ^Trainer, running: bool) {
    if running {
        trainer.energy -= TRAINER_RUN_COST
        trainer.energy_recovery_ticks = TRAINER_RECOVERY_DELAY
        if trainer.energy < TRAINER_RUN_COST { trainer.run_exhausted = true }
    } else if trainer.energy_recovery_ticks > 0 {
        trainer.energy_recovery_ticks -= 1
    } else {
        trainer.energy = min(TRAINER_ENERGY_MAX, trainer.energy + 1)
    }
}

session_next_entity :: proc(session: ^Session) -> u32 {
    session.next_entity_id += 1
    if session.next_entity_id == 0 { session.next_entity_id += 1 }
    return session.next_entity_id
}

// Prefer two cells toward the arena center, then nearby clear cells on the same
// elevation. Avoid both trainers and the other gladiator's reserved footprint.
summon_position :: proc(session: ^Session, content: ^Game_Content, index: int) -> [2]f32 {
    arena := content_arena(content, session.map_id)
    origin := arena.spawns[index]
    radius := content_character(content, session.players[index].character_id).footprint_radius
    direction := 1 if index == 0 else -1
    for distance in ([]int{2, 1, 3, 4}) {
        for y in -distance..=distance {
            for x in -distance..=distance {
                // Visit the forward cell first in each ring.
                cell := origin + [2]int{-x * direction, y}
                if y == -distance && x == -distance { cell = origin + [2]int{distance * direction, 0} }
                if arena_elevation_at(arena, cell) != arena_elevation_at(arena, origin) || !arena_spawn_is_clear(arena, content, cell, radius) { continue }
                position := arena_cell_center(arena, cell)
                separated := true
                for trainer in session.trainers {
                    delta := position - trainer.position
                    if math.sqrt(delta.x * delta.x + delta.y * delta.y) < radius + TRAINER_RADIUS + 8 { separated = false }
                }
                for previous in 0..<index {
                    delta := position - session.characters[previous].position
                    other_radius := content_character(content, session.characters[previous].definition_id).footprint_radius
                    if math.sqrt(delta.x * delta.x + delta.y * delta.y) < radius + other_radius + 8 { separated = false }
                }
                if separated { return position }
            }
        }
    }
    // Tiny custom maps can lack room for four separate footprints. The validated
    // original spawn is still land-safe; entity-to-entity collision is deferred.
    return arena_cell_center(arena, origin)
}
