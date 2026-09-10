package main

import ai "ai"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

AI_DEBUG_QUEUE :: 256
AI_DEBUG_HISTORY :: 128
AI_DEBUG_LOG_BYTES :: 8 * 1024 * 1024
AI_DEBUG_OLD_LOGS :: 3

AI_Debug_Job :: struct {
    is_world: bool,
    record: AI_Debug_Record,
    world: Replay_Capture,
}

AI_Debug_Record :: struct {
    sequence: u64,
    owner_id: int,
    definition_id, map_id: u16,
    facing: u8,
    input: ai.Decision_Context,
    config: ai.Wander_Config,
    before, after: ai.Agent,
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    worker_id: int,
    queued_us, started_us, finished_us: i64,
    trace: ai.Trace_Buffer,
}
// Portable view: slices refer only to writer-owned storage during serialization.
AI_Debug_Record_View :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    sequence: u64,
    owner_id: int,
    definition_id, map_id: u16,
    facing: u8,
    input: ai.Decision_Context,
    config: ai.Wander_Config,
    before, after: ai.Agent,
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    worker_id: int,
    queued_us, started_us, finished_us: i64,
    nodes: []ai.Trace_Node,
    truncated_nodes: int,
}
AI_Debug_Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    owner_id: int,
    published_us: i64,
    dropped_records, overwritten_records: u64,
    writer_error: string,
    publish_us: i64,
    log_limit_bytes, retained_segments: int,
    records: []AI_Debug_Record_View,
    replay_status: string,
    replay_frames: u64,
    replay_bytes: int,
}
// Heap-owned and never moved after starting. Queue fields alone need the mutex.
AI_Debug :: struct {
    writer: ^thread.Thread,
    mutex: sync.Mutex,
    ready: sync.Cond,
    queue: [AI_DEBUG_QUEUE]AI_Debug_Job,
    head, count: int,
    stopping: bool,
    dropped: u64,
    sequence: [MAX_PLAYERS]u64, // Host-only counters, including dropped records.
    directory, run_id, fingerprint: string,
    origin: time.Tick,
    history: [MAX_PLAYERS][AI_DEBUG_HISTORY]AI_Debug_Record,
    totals: [MAX_PLAYERS]u64,
    files: [MAX_PLAYERS]^os.File,
    bytes: [MAX_PLAYERS]int,
    log_limit: int,
    last_error: string,
    publish_us: i64,
    world_sequence: u64, // Host-only; read by the writer only after shutdown handoff.
    seed: u32,
    replay: Replay_Writer,
}

ai_debug_options_valid :: proc(options: Options) -> bool {
    if options.dev_ai_dir == "" && options.dev_ai_run == "" { return true }
    when !ODIN_DEBUG {
        fmt.eprintln("[AI debugger] Telemetry requires a debug host build.")
        return false
    }
    if !options.dev || options.bind != "127.0.0.1" || !os.is_absolute_path(options.dev_ai_dir) || options.dev_ai_run == "" {
        fmt.eprintln("[AI debugger] Require --dev, loopback, absolute --dev-ai-dir and --dev-ai-run.")
        return false
    }
    return true
}

ai_debug_open :: proc(directory, run_id: string, fingerprint: [32]u8, log_limit: int = AI_DEBUG_LOG_BYTES, seed: u32 = 0) -> ^AI_Debug {
    if directory == "" { return nil }
    when !ODIN_DEBUG { return nil }
    debug := new(AI_Debug)
    debug.directory, debug.run_id = directory, run_id
    // Encode bytes explicitly, matching the client's compatibility fingerprint.
    digest := fingerprint
    debug.fingerprint = ai_debug_hex(digest[:])
    debug.origin = time.tick_now()
    debug.log_limit = max(1024, log_limit)
    debug.seed = seed
    debug.replay.limit = REPLAY_LIMIT_BYTES
    debug.writer = thread.create(ai_debug_writer)
    debug.writer.data = debug
    thread.start(debug.writer)
    return debug
}

ai_debug_close :: proc(debug: ^AI_Debug) {
    if debug == nil { return }
    sync.mutex_lock(&debug.mutex)
    debug.stopping = true
    sync.mutex_unlock(&debug.mutex)
    sync.cond_signal(&debug.ready)
    thread.join(debug.writer)
    thread.destroy(debug.writer)
    delete(debug.fingerprint)
    free(debug)
}

ai_debug_enqueue :: proc(debug: ^AI_Debug, record: AI_Debug_Record) {
    if debug == nil { return }
    i := record.owner_id - 1
    assert(i >= 0 && i < MAX_PLAYERS)
    debug.sequence[i] += 1
    job := AI_Debug_Job{record = record}
    job.record.sequence = debug.sequence[i]
    ai_debug_push(debug, job)
}

ai_debug_push :: proc(debug: ^AI_Debug, job: AI_Debug_Job) {
    sync.mutex_lock(&debug.mutex)
    if debug.count == len(debug.queue) {
        debug.dropped += 1
    } else {
        index := (debug.head + debug.count) % len(debug.queue)
        debug.queue[index] = job
        debug.count += 1
    }
    sync.mutex_unlock(&debug.mutex)
    sync.cond_signal(&debug.ready)
}

