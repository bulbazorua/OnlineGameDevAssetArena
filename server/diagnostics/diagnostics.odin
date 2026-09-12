package diagnostics

import "../content"
import "../simulation"
import ai "../ai"
import "../perception"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

@(private) QUEUE_CAPACITY :: 256
@(private) HISTORY :: 80
LOG_BYTES :: 8 * 1024 * 1024
@(private) OLD_LOGS :: 3
// Trace schema 4 added the consumed nose sample, private scent memory, the
// scent-driven search evidence and a separate host olfaction audit; schema 5
// adds the nose's zone coverage and the audit's excluded-cell and detectable-age counts.
TRACE_SCHEMA :: 5
// Records and recent history are bounded; oversized diagnostics are counted.
RECORD_LIMIT :: 48 * 1024

// Heap-owned and never moved after open. The mutex guards only the queue fields
// (queue, head, count, stopping, dropped); the scent mutex guards only scent_capture.
// Every other field belongs to one thread, named in docs/codebase/server-diagnostics.md.
Diagnostics :: struct {
    writer: ^thread.Thread,
    mutex: sync.Mutex,
    ready: sync.Cond,
    queue: [QUEUE_CAPACITY]Job,
    head, count: int,
    stopping: bool,
    dropped: u64,
    sequence: [simulation.MAX_PLAYERS]u64, // Host-only counters, including dropped records.
    directory, run_id, fingerprint: string,
    protocol_version: int, // Supplied by the host codec at open; written into the replay header.
    origin: time.Tick,
    origin_unix_us: i64,
    sense_world: Sense_World,
    history: [simulation.MAX_PLAYERS][HISTORY]Record,
    publish_views: [HISTORY]Record_View, // Writer-only reusable snapshot workspace.
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
    grids: []Grid_Copy, // Writer-owned immutable opacity copies, prepared at open.
    fans: [simulation.MAX_PLAYERS]Fan_Cache,
    delivery: [simulation.MAX_PLAYERS]Delivery_Clocks,
    scent_mutex: sync.Mutex, // Guards only the field capture handed to the writer.
    scent_capture: Scent_Capture,
    scent_captured_steps: u32, // Main thread only: the field step already copied.
}

// Launch gate. No diagnostic option means a normal host; any diagnostic option needs a
// debug build, --dev, the loopback bind, an absolute output directory and a run ID.
options_valid :: proc(dev: bool, bind, directory, run_id: string) -> bool {
    if directory == "" && run_id == "" { return true }
    when !ODIN_DEBUG {
        fmt.eprintln("[AI debugger] Telemetry requires a debug host build.")
        return false
    }
    if !dev || bind != "127.0.0.1" || !os.is_absolute_path(directory) || run_id == "" {
        fmt.eprintln("[AI debugger] Require --dev, loopback, absolute --dev-ai-dir and --dev-ai-run.")
        return false
    }
    return true
}

// Release builds and empty directories leave diagnostics off and return nil.
// Keep the directory and run_id strings alive and unchanged until close returns.
open :: proc(directory, run_id: string, fingerprint: [32]u8, protocol_version: int, catalog: ^content.Game_Content = nil,
             log_limit: int = LOG_BYTES, seed: u32 = 0) -> ^Diagnostics {
    if directory == "" { return nil }
    when !ODIN_DEBUG { return nil }
    debug := new(Diagnostics)
    debug.directory, debug.run_id = directory, run_id
    // Encode bytes explicitly, matching the client's compatibility fingerprint.
    digest := fingerprint
    debug.fingerprint = hex(digest[:])
    debug.protocol_version = protocol_version
    debug.origin = time.tick_now()
    debug.origin_unix_us = time.to_unix_nanoseconds(time.now()) / 1000
    debug.log_limit = max(1024, log_limit)
    debug.seed = seed
    debug.replay.limit = REPLAY_LIMIT_BYTES
    debug.replay.line_limit = REPLAY_LINE_LIMIT
    if catalog != nil {
        // Copy opacity outside the simulation tick; the writer alone reads it.
        debug.grids = make([]Grid_Copy, len(catalog.arenas))
        for &arena, index in catalog.arenas {
            source := content.arena_opacity_grid(&arena)
            grid := perception.Opacity_Grid{width = source.width, height = source.height, tile_size = source.tile_size, opaque = make([]bool, len(source.opaque))}
            copy(grid.opaque, source.opaque)
            debug.grids[index] = {arena.id, grid}
        }
    }
    debug.writer = thread.create(writer_run)
    debug.writer.data = debug
    thread.start(debug.writer)
    return debug
}

// Stop all capture calls before closing; close does not block new jobs.
// Let the writer finish its queued work, then release the owned storage.
close :: proc(debug: ^Diagnostics) {
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

// Turn this tick's requests, answers and confirmed results into one diagnostic record
// per creature. The confirmed outcome is appended to each trace first.
record_decisions :: proc(debug: ^Diagnostics, sim: ^simulation.Simulation, requests: [simulation.MAX_PLAYERS]simulation.Brain_Request,
                         responses: ^[simulation.MAX_PLAYERS]simulation.Brain_Response, outcomes: [simulation.MAX_PLAYERS]simulation.Decision_Outcome) {
    if debug == nil { return }
    for outcome, index in outcomes {
        request := requests[index]
        response := &responses[index]
        ai.trace_add(&response.trace, 1, .Outcome, .Resolved, "Host resolved intent; inspect confirmed action result",
            "confirmed_facing", f64(outcome.result.facing), 0, outcome.result.displacement)
        start_us := i64(time.tick_diff(debug.origin, response.started) / time.Microsecond)
        enqueue(debug, Record{owner_id = index + 1, definition_id = sim.session.characters[index].definition_id,
            map_id = sim.session.map_id, facing = u8(request.ctx.facing), input = request.ctx, config = request.config,
            before = request.agent, after = sim.battle.agents[index], decision_reason = outcome.decision_reason, result = outcome.result,
            position_after = outcome.position_after, facing_after = outcome.facing_after,
            audit = sim.battle.receptors[index].vision.audit, scent_audit = sim.battle.receptors[index].olfaction.audit,
            worker_id = response.worker_id, queued_us = start_us - response.queue_us, started_us = start_us,
            finished_us = start_us + response.compute_us, trace = response.trace})
    }
}
