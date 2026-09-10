package main

import "core:math"

SIMULATION_HZ :: 60
SNAPSHOT_INTERVAL :: 3 // 20 Hz; independent of rendering frequency.
CHARACTER_SPEED :: f32(120)
INPUT_TIMEOUT_TICKS :: 15

Character :: struct {
    entity_id: u32,
    definition_id: u16,
    owner_id: u8,
    position: [2]f32,
    pending_input_sequence: u32,
    applied_input_sequence: u32,
    input_mask: u8, // Left=1, Right=2, Up=4, Down=8.
    input_age_ticks: u16,
    locomotion: Character_Locomotion,
    facing: Character_Facing,
    state_start_tick: u32,
}

serial_is_newer :: proc(value, previous: u32) -> bool {
    distance := value - previous
    return distance > 0 && distance < 0x80000000
}

session_countdown_seconds :: proc(session: ^Session) -> u8 {
    return u8((session.countdown_ticks + SIMULATION_HZ - 1) / SIMULATION_HZ)
}

character_move :: proc(position: [2]f32, mask: u8, radius: f32, arena: ^Arena_Definition, content: ^Game_Content) -> [2]f32 {
    direction := [2]f32{f32((mask >> 1) & 1) - f32(mask & 1), f32((mask >> 3) & 1) - f32((mask >> 2) & 1)}
    length := math.sqrt(direction.x * direction.x + direction.y * direction.y)
    if length == 0 { return position }
    delta := direction * (CHARACTER_SPEED / SIMULATION_HZ / length)
    result, _ := movement_apply_delta(position, delta, radius, arena, content)
    return result
}

// Shared terrain mechanics. Trainers and autonomous characters supply their own speed.
movement_apply_delta :: proc(position, delta: [2]f32, radius: f32, arena: ^Arena_Definition, content: ^Game_Content) -> (result: [2]f32, blocked: bool) {
    result = position
    // Axis separation lets characters slide along walls.
    candidate := result + [2]f32{delta.x, 0}
    if arena_position_is_clear(arena, content, candidate, radius) && arena_step_is_allowed(arena, content, result, candidate) { result = candidate } else if delta.x != 0 { blocked = true }
    candidate = result + [2]f32{0, delta.y}
    if arena_position_is_clear(arena, content, candidate, radius) && arena_step_is_allowed(arena, content, result, candidate) { result = candidate } else if delta.y != 0 { blocked = true }
    return
}

// Only this fixed step advances time and positions. Packets cannot buy more steps.
session_tick :: proc(session: ^Session, content: ^Game_Content) -> (session_changed: bool) {
    session.server_tick += 1
    if session.phase == .Countdown {
        previous := session_countdown_seconds(session)
        session.countdown_ticks -= 1
        if session.countdown_ticks == 0 {
            session_enter_arena(session, content)
        }
        if session_countdown_seconds(session) != previous {
            session.revision += 1
            return true
        }
    } else if session.phase == .In_Arena {
        arena := content_arena(content, session.map_id)
        summoning := session.summon_elapsed_ticks < SUMMON_DURATION_TICKS
        if summoning { session.summon_elapsed_ticks += 1 }
        for &character in session.trainers {
            if character.input_age_ticks >= INPUT_TIMEOUT_TICKS {
                character.input_mask = 0
            } else {
                character.input_age_ticks += 1
            }
            if summoning { character.input_mask = 0 }
            trainer_tick_motion(&character, session.server_tick, arena, content)
            character.applied_input_sequence = character.pending_input_sequence
        }
    }
    return false
}

// Both normal countdown and development scenarios enter through this path.
session_enter_arena :: proc(session: ^Session, content: ^Game_Content) {
    assert(session_player_mask(session) == 3)
    arena := content_arena(content, session.map_id)
    assert(arena != nil)
    session.summon_elapsed_ticks = 0
    for index in 0..<MAX_PLAYERS {
        session.trainers[index] = Trainer{
            entity_id = session_next_entity(session), definition_id = TRAINER_DEFINITION_ID,
            owner_id = u8(index + 1), position = arena_cell_center(arena, arena.spawns[index]),
            facing = .East if index == 0 else .West, state_start_tick = session.server_tick,
        }
    }
    for player, index in session.players {
        assert(player.ready && content_character(content, player.character_id) != nil)
        session.characters[index] = Character{
            entity_id = session_next_entity(session), definition_id = player.character_id,
            owner_id = u8(index + 1), position = summon_position(session, content, index),
            facing = .East if index == 0 else .West, state_start_tick = session.server_tick,
        }
    }
    session.countdown_ticks = 0
    session.character_count = MAX_PLAYERS
    session.phase = .In_Arena
}