ai_debug_view :: proc(debug: ^AI_Debug, record: ^AI_Debug_Record) -> AI_Debug_Record_View {
    r := record
    return {1, debug.run_id, debug.fingerprint, r.sequence, r.owner_id, r.definition_id, r.map_id,
        r.facing, r.input, r.config, r.before, r.after, r.decision_reason, r.result, r.position_after, r.worker_id,
        r.queued_us, r.started_us, r.finished_us, r.trace.nodes[:r.trace.count], r.trace.truncated}
}

ai_debug_error :: proc(debug: ^AI_Debug, message: string) {
    if debug.last_error != message { fmt.eprintfln("[AI debugger] %s (%s)", message, debug.directory) }
    debug.last_error = message
}

ai_debug_log :: proc(debug: ^AI_Debug, record: ^AI_Debug_Record) {
    i := record.owner_id - 1
    view := ai_debug_view(debug, record)
    data, error := json.marshal(view, {use_enum_names = true})
    if error != nil { ai_debug_error(debug, "Cannot serialize trace"); return }
    defer delete(data)
    path := fmt.aprintf("%s/ai-%d.jsonl", debug.directory, i + 1)
    defer delete(path)
    if debug.bytes[i] > 0 && debug.bytes[i] + len(data) + 1 > debug.log_limit {
        if debug.files[i] != nil { os.close(debug.files[i]); debug.files[i] = nil }
        for n := AI_DEBUG_OLD_LOGS; n >= 1; n -= 1 {
            destination := fmt.aprintf("%s.%d", path, n)
            source := path if n == 1 else fmt.aprintf("%s.%d", path, n - 1)
            if os.exists(destination) { os.remove(destination) }
            if os.exists(source) && os.rename(source, destination) != nil { ai_debug_error(debug, "Cannot rotate trace log") }
            delete(destination)
            if n > 1 { delete(source) }
        }
        debug.bytes[i] = 0
    }
    if debug.files[i] == nil {
        file, open_error := os.open(path, {.Write, .Create, .Append})
        if open_error != nil { ai_debug_error(debug, "Cannot open trace journal"); return }
        debug.files[i] = file
    }
    written, write_error := os.write(debug.files[i], data)
    newline, newline_error := os.write(debug.files[i], []u8{'\n'})
    if write_error != nil || newline_error != nil || written != len(data) || newline != 1 {
        ai_debug_error(debug, "Incomplete trace journal write")
    }
    debug.bytes[i] += int(written + newline)
}

ai_debug_publish :: proc(debug: ^AI_Debug, dropped: u64) {
    start := time.tick_now()
    for i in 0..<MAX_PLAYERS {
        views: [AI_DEBUG_HISTORY]AI_Debug_Record_View
        total := debug.totals[i]
        count := int(min(total, u64(AI_DEBUG_HISTORY)))
        for j in 0..<count {
            index := int((total - u64(count) + u64(j)) % AI_DEBUG_HISTORY)
            views[j] = ai_debug_view(debug, &debug.history[i][index])
        }
        snapshot := AI_Debug_Snapshot{1, debug.run_id, debug.fingerprint, i + 1,
            i64(time.tick_since(debug.origin) / time.Microsecond), dropped, total - u64(count),
            debug.last_error, debug.publish_us, debug.log_limit, AI_DEBUG_OLD_LOGS + 1, views[:count],
            debug.replay.status, debug.replay.frames, debug.replay.bytes}
        data, error := json.marshal(snapshot, {use_enum_names = true})
        if error != nil { ai_debug_error(debug, "Cannot serialize debugger snapshot"); continue }
        path := fmt.aprintf("%s/ai-%d.json", debug.directory, i + 1)
        temporary := fmt.aprintf("%s.tmp", path)
        if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil {
            ai_debug_error(debug, "Cannot publish debugger snapshot")
        }
        delete(temporary)
        delete(path)
        delete(data)
    }
    debug.publish_us = i64(time.tick_since(start) / time.Microsecond)
}

ai_debug_writer :: proc(t: ^thread.Thread) {
    debug := cast(^AI_Debug)t.data
    previous := time.tick_now()
    for {
        job: AI_Debug_Job
        have_record := false
        sync.mutex_lock(&debug.mutex)
        if debug.count == 0 && !debug.stopping { sync.cond_wait_with_timeout(&debug.ready, &debug.mutex, 100 * time.Millisecond) }
        if debug.count > 0 {
            job = debug.queue[debug.head]
            debug.head = (debug.head + 1) % len(debug.queue)
            debug.count -= 1
            have_record = true
        }
        stop := debug.stopping && debug.count == 0 && !have_record
        dropped := debug.dropped
        sync.mutex_unlock(&debug.mutex)
        if have_record {
            if job.is_world {
                replay_capture(debug, &job.world)
            } else {
                record := &job.record
                i := record.owner_id - 1
                debug.history[i][debug.totals[i] % AI_DEBUG_HISTORY] = record^
                debug.totals[i] += 1
                ai_debug_log(debug, record)
            }
        }
        if stop { replay_close(debug) }
        if stop || time.tick_since(previous) >= 250 * time.Millisecond {
            ai_debug_publish(debug, dropped)
            previous = time.tick_now()
        }
        if stop { break }
    }
    for file in debug.files { if file != nil { os.close(file) } }
}
