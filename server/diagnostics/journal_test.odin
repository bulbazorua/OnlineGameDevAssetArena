package diagnostics

import ai "../ai"
import obs "../observations"
import "../perception"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:testing"

// Builds a record with every array full and every field at a realistic maximum:
// world-sized coordinates, 32-bit ticks, the longest enum names and labels.
@(private = "file")
extreme_record :: proc(absurd_floats: bool) -> Record {
    wide := f32(-1234.5677)
    widest := f64(4294967295)
    if absurd_floats { wide, widest = f32(-1.1754944e-38), f64(-1.7976931348623157e+308) }
    point := obs.Vector{wide, wide}
    record: Record
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
    debug := new(Diagnostics)
    defer free(debug)
    debug.run_id = "ceiling-check-run-identity-with-a-realistic-length/generation-1/attempt-1"
    debug.fingerprint = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    record := extreme_record(false)
    view := record_view(debug, &record)
    data, error := json.marshal(view, {use_enum_names = true})
    defer delete(data)
    testing.expect(t, error == nil && len(data) <= RECORD_LIMIT, "worst-case record exceeds the per-record ceiling")
    testing.expect(t, HISTORY * RECORD_LIMIT + 64 * 1024 < 4 * 1024 * 1024, "a full snapshot could exceed the reader cap")
    testing.expect(t, 2 * RECORD_LIMIT + 4096 < REPLAY_LINE_LIMIT && REPLAY_LINE_LIMIT < 128 * 1024)
    fmt.printfln("[AI debugger] Worst-case schema-%d record: %d bytes of %d", TRACE_SCHEMA, len(data), RECORD_LIMIT)
}

@(test)
oversized_diagnostics_are_dropped_and_counted_without_touching_gameplay :: proc(t: ^testing.T) {
    debug := new(Diagnostics)
    defer free(debug)
    directory := fmt.aprintf("build/oversized-record-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug.directory, debug.run_id, debug.fingerprint = directory, "oversized", "00"
    debug.log_limit = LOG_BYTES
    debug.replay.limit = 4 * 1024 * 1024
    debug.replay.line_limit = 40 * 1024 // Tightened so one bloated record overflows a frame.
    bloated := extreme_record(true)
    journal_write(debug, &bloated)
    journal := fmt.aprintf("%s/ai-2.jsonl", directory)
    defer delete(journal)
    testing.expect(t, debug.oversized[1] == 1 && !os.exists(journal) && debug.last_error != "")
    normal := extreme_record(false)
    journal_write(debug, &normal)
    testing.expect(t, debug.oversized[1] == 1 && os.exists(journal))
    // A replay frame keeps its world packet and drops only the oversized traces.
    bloated.input.tick, bloated.input.round_id = 5, 1
    bloated.owner_id = 1
    debug.history[0][0] = bloated
    debug.totals[0] = 1
    // A lobby-sized world packet: 32 bytes of any content, as the host would hand over.
    capture := World_Capture{sequence = 1, tick = 5, round_id = 1, packet_size = 32}
    for index in 0..<32 { capture.packet[index] = u8(index) }
    replay_write_frame(debug, &capture)
    testing.expect(t, debug.replay.frames == 1 && debug.replay.oversized_frames == 1 && debug.replay.status == "recording")
    replay_close(debug)
    for file in debug.files { if file != nil { os.close(file) } }
}
