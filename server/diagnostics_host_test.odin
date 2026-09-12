package main

import "content"
import "diagnostics"
import "simulation"
import obs "observations"
import "perception"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"

// Host-side view of the diagnostics seam: the packets, captures and files the host
// hands over or reads back through host_simulation_step and the codec.

// An independent hex encoding, so the recording check does not trust the writer's own.
@(private = "file")
hex_string :: proc(bytes: []u8) -> string {
    builder := strings.builder_make()
    for b in bytes { fmt.sbprintf(&builder, "%02x", b) }
    return strings.to_string(builder)
}

@(test)
world_capture_receives_the_host_packet_and_owns_its_copy :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    debug := diagnostics.test_open_without_writer()
    defer free(debug)
    // The lobby fixture from the protocol tests: 32 valid bytes of a 164-byte array.
    lobby := simulation.Session{round_id = 0x04030201, revision = 0x08070605, phase = .Selecting, map_id = 1, audience_count = 513,
        players = {{present = true, character_id = 4, ready = true}, {present = true, character_id = 3}}}
    lobby_bytes := [32]u8{'O', 'G', 'A', 'A', 11, 3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 3, 1, 2, 1, 0, 4, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0}
    encoded := protocol_encode_session(&lobby)
    testing.expect(t, len(encoded) <= diagnostics.WORLD_PACKET_BYTES, "the codec's packet must fit the owned capture storage")
    host_capture_world(debug, &lobby)
    first, found := diagnostics.test_queued_world(debug, 0)
    testing.expect(t, found && first.packet_size == 32 && first.sequence == 1 && !first.senses.active)
    for byte, index in lobby_bytes { testing.expect(t, first.packet[index] == byte, "queued lobby packet differs from the wire fixture") }
    // An arena session fills the whole packet; the queued bytes equal the codec's output.
    sim := simulation.battle_test_scenario(&catalog, 1, 5)
    arena := protocol_encode_session(&sim.session)
    testing.expect(t, protocol_session_size(&sim.session) == 164)
    host_capture_world(debug, &sim.session)
    second, second_found := diagnostics.test_queued_world(debug, 1)
    testing.expect(t, second_found && second.sequence == 2 && second.packet_size == 164 && second.packet == arena)
    testing.expect(t, second.tick == sim.session.server_tick && second.round_id == sim.session.round_id && second.senses.active)
    testing.expect(t, second.senses.entities == {sim.session.characters[0].entity_id, sim.session.characters[1].entity_id})
}

@(test)
host_capture_stays_disabled_without_diagnostics :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    sim := simulation.battle_test_scenario(&catalog, 1, 5)
    before := sim
    host_capture_world(nil, &sim.session)
    testing.expect(t, sim == before, "an absent recorder must not touch the session")
    reference := sim
    for _ in 0..<120 {
        simulation.advance(&reference, &catalog)
        host_simulation_step(&sim, &catalog, nil, nil)
        testing.expect(t, sim.session == reference.session && sim.battle == reference.battle)
    }
    diagnostics.close(nil)
}

@(test)
scent_capture_follows_the_host_step_and_clears_when_the_arena_ends :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := simulation.battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    debug := diagnostics.test_open_without_writer()
    defer free(debug)
    sim := simulation.battle_test_scenario(&catalog, map_id, 5)
    for _ in 0..<300 { host_simulation_step(&sim, &catalog, nil, debug) }
    field := &sim.battle.scent.field
    // The capture follows field steps (10 Hz); compare right after a tick that stepped.
    for diagnostics.test_scent_capture(debug).tick != sim.session.server_tick { host_simulation_step(&sim, &catalog, nil, debug) }
    capture := diagnostics.test_scent_capture(debug)
    testing.expect(t, capture.valid && capture.round_id == sim.session.round_id && capture.width == field.width && capture.height == field.height)
    for class in obs.Scent_Class {
        for index in 0..<field.width * field.height {
            expected := u8(clamp(field.levels[class][index] * 255 + 0.5, 0, 255))
            testing.expect(t, capture.levels[class][index] == expected, "captured level differs from the live field")
        }
    }
    // Leaving the arena invalidates the capture instead of showing an old field.
    simulation.session_reset(&sim.session)
    host_simulation_step(&sim, &catalog, nil, debug)
    testing.expect(t, !diagnostics.test_scent_capture(debug).valid)
}

