package diagnostics

import "../simulation"
import "core:testing"

@(test)
world_capture_owns_a_copy_of_the_host_packet_and_its_valid_length :: proc(t: ^testing.T) {
    debug := test_open_without_writer()
    defer free(debug)
    session: simulation.Session
    session.server_tick, session.round_id, session.map_id = 9, 3, 2
    session.phase, session.character_count = .In_Arena, simulation.MAX_PLAYERS
    session.characters[0].entity_id, session.characters[1].entity_id = 40, 41
    packet: [WORLD_PACKET_BYTES]u8
    for &byte, index in packet { byte = u8(index * 7 + 1) }
    expected := packet
    capture_world(debug, &session, packet[:])
    // The caller's buffer dies or changes after the call; the queued copy must not.
    for &byte in packet { byte = 0 }
    first, found := test_queued_world(debug, 0)
    testing.expect(t, found && first.sequence == 1 && first.tick == 9 && first.round_id == 3)
    testing.expect(t, first.packet_size == WORLD_PACKET_BYTES && first.packet == expected, "the full packet is copied byte for byte")
    testing.expect(t, first.senses.active && first.senses.round_id == 3 && first.senses.map_id == 2 && first.senses.entities == {40, 41})
    // A lobby-sized packet keeps its shorter valid length; nothing beyond it is the host's.
    session.phase, session.character_count = .Lobby, 0
    capture_world(debug, &session, expected[:32])
    second, second_found := test_queued_world(debug, 1)
    testing.expect(t, second_found && second.sequence == 2 && second.packet_size == 32 && !second.senses.active)
    for index in 0..<32 { testing.expect(t, second.packet[index] == expected[index]) }
    testing.expect(t, debug.world_sequence == 2 && debug.count == 2 && debug.dropped == 0)
}

@(test)
absent_diagnostics_accept_every_operation_without_touching_the_caller :: proc(t: ^testing.T) {
    sim: simulation.Simulation
    sim.session.server_tick, sim.session.round_id = 4, 1
    before := sim
    packet: [WORLD_PACKET_BYTES]u8
    requests: [simulation.MAX_PLAYERS]simulation.Brain_Request
    responses: [simulation.MAX_PLAYERS]simulation.Brain_Response
    outcomes: [simulation.MAX_PLAYERS]simulation.Decision_Outcome
    capture_world(nil, &sim.session, packet[:])
    capture_scent(nil, &sim.battle, &sim.session)
    record_decisions(nil, &sim, requests, &responses, outcomes)
    close(nil)
    testing.expect(t, sim == before, "a disabled recorder must leave the simulation alone")
    for response in responses { testing.expect(t, response.trace.count == 0, "no confirmed outcome is appended without a recorder") }
}
