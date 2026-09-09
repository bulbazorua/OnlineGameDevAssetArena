package main

import "core:math"

SIMULATION_HZ :: 60
SNAPSHOT_INTERVAL :: 3 // 20 Hz; independent of rendering frequency.
CHARACTER_SPEED :: f32(180)
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
    result := position
    // Axis separation lets characters slide along walls.
    candidate := result + [2]f32{delta.x, 0}
    if arena_position_is_clear(arena, content, candidate, radius) { result = candidate }
    candidate = result + [2]f32{0, delta.y}
    if arena_position_is_clear(arena, content, candidate, radius) { result = candidate }
    return result
}

// Only this fixed step advances time and positions. Packets cannot buy more steps.
session_tick :: proc(session: ^Session, content: ^Game_Content) -> (session_changed: bool) {
    session.server_tick += 1
    if session.phase == .Countdown {
        previous := session_countdown_seconds(session)
        session.countdown_ticks -= 1
        if session.countdown_ticks == 0 {
            arena := content_arena(content, session.map_id)
            for player, index in session.players {
                session.next_entity_id += 1
                if session.next_entity_id == 0 { session.next_entity_id += 1 }
                session.characters[index] = Character{
                    entity_id = session.next_entity_id, definition_id = player.character_id,
                    owner_id = u8(index + 1), position = arena_cell_center(arena, arena.spawns[index]),
                }
            }
            session.character_count = MAX_PLAYERS
            session.phase = .In_Arena
        }
        if session_countdown_seconds(session) != previous {
            session.revision += 1
            return true
        }
    } else if session.phase == .In_Arena {
        arena := content_arena(content, session.map_id)
        for &character in session.characters {
            if character.input_age_ticks >= INPUT_TIMEOUT_TICKS {
                character.input_mask = 0
            } else {
                character.input_age_ticks += 1
            }
            definition := content_character(content, character.definition_id)
            character.position = character_move(character.position, character.input_mask, definition.footprint_radius, arena, content)
            character.applied_input_sequence = character.pending_input_sequence
        }
    }
    return false
}
