package main

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

// Role comes from the welcomed connection, never from a command payload.
// A rejected command and a valid no-op both leave the revision unchanged.
session_apply :: proc(session: ^Session, content: ^Game_Content, player_id: u8, command: Client_Command, dev_search_enabled: bool = false) -> (changed: bool, rejection: Command_Reject_Reason) {
    if player_id == 0 || player_id > MAX_PLAYERS || !session.players[player_id - 1].present { return false, .Audience_Read_Only }
    if command.round_id != session.round_id { return false, .Stale_Round }
    if command.kind == .Dev_Reset_Search { return dev_search_reset(session, content, dev_search_enabled) }
    if command.kind == .Input {
        if session.phase != .In_Arena { return false, .Wrong_Phase }
        character := &session.trainers[player_id - 1]
        if serial_is_newer(command.input_sequence, character.pending_input_sequence) {
            character.pending_input_sequence = command.input_sequence
            character.input_mask = command.input_mask if session.summon_elapsed_ticks == SUMMON_DURATION_TICKS else 0
            character.input_age_ticks = 0
        }
        return false, .None
    }
    if command.kind == .Return_To_Lobby {
        if session.phase != .Countdown && session.phase != .In_Arena { return false, .Wrong_Phase }
        session_reset(session)
    } else if command.kind == .Start_Selection {
        if session.phase != .Lobby { return false, .Wrong_Phase }
        if session_player_mask(session) != 3 { return false, .Need_Two_Players }
        session.phase = .Selecting
        session.map_id = content.arenas[0].id
        session.round_id += 1
    } else {
        if session.phase != .Selecting { return false, .Wrong_Phase }
        player := &session.players[player_id - 1]
        #partial switch command.kind {
        case .Select_Character:
            if content_character(content, command.character_id) == nil { return false, .Unknown_Character }
            if player.character_id == command.character_id { return false, .None }
            player.character_id = command.character_id
            player.ready = false
        case .Select_Arena:
            if content_arena(content, command.map_id) == nil { return false, .Unknown_Arena }
            if session.map_id == command.map_id { return false, .None }
            session.map_id = command.map_id
            // The setting changed. Invalidate in-flight requests, even an A -> B -> A switch.
            session.round_id += 1
            for &slot in session.players { slot.ready = false }
        case .Set_Ready:
            if command.map_id != session.map_id { return false, .Arena_Changed }
            if player.character_id == 0 || command.character_id != player.character_id { return false, .Selection_Changed }
            if player.ready == command.ready { return false, .None }
            player.ready = command.ready
        case: return false, .Wrong_Phase
        }
    }
    if session.phase == .Selecting && session.players[0].ready && session.players[1].ready {
        session.phase = .Countdown
        session.countdown_ticks = 5 * SIMULATION_HZ
    }
    session.revision += 1
    return true, .None
}
