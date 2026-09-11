package main

import "simulation"
import "core:sync"
import "core:thread"
import "core:time"

// One producer and one consumer. Semaphore handoff protects copied mailbox data.
// Never move/copy a started worker, and never submit two outstanding requests.
Brain_Worker :: struct {
    thread: ^thread.Thread,
    available, completed: sync.Sema,
    request: simulation.Brain_Request,
    submitted: time.Tick,
    response: simulation.Brain_Response,
    stopping, busy: bool,
}
Brain_Workers :: struct { slots: [simulation.MAX_PLAYERS]Brain_Worker }

brain_workers_init :: proc(workers: ^Brain_Workers) {
    for &worker, i in workers.slots {
        worker.thread = thread.create(brain_worker_run)
        worker.thread.data = &worker
        worker.thread.user_index = i + 1
        thread.start(worker.thread)
    }
}

brain_workers_destroy :: proc(workers: ^Brain_Workers) {
    for &worker in workers.slots {
        if worker.thread == nil { continue }
        if worker.busy { brain_worker_collect(&worker) }
        worker.stopping = true
        sync.sema_post(&worker.available)
    }
    for &worker in workers.slots {
        if worker.thread == nil { continue }
        thread.join(worker.thread)
        thread.destroy(worker.thread)
        worker.thread = nil
    }
}

// Both threads receive their input before either is joined, so one slow brain
// never delays the other brain's start.
brain_workers_decide :: proc(workers: ^Brain_Workers, requests: [simulation.MAX_PLAYERS]simulation.Brain_Request) -> (responses: [simulation.MAX_PLAYERS]simulation.Brain_Response) {
    for request, index in requests { brain_worker_submit(&workers.slots[index], request) }
    for &worker, index in workers.slots { responses[index] = brain_worker_collect(&worker) }
    return
}

brain_worker_submit :: proc(worker: ^Brain_Worker, request: simulation.Brain_Request) {
    assert(!worker.busy && !worker.stopping && worker.thread != nil)
    worker.request = request
    worker.submitted = time.tick_now()
    worker.busy = true
    sync.sema_post(&worker.available)
}

brain_worker_collect :: proc(worker: ^Brain_Worker) -> simulation.Brain_Response {
    assert(worker.busy)
    sync.sema_wait(&worker.completed)
    worker.busy = false
    return worker.response
}

brain_worker_run :: proc(t: ^thread.Thread) {
    worker := cast(^Brain_Worker)t.data
    for {
        sync.sema_wait(&worker.available)
        if worker.stopping { return }
        // The mailbox holds values: the brain's own copies, never a pointer to the
        // session, the terrain, the candidates or another brain.
        response := simulation.brain_decide(worker.request)
        response.queue_us = i64(time.tick_diff(worker.submitted, response.started) / time.Microsecond)
        worker.response = response
        sync.sema_post(&worker.completed)
    }
}
