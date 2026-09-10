// Optional diagnostics. No trace field influences a decision or random draw.
package ai

import "core:sync"
import "core:time"

TRACE_NODE_CAPACITY :: 48
Trace_Stage :: enum { Input, State, Controller, Branch, Decision, Outcome }
Trace_Status :: enum { Info, Passed, Rejected, Skipped, Selected, Resolved, Unavailable }
Trace_Node :: struct {
    id, parent: int,
    stage: Trace_Stage,
    status: Trace_Status,
    label, metric: string,
    value, threshold: f64,
    direction: Vector,
    thread_id: int,
    elapsed_us: i64,
}
Trace_Buffer :: struct {
    nodes: [TRACE_NODE_CAPACITY]Trace_Node,
    count, truncated: int,
    started: time.Tick,
}

trace_begin :: proc(trace: ^Trace_Buffer) {
    if trace == nil { return }
    trace^ = Trace_Buffer{started = time.tick_now()}
}

trace_add :: proc(trace: ^Trace_Buffer, parent: int, stage: Trace_Stage, status: Trace_Status,
                  label: string, metric: string = "", value: f64 = 0, threshold: f64 = 0, direction: Vector = {}) -> int {
    if trace == nil { return 0 }
    if trace.count == len(trace.nodes) { trace.truncated += 1; return 0 }
    id := trace.count + 1
    assert(parent >= 0 && parent < id)
    trace.nodes[trace.count] = {id, parent, stage, status, label, metric, value, threshold, direction,
        sync.current_thread_id(), i64(time.tick_since(trace.started) / time.Microsecond)}
    trace.count += 1
    return id
}

trace_condition :: proc(trace: ^Trace_Buffer, parent: int, label: string, passed: bool,
                        metric: string = "", value: f64 = 0, threshold: f64 = 0, direction: Vector = {}) -> int {
    return trace_add(trace, parent, .Branch, .Passed if passed else .Rejected, label, metric, value, threshold, direction)
}
