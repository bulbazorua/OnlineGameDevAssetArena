package main

import "content"
import "simulation"
import ai "ai"
import obs "observations"
import "perception"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

@(test)
dedicated_brains_match_serial_simulation_and_use_distinct_threads :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    // No writer: a full diagnostics queue also exercises non-blocking trace loss.
    debug := new(AI_Debug)
    defer free(debug)
    debug.origin = time.tick_now()
    for &arena in catalog.arenas {
        a := simulation.battle_test_scenario(&catalog, arena.id, 5, 71)
        b := a
        for tick in u32(1)..<700 {
            if tick % 3 == 0 {
                command := simulation.Client_Command{kind = .Input, round_id = a.session.round_id, input_sequence = tick, input_mask = 2}
                simulation.session_apply(&a.session, &catalog, 1, command)
                simulation.session_apply(&b.session, &catalog, 1, command)
            }
            simulation.advance(&a, &catalog)
            host_simulation_step(&b, &catalog, workers, debug)
            testing.expect(t, a.session == b.session && a.battle == b.battle)
        }
        id1, id2 := workers.slots[0].response.worker_id, workers.slots[1].response.worker_id
        testing.expect(t, id1 != id2 && id1 != sync.current_thread_id() && id2 != sync.current_thread_id())
        simulation.session_reset(&a.session)
        simulation.session_reset(&b.session)
        simulation.advance(&a, &catalog)
        host_simulation_step(&b, &catalog, workers, debug)
        testing.expect(t, a.battle == simulation.Battle_Runtime{} && b.battle == simulation.Battle_Runtime{})
    }
    testing.expect(t, debug.count == AI_DEBUG_QUEUE && debug.dropped > 0)
}

@(test)
second_brain_completes_without_collecting_first_brain :: proc(t: ^testing.T) {
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    for i in 0..<2 {
        brain_worker_submit(&workers.slots[i], {agent = ai.agent_reset(u32(i + 1), 2),
            ctx = {entity_id = u32(i + 1), round_id = 2, tick = 30, can_act = true, turn_ready = true}, config = ai.observe_defaults(), trace = true})
    }
    second := brain_worker_collect(&workers.slots[1])
    testing.expect(t, workers.slots[0].busy && !workers.slots[1].busy && second.agent.entity_id == 2)
    first := brain_worker_collect(&workers.slots[0])
    testing.expect(t, first.worker_id != second.worker_id)
    testing.expect(t, first.trace.nodes[0].thread_id == first.worker_id && second.trace.nodes[0].thread_id == second.worker_id)
}

