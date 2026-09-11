package main

import "simulation"
import "core:testing"

@(test)
protocol_version_six_fixtures :: proc(t: ^testing.T) {
    hello: [39]u8
    protocol_header(hello[:], .Hello)
    hello[6] = 1
    hello[7] = 255
    command, valid := protocol_decode(hello[:], 0)
    testing.expect(t, valid && command.wants_audience && command.fingerprint[0] == 255)
    testing.expect(t, protocol_encode_welcome(2) == [11]u8{'O', 'G', 'A', 'A', 11, 2, 2, 0, 0, 0, 0})
    session := simulation.Session{round_id = 0x04030201, revision = 0x08070605, phase = .Selecting, map_id = 1, audience_count = 513,
        players = {{present = true, character_id = 4, ready = true}, {present = true, character_id = 3}}}
    expected := [32]u8{'O', 'G', 'A', 'A', 11, 3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 3, 1, 2, 1, 0, 4, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0}
    encoded := protocol_encode_session(&session)
    testing.expect(t, protocol_session_size(&session) == len(expected))
    for byte, index in expected { testing.expect(t, encoded[index] == byte) }
    select := [12]u8{'O', 'G', 'A', 'A', 11, 5, 1, 2, 3, 4, 4, 0}
    pick, pick_ok := protocol_decode(select[:], 0)
    testing.expect(t, pick_ok && pick.round_id == 0x04030201 && pick.character_id == 4)
    for length in 0..<len(hello) {
        _, accepted := protocol_decode(hello[:length], 0)
        testing.expect(t, !accepted)
    }
    for i in 0..<7 {
        corrupt := hello
        corrupt[i] = 99
        _, accepted := protocol_decode(corrupt[:], 0)
        testing.expect(t, !accepted)
    }
    _, wrong_channel := protocol_decode(hello[:], 1)
    testing.expect(t, !wrong_channel)
    ready := [13]u8{'O', 'G', 'A', 'A', 11, 6, 0, 0, 0, 0, 1, 0, 2}
    _, bad_bool := protocol_decode(ready[:], 0)
    testing.expect(t, !bad_bool)
}

@(test)
arena_command_wire_fixtures :: proc(t: ^testing.T) {
    request := [12]u8{'O', 'G', 'A', 'A', 11, 9, 1, 2, 3, 4, 2, 0}
    command, valid := protocol_decode(request[:], 0)
    testing.expect(t, valid && command.kind == .Select_Arena && command.round_id == 0x04030201 && command.map_id == 2)
    ready := [15]u8{'O', 'G', 'A', 'A', 11, 6, 1, 2, 3, 4, 4, 0, 2, 0, 1}
    command, valid = protocol_decode(ready[:], 0)
    testing.expect(t, valid && command.kind == .Set_Ready && command.character_id == 4 && command.map_id == 2 && command.ready)
    for length in 0..<len(ready) {
        _, accepted := protocol_decode(ready[:length], 0)
        testing.expect(t, !accepted)
    }
    ready[14] = 2
    _, accepted := protocol_decode(ready[:], 0)
    testing.expect(t, !accepted)
}

@(test)
movement_protocol_fixtures_and_channel_validation :: proc(t: ^testing.T) {
    input := [15]u8{'O', 'G', 'A', 'A', 11, 10, 1, 2, 3, 4, 9, 10, 11, 12, 6}
    command, valid := protocol_decode(input[:], 1)
    testing.expect(t, valid && command.round_id == 0x04030201 && command.input_sequence == 0x0c0b0a09 && command.input_mask == 6)
    _, valid = protocol_decode(input[:], 0)
    testing.expect(t, !valid)
    for length in 0..<len(input) { _, accepted := protocol_decode(input[:length], 1); testing.expect(t, !accepted) }
    input[14] = 32
    _, valid = protocol_decode(input[:], 1)
    testing.expect(t, !valid)
    session := simulation.Session{phase = .In_Arena, round_id = 0x04030201, server_tick = 0x08070605, character_count = 2, summon_elapsed_ticks = 90,
        characters = {
            {entity_id = 1, definition_id = 3, owner_id = 1, position = {144, 240}, locomotion = .Walk, facing = .East, state_start_tick = 0x08070600},
            {entity_id = 2, definition_id = 4, owner_id = 2, position = {496, 240}, facing = .West, state_start_tick = 0x07060504},
        }, trainers = {
            {entity_id = 3, definition_id = 1, owner_id = 1, position = {112, 240}, applied_input_sequence = 0x0c0b0a09, input_mask = 6, locomotion = .Walk, facing = .North_East, state_start_tick = 0x08070600,
                energy = 450, energy_recovery_ticks = 42, movement_start_tick = 0x08070600},
            {entity_id = 4, definition_id = 1, owner_id = 2, position = {528, 240}, facing = .West, state_start_tick = 0x07060504,
                energy = 75, run_exhausted = true, movement_start_tick = 0x07060500},
        }}
    expected := [147]u8{79, 71, 65, 65, 11, 11, 1, 2, 3, 4, 5, 6, 7, 8, 2, 1, 0, 0, 0, 3,
        0, 1, 0, 144, 0, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 4,
        0, 2, 0, 240, 1, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1,
        0, 1, 0, 112, 0, 0, 0, 240, 0, 0, 9, 10, 11, 12, 6, 4, 0, 0, 0, 1,
        0, 2, 0, 16, 2, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 90, 0, 1, 2, 0, 6, 7, 8, 0, 6, 4, 5, 6, 7,
        1, 1, 0, 6, 7, 8, 0, 6, 4, 5, 6, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        194, 1, 42, 0, 0, 6, 7, 8, 75, 0, 0, 1, 0, 5, 6, 7}
    testing.expect(t, protocol_encode_world(&session) == expected)
    testing.expect(t, protocol_session_size(&session) == 164)
}

@(test)
input_packet_carries_the_run_bit :: proc(t: ^testing.T) {
    packet := [15]u8{'O', 'G', 'A', 'A', 11, 10, 0, 0, 0, 0, 1, 0, 0, 0, 18}
    command, valid := protocol_decode(packet[:], 1)
    testing.expect(t, valid && command.input_mask == 18)
}

@(test)
search_reset_command_has_a_bounded_reliable_wire_contract :: proc(t: ^testing.T) {
    packet := [10]u8{'O', 'G', 'A', 'A', 11, 12, 1, 2, 3, 4}
    command, valid := protocol_decode(packet[:], 0)
    testing.expect(t, valid && command.kind == .Dev_Reset_Search && command.round_id == 0x04030201)
    _, valid = protocol_decode(packet[:], 1)
    testing.expect(t, !valid)
    for length in 0..<len(packet) {
        _, valid = protocol_decode(packet[:length], 0)
        testing.expect(t, !valid)
    }
    oversized: [11]u8
    copy(oversized[:], packet[:])
    _, valid = protocol_decode(oversized[:], 0)
    testing.expect(t, !valid)
}