@(test)
debug_journals_rotate_and_shutdown_publishes_complete_history :: proc(t: ^testing.T) {
    when !ODIN_DEBUG {
        testing.expect(t, diagnostics.open("/tmp/unused-ai-test", "test", {}, int(PROTOCOL_HEADER[4])) == nil)
        return
    }
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    directory := fmt.aprintf("build/ai-debug-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug := diagnostics.open(directory, "test-run", catalog.fingerprint, int(PROTOCOL_HEADER[4]), &catalog, 4096, seed = 42)
    sim := simulation.battle_test_scenario(&catalog, 1, 5)
    sim.session.summon_elapsed_ticks = 90
    packets: [60][164]u8
    origin := sim.session.trainers[0].position
    for i in 0..<60 {
        simulation.session_apply(&sim.session, &catalog, 1, {kind = .Input, round_id = sim.session.round_id, input_sequence = u32(i + 1), input_mask = 2})
        host_simulation_step(&sim, &catalog, nil, debug)
        packets[i] = protocol_encode_session(&sim.session)
    }
    testing.expect(t, sim.session.trainers[0].position != origin)
    diagnostics.close(debug)
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary)
    defer mem.dynamic_arena_destroy(&temporary)
    for owner in 1..=2 {
        path := fmt.aprintf("%s/ai-%d.json", directory, owner)
        data, error := os.read_entire_file(path, context.allocator)
        testing.expect(t, error == nil)
        snapshot: diagnostics.Snapshot
        testing.expect(t, json.unmarshal(data, &snapshot, allocator = mem.dynamic_arena_allocator(&temporary)) == nil)
        testing.expect(t, snapshot.owner_id == owner && snapshot.run_id == "test-run" && len(snapshot.fingerprint) == 64 && snapshot.schema_version == diagnostics.TRACE_SCHEMA)
        testing.expect(t, len(snapshot.records) == 60 && snapshot.dropped_records == 0 && snapshot.oversized_records == 0 && snapshot.writer_error == "")
        testing.expect(t, snapshot.record_limit_bytes == diagnostics.RECORD_LIMIT)
        for record, i in snapshot.records {
            testing.expect(t, record.sequence == u64(i + 1) && record.owner_id == owner && record.schema_version == diagnostics.TRACE_SCHEMA)
            testing.expect(t, record.nodes[0].stage == .Input && record.nodes[len(record.nodes) - 1].stage == .Outcome)
            // The consumed eye sample, its writer-side fan and the separate host audit travel together.
            testing.expect(t, record.input.senses.vision.status == .Sampled && len(record.sight_fan) == perception.FAN_RAYS && record.host_audit.sample_id == record.input.senses.vision.sample_id)
            testing.expect(t, record.input.senses.vision.sample_tick <= record.input.tick && record.input.tick - record.input.senses.vision.sample_tick < 6)
        }
        journal := fmt.aprintf("%s/ai-%d.jsonl", directory, owner)
        journal_data, journal_error := os.read_entire_file(journal, context.allocator)
        testing.expect(t, journal_error == nil)
        for line in strings.split_lines(string(journal_data), context.temp_allocator) { testing.expect(t, len(line) <= diagnostics.RECORD_LIMIT) }
        delete(journal_data)
        delete(journal)
        rotated := fmt.aprintf("%s/ai-%d.jsonl.3", directory, owner)
        testing.expect(t, os.exists(rotated))
        delete(rotated)
        delete(data)
        delete(path)
    }
    replay_path := fmt.aprintf("%s/match.replay.jsonl", directory)
    defer delete(replay_path)
    replay_data, replay_error := os.read_entire_file(replay_path, context.allocator)
    defer delete(replay_data)
    testing.expect(t, replay_error == nil)
    lines := strings.split(string(replay_data), "\n")
    defer delete(lines)
    testing.expect(t, len(lines) == 63) // header, 60 frames, end, final newline
    if len(lines) != 63 { return }
    allocator := mem.dynamic_arena_allocator(&temporary)
    header: diagnostics.Replay_Header
    testing.expect(t, json.unmarshal(transmute([]u8)lines[0], &header, allocator = allocator) == nil)
    testing.expect(t, header.kind == "header" && header.seed == 42 && header.simulation_hz == 60 && header.protocol_version == int(PROTOCOL_HEADER[4]))
    testing.expect(t, header.schema_version == diagnostics.REPLAY_SCHEMA && header.trace_schema == diagnostics.TRACE_SCHEMA)
    for i in 0..<60 {
        frame: diagnostics.Replay_Frame
        testing.expect(t, json.unmarshal(transmute([]u8)lines[i + 1], &frame, allocator = allocator) == nil)
        expected := hex_string(packets[i][:])
        testing.expect(t, frame.kind == "frame" && frame.sequence == u64(i + 1) && frame.tick == u32(i + 1) && frame.packet_hex == expected)
        delete(expected)
        testing.expect(t, len(frame.ai) == 2)
        for record, owner in frame.ai {
            testing.expect(t, record.owner_id == owner + 1 && record.input.tick == frame.tick && record.input.round_id == sim.session.round_id)
        }
    }
    end: diagnostics.Replay_End
    testing.expect(t, json.unmarshal(transmute([]u8)lines[61], &end, allocator = allocator) == nil)
    testing.expect(t, end.kind == "end" && end.status == "complete" && end.frames == 60 && end.last_sequence == 60 && end.captured_frames == 60 && end.dropped_messages == 0 && end.oversized_frames == 0)
    fmt.printfln("[AI debugger] Journal fixture: %s", directory)
}
