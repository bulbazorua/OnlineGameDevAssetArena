package diagnostics

import "../simulation"
import "core:sync"

// One copied job crossing from the main thread to the writer: a decision record or a
// world capture. Nothing inside points at live simulation memory.
@(private)
Job :: struct {
    is_world: bool,
    record: Record,
    world: World_Capture,
}

// Main thread: number the record for its owner, then hand a copy to the queue.
@(private)
enqueue :: proc(debug: ^Diagnostics, record: Record) {
    if debug == nil { return }
    i := record.owner_id - 1
    assert(i >= 0 && i < simulation.MAX_PLAYERS)
    debug.sequence[i] += 1
    job := Job{record = record}
    job.record.sequence = debug.sequence[i]
    push(debug, job)
}

// Main thread: a full queue drops the job and counts it; the caller never waits.
@(private)
push :: proc(debug: ^Diagnostics, job: Job) {
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
