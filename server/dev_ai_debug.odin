package main

import "content"
import "simulation"
import ai "ai"
import obs "observations"
import "perception"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

AI_DEBUG_QUEUE :: 256
AI_DEBUG_HISTORY :: 80
AI_DEBUG_LOG_BYTES :: 8 * 1024 * 1024
AI_DEBUG_OLD_LOGS :: 3
// Trace schema 4 added the consumed nose sample, private scent memory, the
// scent-driven search evidence and a separate host olfaction audit; schema 5
// adds the nose's zone coverage and the audit's excluded-cell and detectable-age counts.
AI_DEBUG_SCHEMA :: 5
// Records and recent history are bounded; oversized diagnostics are counted.
AI_DEBUG_RECORD_LIMIT :: 48 * 1024

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
    config: ai.Observe_Config,
    before, after: ai.Agent,
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    facing_after: u8,
    audit: perception.Vision_Audit, // Host-only developer evidence; never a brain input.
    scent_audit: perception.Olfaction_Audit,
    worker_id: int,
    queued_us, started_us, finished_us: i64,
    trace: ai.Trace_Buffer,
    // Writer-filled display geometry, cached per sample. Never touched on the
    // simulation or creature threads.
    fan: [perception.FAN_RAYS]obs.Vector,
    fan_count: int,
}
Vision_Audit_View :: struct {
    sample_id: u32,
    origin_opaque: bool,
    candidates: []perception.Candidate_Audit,
    sight_tests, merged_cues: int,
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
    config: ai.Observe_Config,
    before, after: ai.Agent,
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    facing_after: u8,
    worker_id: int,
    queued_us, started_us, finished_us: i64,
    nodes: []ai.Trace_Node,
    truncated_nodes: int,
    host_audit: Vision_Audit_View,
    host_scent_audit: perception.Olfaction_Audit,
    sight_fan: []obs.Vector,
}
AI_Debug_Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    owner_id: int,
    published_us: i64,
    dropped_records, overwritten_records, oversized_records: u64,
    writer_error: string,
    publish_us: i64,
    log_limit_bytes, retained_segments, record_limit_bytes: int,
    records: []AI_Debug_Record_View,
    replay_status: string,
    replay_frames: u64,
    replay_bytes: int,
}
Debug_Grid :: struct { map_id: u16, grid: perception.Opacity_Grid }
Fan_Cache :: struct {
    valid: bool,
    round_id, observer, sample_id: u32,
    count: int,
    points: [perception.FAN_RAYS]obs.Vector,
}
// When one receptor's sample first reached a brain. Each sense keeps its own
// clock, so a fresh smell never makes an older eye sample look newly delivered.
Sense_Delivery :: struct {
    valid: bool,
    round_id, observer, sample_id: u32,
    delivered_us: i64,
}
Delivery_Clocks :: struct { vision, olfaction: Sense_Delivery }
// Heap-owned and never moved after starting. Queue fields alone need the mutex.
AI_Debug :: struct {
    writer: ^thread.Thread,
    mutex: sync.Mutex,
    ready: sync.Cond,
    queue: [AI_DEBUG_QUEUE]AI_Debug_Job,
    head, count: int,
    stopping: bool,
    dropped: u64,
    sequence: [simulation.MAX_PLAYERS]u64, // Host-only counters, including dropped records.
    directory, run_id, fingerprint: string,
    origin: time.Tick,
    origin_unix_us: i64,
    sense_world: Sense_Debug_World,
    history: [simulation.MAX_PLAYERS][AI_DEBUG_HISTORY]AI_Debug_Record,
    totals: [simulation.MAX_PLAYERS]u64,
    oversized: [simulation.MAX_PLAYERS]u64,
    files: [simulation.MAX_PLAYERS]^os.File,
    bytes: [simulation.MAX_PLAYERS]int,
    log_limit: int,
    last_error: string,
    publish_us: i64,
    world_sequence: u64, // Host-only; read by the writer only after shutdown handoff.
    seed: u32,
    replay: Replay_Writer,
    grids: []Debug_Grid, // Writer-owned immutable opacity copies, prepared at open.
    fans: [simulation.MAX_PLAYERS]Fan_Cache,
    delivery: [simulation.MAX_PLAYERS]Delivery_Clocks,
    scent_mutex: sync.Mutex, // Guards only the field capture handed to the writer.
    scent_capture: Scent_Debug_Capture,
    scent_captured_steps: u32,
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

ai_debug_open :: proc(directory, run_id: string, fingerprint: [32]u8, catalog: ^content.Game_Content = nil, log_limit: int = AI_DEBUG_LOG_BYTES, seed: u32 = 0) -> ^AI_Debug {
    if directory == "" { return nil }
    when !ODIN_DEBUG { return nil }
    debug := new(AI_Debug)
    debug.directory, debug.run_id = directory, run_id
    // Encode bytes explicitly, matching the client's compatibility fingerprint.
    digest := fingerprint
    debug.fingerprint = ai_debug_hex(digest[:])
    debug.origin = time.tick_now()
    debug.origin_unix_us = time.to_unix_nanoseconds(time.now()) / 1000
    debug.log_limit = max(1024, log_limit)
    debug.seed = seed
    debug.replay.limit = REPLAY_LIMIT_BYTES
    debug.replay.line_limit = REPLAY_LINE_LIMIT
    if catalog != nil {
        // Copy opacity outside the simulation tick; the writer alone reads it.
        debug.grids = make([]Debug_Grid, len(catalog.arenas))
        for &arena, index in catalog.arenas {
            source := content.arena_opacity_grid(&arena)
            grid := perception.Opacity_Grid{width = source.width, height = source.height, tile_size = source.tile_size, opaque = make([]bool, len(source.opaque))}
            copy(grid.opaque, source.opaque)
            debug.grids[index] = {arena.id, grid}
        }
    }
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
    for entry in debug.grids { delete(entry.grid.opaque) }
    delete(debug.grids)
    delete(debug.fingerprint)
    free(debug)
}

ai_debug_enqueue :: proc(debug: ^AI_Debug, record: AI_Debug_Record) {
    if debug == nil { return }
    i := record.owner_id - 1
    assert(i >= 0 && i < simulation.MAX_PLAYERS)
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

// Writer-side display fan for the consumed sample, cached by round/observer/sample
// so retained samples do not repeat the ray queries on every decision.
ai_debug_attach_fan :: proc(debug: ^AI_Debug, record: ^AI_Debug_Record) {
    record.fan_count = 0
    sample := record.input.senses.vision
    if sample.status != .Sampled { return }
    cache := &debug.fans[record.owner_id - 1]
    if cache.valid && cache.round_id == sample.round_id && cache.observer == sample.observer && cache.sample_id == sample.sample_id {
        record.fan, record.fan_count = cache.points, cache.count
        return
    }
    for entry in debug.grids {
        if entry.map_id != record.map_id { continue }
        record.fan_count = perception.vision_fan(entry.grid, sample.pose, sample.profile, &record.fan)
        break
    }
    cache^ = {valid = true, round_id = sample.round_id, observer = sample.observer, sample_id = sample.sample_id,
        count = record.fan_count, points = record.fan}
}

// Remember the first delivery of a new sample. A repeated decision with the same
// sample keeps the original time; a sample whose first record was lost is unknown.
@(private = "file")
delivery_note :: proc(clock: ^Sense_Delivery, round_id, observer, sample_id: u32, is_new: bool, queued_us: i64) {
    if clock.valid && clock.round_id == round_id && clock.observer == observer && clock.sample_id == sample_id { return }
    clock^ = {valid = true, round_id = round_id, observer = observer, sample_id = sample_id, delivered_us = queued_us if is_new else -1}
}

ai_debug_note_delivery :: proc(debug: ^AI_Debug, record: ^AI_Debug_Record) {
    clocks := &debug.delivery[record.owner_id - 1]
    eye := record.input.senses.vision
    if eye.status == .Sampled { delivery_note(&clocks.vision, eye.round_id, eye.observer, eye.sample_id, record.input.senses.vision_is_new, record.queued_us) }
    nose := record.input.senses.olfaction
    if nose.status == .Sampled { delivery_note(&clocks.olfaction, nose.round_id, nose.observer, nose.sample_id, record.input.senses.olfaction_is_new, record.queued_us) }
}

ai_debug_view :: proc(debug: ^AI_Debug, record: ^AI_Debug_Record) -> AI_Debug_Record_View {
    r := record
    audit := Vision_Audit_View{r.audit.sample_id, r.audit.origin_opaque, r.audit.candidates[:r.audit.candidate_count], r.audit.sight_tests, r.audit.merged_cues}
    return {AI_DEBUG_SCHEMA, debug.run_id, debug.fingerprint, r.sequence, r.owner_id, r.definition_id, r.map_id,
        r.facing, r.input, r.config, r.before, r.after, r.decision_reason, r.result, r.position_after, r.facing_after, r.worker_id,
        r.queued_us, r.started_us, r.finished_us, r.trace.nodes[:r.trace.count], r.trace.truncated, audit, r.scent_audit, r.fan[:r.fan_count]}
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
    if len(data) > AI_DEBUG_RECORD_LIMIT {
        debug.oversized[i] += 1
        ai_debug_error(debug, "Dropped an oversized trace record")
        return
    }
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

// One creature's recent-history snapshot: the expensive part of the writer's work.
ai_debug_publish_owner :: proc(debug: ^AI_Debug, owner: int, dropped: u64) {
    views: [AI_DEBUG_HISTORY]AI_Debug_Record_View
    total := debug.totals[owner]
    count := int(min(total, u64(AI_DEBUG_HISTORY)))
    for j in 0..<count {
        index := int((total - u64(count) + u64(j)) % AI_DEBUG_HISTORY)
        views[j] = ai_debug_view(debug, &debug.history[owner][index])
    }
    snapshot := AI_Debug_Snapshot{AI_DEBUG_SCHEMA, debug.run_id, debug.fingerprint, owner + 1,
        i64(time.tick_since(debug.origin) / time.Microsecond), dropped, total - u64(count), debug.oversized[owner],
        debug.last_error, debug.publish_us, debug.log_limit, AI_DEBUG_OLD_LOGS + 1, AI_DEBUG_RECORD_LIMIT, views[:count],
        debug.replay.status, debug.replay.frames, debug.replay.bytes}
    data, error := json.marshal(snapshot, {use_enum_names = true})
    if error != nil { ai_debug_error(debug, "Cannot serialize debugger snapshot"); return }
    defer delete(data)
    path := fmt.aprintf("%s/ai-%d.json", debug.directory, owner + 1)
    defer delete(path)
    temporary := fmt.aprintf("%s.tmp", path)
    defer delete(temporary)
    if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil {
        ai_debug_error(debug, "Cannot publish debugger snapshot")
    }
}

ai_debug_publish :: proc(debug: ^AI_Debug, dropped: u64) {
    start := time.tick_now()
    for owner in 0..<simulation.MAX_PLAYERS { ai_debug_publish_owner(debug, owner, dropped) }
    debug.publish_us = i64(time.tick_since(start) / time.Microsecond)
}

// Handle one queued job: a world capture feeds replay and the lifecycle record;
// a decision record gets its display fan and delivery clock, then history and journal.
@(private = "file")
ai_debug_consume :: proc(debug: ^AI_Debug, job: ^AI_Debug_Job) {
    if job.is_world {
        debug.sense_world = job.world.senses
        replay_capture(debug, &job.world)
        return
    }
    record := &job.record
    i := record.owner_id - 1
    ai_debug_attach_fan(debug, record)
    ai_debug_note_delivery(debug, record)
    debug.history[i][debug.totals[i] % AI_DEBUG_HISTORY] = record^
    debug.totals[i] += 1
    ai_debug_log(debug, record)
}

Writer_Drain :: struct {
    fresh_sample, stop: bool,
    dropped: u64,
}

// Process everything queued right now. With `wait` the first job may be awaited
// briefly; the pass ends when the queue is empty.
@(private = "file")
ai_debug_drain :: proc(debug: ^AI_Debug, wait: bool) -> (drain: Writer_Drain) {
    first := wait
    for {
        job: AI_Debug_Job
        have_record := false
        sync.mutex_lock(&debug.mutex)
        if first && debug.count == 0 && !debug.stopping { sync.cond_wait_with_timeout(&debug.ready, &debug.mutex, 100 * time.Millisecond) }
        if debug.count > 0 {
            job = debug.queue[debug.head]
            debug.head = (debug.head + 1) % len(debug.queue)
            debug.count -= 1
            have_record = true
        }
        drain.stop = debug.stopping && debug.count == 0 && !have_record
        drain.dropped = debug.dropped
        sync.mutex_unlock(&debug.mutex)
        if !have_record { return }
        ai_debug_consume(debug, &job)
        if !job.is_world && (job.record.input.senses.vision_is_new || job.record.input.senses.olfaction_is_new) { drain.fresh_sample = true }
        first = false
    }
}

@(private = "file")
ai_debug_publish_live :: proc(debug: ^AI_Debug) {
    ai_debug_publish_senses(debug)
    ai_debug_publish_search(debug)
}

ai_debug_writer :: proc(t: ^thread.Thread) {
    debug := cast(^AI_Debug)t.data
    previous := time.tick_now()
    previous_senses := previous
    previous_scent := previous
    for {
        drain := ai_debug_drain(debug, true)
        if drain.stop { replay_close(debug) }
        if drain.stop || drain.fresh_sample || time.tick_since(previous_senses) >= 50 * time.Millisecond {
            ai_debug_publish_live(debug)
            previous_senses = time.tick_now()
        }
        if drain.stop || time.tick_since(previous_scent) >= 100 * time.Millisecond {
            ai_debug_publish_scent(debug)
            previous_scent = time.tick_now()
        }
        if drain.stop || time.tick_since(previous) >= 250 * time.Millisecond {
            // A fresh sample must never wait behind both history snapshots: catch up between them.
            start := time.tick_now()
            for owner in 0..<simulation.MAX_PLAYERS {
                ai_debug_publish_owner(debug, owner, drain.dropped)
                if owner + 1 == simulation.MAX_PLAYERS { break }
                between := ai_debug_drain(debug, false)
                drain.dropped = between.dropped
                if between.fresh_sample {
                    ai_debug_publish_live(debug)
                    previous_senses = time.tick_now()
                }
            }
            debug.publish_us = i64(time.tick_since(start) / time.Microsecond)
            previous = time.tick_now()
        }
        if drain.stop { break }
    }
    for file in debug.files { if file != nil { os.close(file) } }
}

// Turn this tick's requests, answers and confirmed results into one diagnostic record
// per creature. The confirmed outcome is appended to each trace first.
ai_debug_record_decisions :: proc(debug: ^AI_Debug, sim: ^simulation.Simulation, requests: [simulation.MAX_PLAYERS]simulation.Brain_Request,
                                  responses: ^[simulation.MAX_PLAYERS]simulation.Brain_Response, outcomes: [simulation.MAX_PLAYERS]simulation.Decision_Outcome) {
    if debug == nil { return }
    for outcome, index in outcomes {
        request := requests[index]
        response := &responses[index]
        ai.trace_add(&response.trace, 1, .Outcome, .Resolved, "Host resolved intent; inspect confirmed action result",
            "confirmed_facing", f64(outcome.result.facing), 0, outcome.result.displacement)
        start_us := i64(time.tick_diff(debug.origin, response.started) / time.Microsecond)
        ai_debug_enqueue(debug, AI_Debug_Record{owner_id = index + 1, definition_id = sim.session.characters[index].definition_id,
            map_id = sim.session.map_id, facing = u8(request.ctx.facing), input = request.ctx, config = request.config,
            before = request.agent, after = sim.battle.agents[index], decision_reason = outcome.decision_reason, result = outcome.result,
            position_after = outcome.position_after, facing_after = outcome.facing_after,
            audit = sim.battle.receptors[index].vision.audit, scent_audit = sim.battle.receptors[index].olfaction.audit,
            worker_id = response.worker_id, queued_us = start_us - response.queue_us, started_us = start_us,
            finished_us = start_us + response.compute_us, trace = response.trace})
    }
}
