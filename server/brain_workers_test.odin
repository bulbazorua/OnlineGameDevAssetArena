package main

import ai "ai"
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
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    // No writer: a full diagnostics queue also exercises non-blocking trace loss.
    debug := new(AI_Debug)
    defer free(debug)
    debug.origin = time.tick_now()
    for &arena in content.arenas {
        a := battle_test_scenario(&content, arena.id, 5, 71)
        b := a
        for tick in u32(1)..<700 {
            if tick % 3 == 0 {
                command := Client_Command{kind = .Input, round_id = a.session.round_id, input_sequence = tick, input_mask = 2}
                session_apply(&a.session, &content, 1, command)
                session_apply(&b.session, &content, 1, command)
            }
            simulation_tick(&a, &content)
            simulation_tick(&b, &content, workers, debug)
            testing.expect(t, a.session == b.session && a.battle == b.battle)
        }
        id1, id2 := workers.slots[0].response.worker_id, workers.slots[1].response.worker_id
        testing.expect(t, id1 != id2 && id1 != sync.current_thread_id() && id2 != sync.current_thread_id())
        session_reset(&a.session)
        session_reset(&b.session)
        simulation_tick(&a, &content)
        simulation_tick(&b, &content, workers, debug)
        testing.expect(t, a.battle == Battle_Runtime{} && b.battle == Battle_Runtime{})
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
        brain_worker_submit(&workers.slots[i], {agent = ai.agent_reset(u32(i + 1), 2, 7),
            ctx = {entity_id = u32(i + 1), round_id = 2, tick = 30, can_move = true}, config = ai.wander_defaults(), trace = true})
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
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    directory := fmt.aprintf("build/ai-debug-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug := ai_debug_open(directory, "test-run", content.fingerprint, 4096, seed = 42)
    sim := battle_test_scenario(&content, 1, 5)
    sim.session.summon_elapsed_ticks = 90
    packets: [60][138]u8
    origin := sim.session.trainers[0].position
    for i in 0..<60 {
        session_apply(&sim.session, &content, 1, {kind = .Input, round_id = sim.session.round_id, input_sequence = u32(i + 1), input_mask = 2})
        simulation_tick(&sim, &content, nil, debug)
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
        testing.expect(t, snapshot.owner_id == owner && snapshot.run_id == "test-run" && len(snapshot.fingerprint) == 64)
        testing.expect(t, len(snapshot.records) == 60 && snapshot.dropped_records == 0 && snapshot.writer_error == "")
        for record, i in snapshot.records {
            testing.expect(t, record.sequence == u64(i + 1) && record.owner_id == owner)
            testing.expect(t, record.nodes[0].stage == .Input && record.nodes[len(record.nodes) - 1].stage == .Outcome)
        }
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
    testing.expect(t, end.kind == "end" && end.status == "complete" && end.frames == 60 && end.last_sequence == 60 && end.captured_frames == 60 && end.dropped_messages == 0)
    fmt.printfln("[AI debugger] Journal fixture: %s", directory)
}

@(test)
replay_limit_preserves_start_and_reports_uncaptured_tail :: proc(t: ^testing.T) {
    debug := new(AI_Debug)
    defer free(debug)
    directory := fmt.aprintf("build/replay-limit-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug.directory = directory
    debug.run_id = "limit-test"
    debug.replay.limit = 4096
    session: Session
    for sequence in u64(1)..=40 {
        session.server_tick += 1
        capture := Replay_Capture{sequence = sequence, tick = session.server_tick, packet = protocol_encode_session(&session), packet_size = 32}
        replay_capture(debug, &capture)
    }
    testing.expect(t, debug.replay.status == "size_limit" && debug.replay.frames > 0 && debug.replay.frames < 40)
    frames := debug.replay.frames
    debug.world_sequence = 40
    debug.dropped = 3
    replay_close(debug)
    testing.expect(t, debug.replay.bytes <= 4096 && debug.replay.status == "size_limit" && debug.replay.file == nil)
    path := fmt.aprintf("%s/match.replay.jsonl", directory)
    defer delete(path)
    data, error := os.read_entire_file(path, context.allocator)
    defer delete(data)
    testing.expect(t, error == nil)
    lines := strings.split(string(data), "\n")
    defer delete(lines)
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary)
    defer mem.dynamic_arena_destroy(&temporary)
    end: Replay_End
    testing.expect(t, json.unmarshal(transmute([]u8)lines[len(lines) - 2], &end, allocator = mem.dynamic_arena_allocator(&temporary)) == nil)
    testing.expect(t, end.status == "size_limit" && end.frames == frames && end.last_sequence == frames && end.captured_frames == 40 && end.dropped_messages == 3)
}

@(test)
debugger_requires_explicit_local_development_binding :: proc(t: ^testing.T) {
    testing.expect(t, ai_debug_options_valid({}))
    testing.expect(t, !ai_debug_options_valid({dev_ai_dir = "/tmp/ai-test", dev_ai_run = "test"}))
    testing.expect(t, !ai_debug_options_valid({dev = true, bind = "0.0.0.0", dev_ai_dir = "/tmp/ai-test", dev_ai_run = "test"}))
    testing.expect(t, !ai_debug_options_valid({dev = true, bind = "127.0.0.1", dev_ai_dir = "relative", dev_ai_run = "test"}))
    testing.expect(t, ai_debug_options_valid({dev = true, bind = "127.0.0.1", dev_ai_dir = "/tmp/ai-test", dev_ai_run = "test"}) == ODIN_DEBUG)
}
