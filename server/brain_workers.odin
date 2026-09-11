package main

import ai "ai"
import "core:sync"
import "core:thread"
import "core:time"

Brain_Request :: struct {
    agent: ai.Agent,
    ctx: ai.Decision_Context,
    config: ai.Observe_Config,
    trace: bool,
    submitted: time.Tick,
}
Brain_Response :: struct {
    agent: ai.Agent,
    intent: ai.Intent,
    trace: ai.Trace_Buffer,
    worker_id: int,
    queue_us, compute_us: i64,
    started: time.Tick,
}
// One producer and one consumer. Semaphore handoff protects copied mailbox data.
// Never move/copy a started worker, and never submit two outstanding requests.
Brain_Worker :: struct {
    thread: ^thread.Thread,
    available, completed: sync.Sema,
    request: Brain_Request,
    response: Brain_Response,
    stopping, busy: bool,
}
Brain_Workers :: struct { slots: [MAX_PLAYERS]Brain_Worker }

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

brain_worker_submit :: proc(worker: ^Brain_Worker, request: Brain_Request) {
    assert(!worker.busy && !worker.stopping && worker.thread != nil)
    worker.request = request
    worker.request.submitted = time.tick_now()
    worker.busy = true
    sync.sema_post(&worker.available)
}

brain_worker_collect :: proc(worker: ^Brain_Worker) -> Brain_Response {
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
        input := worker.request
        start := time.tick_now()
        output := Brain_Response{agent = input.agent, worker_id = sync.current_thread_id(), started = start,
            queue_us = i64(time.tick_diff(input.submitted, start) / time.Microsecond)}
        trace: ^ai.Trace_Buffer
        if input.trace { trace = &output.trace }
        // The worker's agent/context are values: its own sample, self condition and
        // private memory. No pointer to Session, terrain, candidates or another brain.
        output.intent = ai.agent_decide(&output.agent, input.ctx, input.config, trace)
        output.compute_us = i64(time.tick_since(start) / time.Microsecond)
        worker.response = output
        sync.sema_post(&worker.completed)
    }
}
