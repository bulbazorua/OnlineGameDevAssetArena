package main

import "core:math"

PROTOCOL_HEADER :: [5]u8{'O', 'G', 'A', 'A', 6}
Message_Kind :: enum u8 {
    Hello = 1, Welcome = 2, Session_State = 3,
    Start_Selection = 4, Select_Character = 5, Set_Ready = 6,
    Return_To_Lobby = 7, Command_Rejected = 8, Select_Arena = 9,
    Input = 10, World_State = 11,
}
Reject_Reason :: enum u32 { Protocol = 1, Content_Mismatch = 2 }
Command_Reject_Reason :: enum u8 {
    None, Audience_Read_Only, Wrong_Phase, Stale_Round,
    Unknown_Character, Selection_Changed, Need_Two_Players, Unknown_Arena, Arena_Changed,
}
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

protocol_read_u16 :: proc(bytes: []u8) -> u16 { return u16(bytes[0]) | u16(bytes[1]) << 8 }
protocol_read_u32 :: proc(bytes: []u8) -> u32 { return u32(bytes[0]) | u32(bytes[1]) << 8 | u32(bytes[2]) << 16 | u32(bytes[3]) << 24 }
protocol_write_u16 :: proc(bytes: []u8, value: u16) { for i in 0..<2 { bytes[i] = u8(value >> u8(i * 8) & 255) } }
protocol_write_u32 :: proc(bytes: []u8, value: u32) { for i in 0..<4 { bytes[i] = u8(value >> u8(i * 8) & 255) } }
protocol_header :: proc(bytes: []u8, kind: Message_Kind) { for byte, i in PROTOCOL_HEADER { bytes[i] = byte }; bytes[5] = u8(kind) }

protocol_decode :: proc(payload: []u8, channel: u8) -> (command: Client_Command, valid: bool) {
    if len(payload) < 6 { return {}, false }
    for value, index in PROTOCOL_HEADER { if payload[index] != value { return {}, false } }
    expected_channel: u8 = 0
    if payload[5] == u8(Message_Kind.Input) { expected_channel = 1 }
    if channel != expected_channel { return {}, false }
    switch payload[5] {
    case u8(Message_Kind.Hello):
        if len(payload) != 39 || payload[6] > 1 { return {}, false }
        command.kind = .Hello
        command.wants_audience = payload[6] == 1
        copy(command.fingerprint[:], payload[7:])
    case u8(Message_Kind.Start_Selection), u8(Message_Kind.Return_To_Lobby):
        if len(payload) != 10 { return {}, false }
        command.kind = Message_Kind(payload[5])
        command.round_id = protocol_read_u32(payload[6:])
    case u8(Message_Kind.Select_Character):
        if len(payload) != 12 { return {}, false }
        command.kind = .Select_Character
        command.round_id = protocol_read_u32(payload[6:])
        command.character_id = protocol_read_u16(payload[10:])
    case u8(Message_Kind.Set_Ready):
        if len(payload) != 15 || payload[14] > 1 { return {}, false }
        command.kind = .Set_Ready
        command.round_id = protocol_read_u32(payload[6:])
        command.character_id = protocol_read_u16(payload[10:])
        command.map_id = protocol_read_u16(payload[12:])
        command.ready = payload[14] == 1
    case u8(Message_Kind.Select_Arena):
        if len(payload) != 12 { return {}, false }
        command.kind = .Select_Arena
        command.round_id = protocol_read_u32(payload[6:])
        command.map_id = protocol_read_u16(payload[10:])
    case u8(Message_Kind.Input):
        if len(payload) != 15 || payload[14] > 15 { return {}, false }
        command.kind = .Input
        command.round_id = protocol_read_u32(payload[6:])
        command.input_sequence = protocol_read_u32(payload[10:])
        command.input_mask = payload[14]
    case: return {}, false
    }
    return command, true
}

protocol_encode_welcome :: proc(player_id: u8, audience_delay_ms: u32 = 0) -> (result: [11]u8) {
    protocol_header(result[:], .Welcome)
    result[6] = player_id
    protocol_write_u32(result[7:], audience_delay_ms)
    return
}

protocol_encode_session :: proc(session: ^Session) -> (result: [72]u8) {
    protocol_header(result[:], .Session_State)
    protocol_write_u32(result[6:], session.round_id)
    protocol_write_u32(result[10:], session.revision)
    result[14] = u8(session.phase)
    result[15] = session_player_mask(session)
    protocol_write_u16(result[16:], session.audience_count)
    protocol_write_u16(result[18:], session.map_id)
    result[26] = session_countdown_seconds(session)
    protocol_write_u32(result[27:], session.server_tick)
    result[31] = session.character_count
    for index in 0..<int(session.character_count) { protocol_write_character(result[32 + index * 20:], &session.characters[index]) }
    for player, index in session.players {
        offset := 20 + index * 3
        protocol_write_u16(result[offset:], player.character_id)
        result[offset + 2] = u8(player.ready)
    }
    return
}

protocol_encode_rejection :: proc(round_id: u32, kind: Message_Kind, reason: Command_Reject_Reason) -> (result: [12]u8) {
    protocol_header(result[:], .Command_Rejected)
    protocol_write_u32(result[6:], round_id)
    result[10] = u8(kind)
    result[11] = u8(reason)
    return
}

protocol_session_size :: proc(session: ^Session) -> int { return 32 + int(session.character_count) * 20 }

protocol_write_character :: proc(bytes: []u8, character: ^Character) {
    protocol_write_u32(bytes, character.entity_id)
    protocol_write_u16(bytes[4:], character.definition_id)
    bytes[6] = character.owner_id
    protocol_write_u32(bytes[7:], u32(math.round(character.position.x * 256)))
    protocol_write_u32(bytes[11:], u32(math.round(character.position.y * 256)))
    protocol_write_u32(bytes[15:], character.applied_input_sequence)
    bytes[19] = character.input_mask
}

protocol_encode_world :: proc(session: ^Session) -> (result: [55]u8) {
    assert(session.phase == .In_Arena && session.character_count == 2)
    protocol_header(result[:], .World_State)
    protocol_write_u32(result[6:], session.round_id)
    protocol_write_u32(result[10:], session.server_tick)
    result[14] = session.character_count
    for index in 0..<MAX_PLAYERS { protocol_write_character(result[15 + index * 20:], &session.characters[index]) }
    return
}
