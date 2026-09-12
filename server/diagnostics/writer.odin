package diagnostics

import "../simulation"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

// Writer thread: print a new error once, remember it for the snapshot.
@(private)
report_error :: proc(debug: ^Diagnostics, message: string) {
    if debug.last_error != message { fmt.eprintfln("[AI debugger] %s (%s)", message, debug.directory) }
    debug.last_error = message
}

// Handle one queued job: a world capture feeds replay and the lifecycle record;
// a decision record gets its display fan and delivery clock, then history and journal.
@(private = "file")
consume :: proc(debug: ^Diagnostics, job: ^Job) {
    if job.is_world {
        debug.sense_world = job.world.senses
        replay_write_frame(debug, &job.world)
        return
    }
    record := &job.record
    i := record.owner_id - 1
    attach_fan(debug, record)
    note_delivery(debug, record)
    debug.history[i][debug.totals[i] % HISTORY] = record^
    debug.totals[i] += 1
    journal_write(debug, record)
}

@(private = "file")
Drain :: struct {
    fresh_sample, stop: bool,
    dropped: u64,
}

// Process everything queued right now. With `wait` the first job may be awaited
// briefly; the pass ends when the queue is empty.
@(private = "file")
drain_queue :: proc(debug: ^Diagnostics, wait: bool) -> (drain: Drain) {
    first := wait
    for {
        job: Job
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
        consume(debug, &job)
        if !job.is_world && (job.record.input.senses.vision_is_new || job.record.input.senses.olfaction_is_new) { drain.fresh_sample = true }
        first = false
    }
}

@(private = "file")
publish_live :: proc(debug: ^Diagnostics) {
    publish_senses(debug)
    publish_search(debug)
}

// The writer thread's whole life: drain, publish the live feeds on their cadences,
// publish both history snapshots, finish the recording at stop, then close the journals.
@(private)
writer_run :: proc(t: ^thread.Thread) {
    debug := cast(^Diagnostics)t.data
    previous := time.tick_now()
    previous_senses := previous
    previous_scent := previous
    for {
        drain := drain_queue(debug, true)
        if drain.stop { replay_close(debug) }
        if drain.stop || drain.fresh_sample || time.tick_since(previous_senses) >= 50 * time.Millisecond {
            publish_live(debug)
            previous_senses = time.tick_now()
        }
        if drain.stop || time.tick_since(previous_scent) >= 100 * time.Millisecond {
            publish_scent(debug)
            previous_scent = time.tick_now()
        }
        if drain.stop || time.tick_since(previous) >= 250 * time.Millisecond {
            // A fresh sample must never wait behind both history snapshots: catch up between them.
            start := time.tick_now()
            for owner in 0..<simulation.MAX_PLAYERS {
                publish_owner(debug, owner, drain.dropped)
                if owner + 1 == simulation.MAX_PLAYERS { break }
                between := drain_queue(debug, false)
                drain.dropped = between.dropped
                if between.fresh_sample {
                    publish_live(debug)
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
