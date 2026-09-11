package simulation

import "../content"

// Message kinds share the wire codec's values; the host codec decodes bytes into these commands.
Message_Kind :: enum u8 {
    Hello = 1, Welcome = 2, Session_State = 3,
    Start_Selection = 4, Select_Character = 5, Set_Ready = 6,
    Return_To_Lobby = 7, Command_Rejected = 8, Select_Arena = 9,
    Input = 10, World_State = 11, Dev_Reset_Search = 12,
}

Command_Reject_Reason :: enum u8 {
    None, Audience_Read_Only, Wrong_Phase, Stale_Round,
    Unknown_Character, Selection_Changed, Need_Two_Players, Unknown_Arena, Arena_Changed,
    Dev_Only, Search_Reset_Unavailable,
}

// What a welcomed connection may ask of the session. It never names an owner or a position.
Client_Command :: struct {
    kind: Message_Kind,
    wants_audience: bool,
    fingerprint: [32]u8,
    round_id: u32,
    character_id: u16,
    map_id: u16,
    ready: bool,
    input_sequence: u32,
    input_mask: u8,
}

@(private)
serial_is_newer :: proc(value, previous: u32) -> bool {
    distance := value - previous
    return distance > 0 && distance < 0x80000000
}

// Role comes from the welcomed connection, never from a command payload.
// A rejected command and a valid no-op both leave the revision unchanged.
session_apply :: proc(session: ^Session, catalog: ^content.Game_Content, player_id: u8, command: Client_Command, dev_search_enabled: bool = false) -> (changed: bool, rejection: Command_Reject_Reason) {
    if player_id == 0 || player_id > MAX_PLAYERS || !session.players[player_id - 1].present { return false, .Audience_Read_Only }
    if command.round_id != session.round_id { return false, .Stale_Round }
    if command.kind == .Dev_Reset_Search { return dev_search_reset(session, catalog, dev_search_enabled) }
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
        session.map_id = catalog.arenas[0].id
        session.round_id += 1
    } else {
        if session.phase != .Selecting { return false, .Wrong_Phase }
        player := &session.players[player_id - 1]
        #partial switch command.kind {
        case .Select_Character:
            if content.find_character(catalog, command.character_id) == nil { return false, .Unknown_Character }
            if player.character_id == command.character_id { return false, .None }
            player.character_id = command.character_id
            player.ready = false
        case .Select_Arena:
            if content.find_arena(catalog, command.map_id) == nil { return false, .Unknown_Arena }
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
