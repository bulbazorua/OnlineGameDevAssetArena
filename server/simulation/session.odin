package simulation

import "core:math"
import "../content"

MAX_PLAYERS :: 2

Session_Phase :: enum u8 { Lobby, Selecting, Countdown, In_Arena }

Player_Slot :: struct {
    present: bool,
    character_id: u16,
    ready: bool,
}

Session :: struct {
    players: [MAX_PLAYERS]Player_Slot,
    audience_count: u16,
    phase: Session_Phase,
    round_id: u32,
    revision: u32,
    map_id: u16,
    countdown_ticks: u16,
    server_tick: u32,
    next_entity_id: u32,
    characters: [MAX_PLAYERS]Character,
    trainers: [MAX_PLAYERS]Trainer,
    summon_elapsed_ticks: u16,
    character_count: u8,
}

session_reset :: proc(session: ^Session) {
    session.phase = .Lobby
    session.map_id = 0
    session.round_id += 1
    session.countdown_ticks = 0
    session.characters = {}
    session.trainers = {}
    session.summon_elapsed_ticks = 0
    session.character_count = 0
    for &player in session.players {
        player.character_id = 0
        player.ready = false
    }
}

session_join :: proc(session: ^Session, wants_audience: bool) -> u8 {
    session.revision += 1
    if !wants_audience {
        for &player, index in session.players {
            if !player.present {
                player.present = true
                return u8(index + 1)
            }
        }
    }
    session.audience_count += 1
    return 0
}

// The connection owner calls this exactly once for each joined connection.
session_leave :: proc(session: ^Session, player_id: u8) {
    if player_id == 0 {
        assert(session.audience_count > 0)
        session.audience_count -= 1
    } else {
        assert(player_id <= MAX_PLAYERS && session.players[player_id - 1].present)
        session.players[player_id - 1].present = false
        session_reset(session)
    }
    session.revision += 1
}

session_player_mask :: proc(session: ^Session) -> u8 {
    mask: u8
    for player, index in session.players {
        if player.present { mask |= u8(1) << u8(index) }
    }
    return mask
}

session_countdown_seconds :: proc(session: ^Session) -> u8 {
    return u8((session.countdown_ticks + SIMULATION_HZ - 1) / SIMULATION_HZ)
}

// Only this fixed step advances time and positions. Packets cannot buy more steps.
session_tick :: proc(session: ^Session, catalog: ^content.Game_Content) -> (session_changed: bool) {
    session.server_tick += 1
    if session.phase == .Countdown {
        previous := session_countdown_seconds(session)
        session.countdown_ticks -= 1
        if session.countdown_ticks == 0 {
            session_enter_arena(session, catalog)
        }
        if session_countdown_seconds(session) != previous {
            session.revision += 1
            return true
        }
    } else if session.phase == .In_Arena {
        arena := content.find_arena(catalog, session.map_id)
        summoning := session.summon_elapsed_ticks < SUMMON_DURATION_TICKS
        if summoning { session.summon_elapsed_ticks += 1 }
        for &character in session.trainers {
            if character.input_age_ticks >= INPUT_TIMEOUT_TICKS {
                character.input_mask = 0
            } else {
                character.input_age_ticks += 1
            }
            if summoning { character.input_mask = 0 }
            trainer_tick_motion(&character, session.server_tick, arena, catalog)
            character.applied_input_sequence = character.pending_input_sequence
        }
    }
    return false
}

// Both normal countdown and development scenarios enter through this path.
session_enter_arena :: proc(session: ^Session, catalog: ^content.Game_Content) {
    assert(session_player_mask(session) == 3)
    arena := content.find_arena(catalog, session.map_id)
    assert(arena != nil)
    session.summon_elapsed_ticks = 0
    for index in 0..<MAX_PLAYERS {
        session.trainers[index] = Trainer{
            body = {entity_id = session_next_entity(session), definition_id = TRAINER_DEFINITION_ID,
                owner_id = u8(index + 1), position = content.arena_cell_center(arena, arena.spawns[index]),
                facing = .East if index == 0 else .West, state_start_tick = session.server_tick},
            energy = TRAINER_ENERGY_MAX, movement_start_tick = session.server_tick,
        }
    }
    for player, index in session.players {
        assert(player.ready && content.find_character(catalog, player.character_id) != nil)
        session.characters[index] = Character{
            entity_id = session_next_entity(session), definition_id = player.character_id,
            owner_id = u8(index + 1), position = summon_position(session, catalog, index),
            facing = .East if index == 0 else .West, state_start_tick = session.server_tick,
        }
    }
    session.countdown_ticks = 0
    session.character_count = MAX_PLAYERS
    session.phase = .In_Arena
}

// Development entry: both fighters count as picked and ready, then the arena is
// entered at once or after the usual countdown. Normal play gets here through commands.
session_start_match :: proc(session: ^Session, catalog: ^content.Game_Content, character_ids: [MAX_PLAYERS]u16, map_id: u16, countdown_seconds: u8) {
    session.round_id += 1
    session.revision += 1
    session.map_id = map_id
    for &player, index in session.players {
        player.character_id = character_ids[index]
        player.ready = true
    }
    if countdown_seconds == 0 {
        session_enter_arena(session, catalog)
    } else {
        session.phase = .Countdown
        session.countdown_ticks = u16(countdown_seconds) * SIMULATION_HZ
    }
}

@(private)
session_next_entity :: proc(session: ^Session) -> u32 {
    session.next_entity_id += 1
    if session.next_entity_id == 0 { session.next_entity_id += 1 }
    return session.next_entity_id
}

// Prefer two cells toward the arena center, then nearby clear cells on the same
// elevation. Avoid both trainers and the other gladiator's reserved footprint.
@(private)
summon_position :: proc(session: ^Session, catalog: ^content.Game_Content, index: int) -> [2]f32 {
    arena := content.find_arena(catalog, session.map_id)
    origin := arena.spawns[index]
    radius := content.find_character(catalog, session.players[index].character_id).footprint_radius
    direction := 1 if index == 0 else -1
    for distance in ([]int{2, 1, 3, 4}) {
        for y in -distance..=distance {
            for x in -distance..=distance {
                // Visit the forward cell first in each ring.
                cell := origin + [2]int{-x * direction, y}
                if y == -distance && x == -distance { cell = origin + [2]int{distance * direction, 0} }
                if content.arena_elevation_at(arena, cell) != content.arena_elevation_at(arena, origin) || !content.arena_spawn_is_clear(arena, catalog, cell, radius) { continue }
                position := content.arena_cell_center(arena, cell)
                separated := true
                for trainer in session.trainers {
                    delta := position - trainer.position
                    if math.sqrt(delta.x * delta.x + delta.y * delta.y) < radius + TRAINER_RADIUS + 8 { separated = false }
                }
                for previous in 0..<index {
                    delta := position - session.characters[previous].position
                    other_radius := content.find_character(catalog, session.characters[previous].definition_id).footprint_radius
                    if math.sqrt(delta.x * delta.x + delta.y * delta.y) < radius + other_radius + 8 { separated = false }
                }
                if separated { return position }
            }
        }
    }
    // Tiny custom maps can lack room for four separate footprints. The validated
    // original spawn is still land-safe; entity-to-entity collision is deferred.
    return content.arena_cell_center(arena, origin)
}
