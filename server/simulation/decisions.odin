package simulation

import ai "../ai"
import "core:sync"
import "core:time"

// Everything one brain receives for a decision, copied so the brain can never reach
// the session, the field, the map or the other brain.
Brain_Request :: struct {
    agent: ai.Agent,
    ctx: ai.Decision_Context,
    config: ai.Observe_Config,
    trace: bool,
}

// The brain's answer and how long it took. A threaded caller fills in the queue time.
Brain_Response :: struct {
    agent: ai.Agent,
    intent: ai.Intent,
    trace: ai.Trace_Buffer,
    worker_id: int,
    queue_us, compute_us: i64,
    started: time.Tick,
}

// Decide for one creature on the calling thread. Dedicated workers call this too,
// so threaded and serial simulations run the same code on the same copied inputs.
brain_decide :: proc(request: Brain_Request) -> (response: Brain_Response) {
    response.started = time.tick_now()
    response.agent = request.agent
    response.worker_id = sync.current_thread_id()
    trace: ^ai.Trace_Buffer
    if request.trace { trace = &response.trace }
    response.intent = ai.agent_decide(&response.agent, request.ctx, request.config, trace)
    response.compute_us = i64(time.tick_since(response.started) / time.Microsecond)
    return
}

// Serial reference for deterministic tests and headless simulations.
decide_serially :: proc(requests: [MAX_PLAYERS]Brain_Request) -> (responses: [MAX_PLAYERS]Brain_Response) {
    for request, index in requests { responses[index] = brain_decide(request) }
    return
}