@(test)
debug_journals_rotate_and_shutdown_publishes_complete_history :: proc(t: ^testing.T) {
    when !ODIN_DEBUG {
        testing.expect(t, ai_debug_open("/tmp/unused-ai-test", "test", {}) == nil)
        return
    }
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    directory := fmt.aprintf("build/ai-debug-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug := ai_debug_open(directory, "test-run", catalog.fingerprint, &catalog, 4096, seed = 42)
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
    ai_debug_close(debug)
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary)
    defer mem.dynamic_arena_destroy(&temporary)
    for owner in 1..=2 {
        path := fmt.aprintf("%s/ai-%d.json", directory, owner)
        data, error := os.read_entire_file(path, context.allocator)
        testing.expect(t, error == nil)
        snapshot: AI_Debug_Snapshot
        testing.expect(t, json.unmarshal(data, &snapshot, allocator = mem.dynamic_arena_allocator(&temporary)) == nil)
        testing.expect(t, snapshot.owner_id == owner && snapshot.run_id == "test-run" && len(snapshot.fingerprint) == 64 && snapshot.schema_version == AI_DEBUG_SCHEMA)
        testing.expect(t, len(snapshot.records) == 60 && snapshot.dropped_records == 0 && snapshot.oversized_records == 0 && snapshot.writer_error == "")
        testing.expect(t, snapshot.record_limit_bytes == AI_DEBUG_RECORD_LIMIT)
        for record, i in snapshot.records {
            testing.expect(t, record.sequence == u64(i + 1) && record.owner_id == owner && record.schema_version == AI_DEBUG_SCHEMA)
            testing.expect(t, record.nodes[0].stage == .Input && record.nodes[len(record.nodes) - 1].stage == .Outcome)
            // The consumed eye sample, its writer-side fan and the separate host audit travel together.
            testing.expect(t, record.input.senses.vision.status == .Sampled && len(record.sight_fan) == perception.FAN_RAYS && record.host_audit.sample_id == record.input.senses.vision.sample_id)
            testing.expect(t, record.input.senses.vision.sample_tick <= record.input.tick && record.input.tick - record.input.senses.vision.sample_tick < 6)
        }
        journal := fmt.aprintf("%s/ai-%d.jsonl", directory, owner)
        journal_data, journal_error := os.read_entire_file(journal, context.allocator)
        testing.expect(t, journal_error == nil)
        for line in strings.split_lines(string(journal_data), context.temp_allocator) { testing.expect(t, len(line) <= AI_DEBUG_RECORD_LIMIT) }
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
    header: Replay_Header
    testing.expect(t, json.unmarshal(transmute([]u8)lines[0], &header, allocator = allocator) == nil)
    testing.expect(t, header.kind == "header" && header.seed == 42 && header.simulation_hz == 60 && header.protocol_version == int(PROTOCOL_HEADER[4]))
    testing.expect(t, header.schema_version == REPLAY_SCHEMA && header.trace_schema == AI_DEBUG_SCHEMA)
    for i in 0..<60 {
        frame: Replay_Frame
        testing.expect(t, json.unmarshal(transmute([]u8)lines[i + 1], &frame, allocator = allocator) == nil)
        expected := ai_debug_hex(packets[i][:])
        testing.expect(t, frame.kind == "frame" && frame.sequence == u64(i + 1) && frame.tick == u32(i + 1) && frame.packet_hex == expected)
        delete(expected)
        testing.expect(t, len(frame.ai) == 2)
        for record, owner in frame.ai {
            testing.expect(t, record.owner_id == owner + 1 && record.input.tick == frame.tick && record.input.round_id == sim.session.round_id)
        }
    }
    end: Replay_End
    testing.expect(t, json.unmarshal(transmute([]u8)lines[61], &end, allocator = allocator) == nil)
    testing.expect(t, end.kind == "end" && end.status == "complete" && end.frames == 60 && end.last_sequence == 60 && end.captured_frames == 60 && end.dropped_messages == 0 && end.oversized_frames == 0)
    fmt.printfln("[AI debugger] Journal fixture: %s", directory)
}

// Builds a record with every array full and every field at a realistic maximum:
// world-sized coordinates, 32-bit ticks, the longest enum names and labels.
@(private = "file")
extreme_record :: proc(absurd_floats: bool) -> AI_Debug_Record {
    wide := f32(-1234.5677)
    widest := f64(4294967295)
    if absurd_floats { wide, widest = f32(-1.1754944e-38), f64(-1.7976931348623157e+308) }
    point := obs.Vector{wide, wide}
    record: AI_Debug_Record
    record.owner_id, record.definition_id, record.map_id = 2, 65535, 65535
    record.sequence, record.worker_id = 0xffffffffffffffff, 0x7fffffff
    record.queued_us, record.started_us, record.finished_us = 9999999999, 9999999999, 9999999999
    sample := &record.input.senses.vision
    sample^ = {sample_id = 0xffffffff, observer = 0xffffffff, round_id = 0xffffffff, sample_tick = 0xffffffff, delivered_tick = 0xffffffff,
        status = .Sampled, pose = {point, .North_West}, profile = {true, wide, wide, wide, 0xffffffff}, focused_count = 3, cue_count = 3}
    for &sighting in sample.focused { sighting = {0xffffffff, 0xffffffff, .Creature, 65535, point, .North_West, .Walk} }
    for &cue in sample.cues { cue = {0xffffffff, 255, .Near} }
    record.input.senses.vision_is_new = true
    nose := &record.input.senses.olfaction
    nose^ = {sample_id = 0xffffffff, observer = 0xffffffff, round_id = 0xffffffff, sample_tick = 0xffffffff, delivered_tick = 0xffffffff,
        position = point, profile = {true, wide, 0xffffffff, true}, status = .Sampled, reading_count = len(nose.readings)}
    for &reading in nose.readings {
        reading = {observation_id = 0xffffffff, class = .Orc, strength = .Medium, freshness = .Very_Recent, bearing_valid = true, bearing = .North_West}
        for &zone in reading.zones { zone = .Medium }
    }
    for &zone in nose.coverage { zone = .Unsampled }
    record.input.senses.olfaction_is_new = true
    record.input = {entity_id = 0xffffffff, round_id = 0xffffffff, tick = 0xffffffff, position = point, facing = .North_West, can_act = true, turn_ready = true,
        senses = record.input.senses, own_emitter = {true, .Human, wide}}
    for agent in ([]^ai.Agent{&record.before, &record.after}) {
        agent^ = {entity_id = 0xffffffff, round_id = 0xffffffff}
        agent.search = {profile = ai.search_defaults(), state = .Last_Known_Position, transition = .Investigation_Abandoned,
            random_state = 0xffffffff, leg_deadline = 0xffffffff, scored_tick = 0xffffffff, state_tick = 0xffffffff,
            scored_position = point, position = point, blocked_origin = point, center = point, cue_origin = point, target_position = point,
            visit_count = ai.SEARCH_MEMORY_CAPACITY, evidence = .Focused_Memory, evidence_tick = 0xffffffff,
            observation_id = 0xffffffff, target = 0xffffffff, target_tick = 0xffffffff, acquired_tick = 0xffffffff,
            acquisition_count = 0xffffffff, relocation_count = 0xffffffff, abandoned_count = 0xffffffff,
            blocked_count = 0xffffffff, weak_episode_tick = 0xffffffff, ignore_cues_until = 0xffffffff}
        for &visit in agent.search.visits { visit = {point, 0xffffffff, true} }
        for &choice in agent.search.choices { choice = {wide, wide, wide, wide, wide, wide, wide} }
        for &deadline in agent.search.blocked_until { deadline = 0xffffffff }
        agent.search.scent = {true, .Orc, .Medium, .Very_Recent, true, .North_West, 0xffffffff, 0xffffffff, 0x7fffffff}
        agent.search.scent_episodes, agent.search.cue_from_scent = 0xffffffff, true
        agent.scent = {count = len(agent.scent.entries), last_sample_id = 0xffffffff, last_sample_tick = 0xffffffff, ingested_samples = 0xffffffff, last_sample_empty = true}
        for &entry in agent.scent.entries {
            entry = {class = .Orc, strength = .Medium, freshness = .Very_Recent, bearing_valid = true, bearing = .North_West, origin = point, range = wide,
                observed_tick = 0xffffffff, expires_tick = 0xffffffff, sample_id = 0xffffffff, observation_id = 0xffffffff}
            for &zone in entry.zones { zone = .Medium }
        }
        agent.memory = {focused_count = 3, cue_count = 3, last_sample_id = 0xffffffff, ingested_samples = 0xffffffff}
        for &entry in agent.memory.focused { entry = {0xffffffff, .Creature, 65535, point, .North_West, .Walk, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff} }
        for &entry in agent.memory.cues { entry = {255, .Near, .North_West, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff} }
        agent.attention = {.Reacquire, .Focused_Memory, 0xffffffff, 0xffffffff, 0xffffffff, .North_West, 0xffffffff, true}
        agent.intent = {.Face, point, .North_West}
        agent.last = {0xffffffff, .Reacquire, {.Face, point, .North_West}, {.Invalid_Request, point, .North_West}}
    }
    record.decision_reason, record.result = .Reacquire, {.Invalid_Request, point, .North_West}
    record.position_after, record.facing_after, record.facing = point, 255, 255
    record.config = {{0xffffffff, 0xffffffff}, 0xffffffff, 0x7fffffffffffffff}
    record.audit = {sample_id = 0xffffffff, origin_opaque = true, candidate_count = 3, sight_tests = 0x7fffffff, merged_cues = 0x7fffffff}
    for &entry in record.audit.candidates { entry = {0xffffffff, .Outside_Field, wide, wide, point} }
    record.scent_audit = {sample_id = 0xffffffff, cells_sampled = 0x7fffffff, cells_blind = 0x7fffffff, cells_excluded = 0x7fffffff}
    for class in obs.Scent_Class {
        record.scent_audit.peak[class], record.scent_audit.newest_age_ticks[class], record.scent_audit.coherence[class] = wide, 0xffffffff, wide
        record.scent_audit.newest_detectable_age_ticks[class] = 0xffffffff
    }
    record.fan_count = perception.FAN_RAYS
    for &point_out in record.fan { point_out = point }
    longest := "Select attention: nearest band, smallest turn, clockwise tie"
    for i in 0..<ai.TRACE_NODE_CAPACITY {
        ai.trace_add(&record.trace, max(0, i - 1), .Controller, .Unavailable, longest, "focused_memories / cue_memories", widest, widest, point, 0xffffffff, 0xffffffff)
        record.trace.nodes[i].thread_id = 0x7fffffff
        record.trace.nodes[i].elapsed_us = 9999999999
    }
    record.trace.truncated = 0x7fffffff
    return record
}

@(test)
worst_case_record_fits_the_declared_ceilings :: proc(t: ^testing.T) {
    debug := new(AI_Debug)
    defer free(debug)
    debug.run_id = "ceiling-check-run-identity-with-a-realistic-length/generation-1/attempt-1"
    debug.fingerprint = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    record := extreme_record(false)
    view := ai_debug_view(debug, &record)
    data, error := json.marshal(view, {use_enum_names = true})
    defer delete(data)
    testing.expect(t, error == nil && len(data) <= AI_DEBUG_RECORD_LIMIT, "worst-case record exceeds the per-record ceiling")
    testing.expect(t, AI_DEBUG_HISTORY * AI_DEBUG_RECORD_LIMIT + 64 * 1024 < 4 * 1024 * 1024, "a full snapshot could exceed the reader cap")
    testing.expect(t, 2 * AI_DEBUG_RECORD_LIMIT + 4096 < REPLAY_LINE_LIMIT && REPLAY_LINE_LIMIT < 128 * 1024)
    fmt.printfln("[AI debugger] Worst-case schema-%d record: %d bytes of %d", AI_DEBUG_SCHEMA, len(data), AI_DEBUG_RECORD_LIMIT)
}

@(test)
oversized_diagnostics_are_dropped_and_counted_without_touching_gameplay :: proc(t: ^testing.T) {
    debug := new(AI_Debug)
    defer free(debug)
    directory := fmt.aprintf("build/oversized-record-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug.directory, debug.run_id, debug.fingerprint = directory, "oversized", "00"
    debug.log_limit = AI_DEBUG_LOG_BYTES
    debug.replay.limit = 4 * 1024 * 1024
    debug.replay.line_limit = 40 * 1024 // Tightened so one bloated record overflows a frame.
    bloated := extreme_record(true)
    ai_debug_log(debug, &bloated)
    journal := fmt.aprintf("%s/ai-2.jsonl", directory)
    defer delete(journal)
    testing.expect(t, debug.oversized[1] == 1 && !os.exists(journal) && debug.last_error != "")
    normal := extreme_record(false)
    ai_debug_log(debug, &normal)
    testing.expect(t, debug.oversized[1] == 1 && os.exists(journal))
    // A replay frame keeps its world packet and drops only the oversized traces.
    session: simulation.Session
    session.server_tick, session.round_id = 5, 1
    bloated.input.tick, bloated.input.round_id = 5, 1
    bloated.owner_id = 1
    debug.history[0][0] = bloated
    debug.totals[0] = 1
    capture := Replay_Capture{sequence = 1, tick = 5, round_id = 1, packet = protocol_encode_session(&session), packet_size = 32}
    replay_capture(debug, &capture)
    testing.expect(t, debug.replay.frames == 1 && debug.replay.oversized_frames == 1 && debug.replay.status == "recording")
    replay_close(debug)
    for file in debug.files { if file != nil { os.close(file) } }
}
