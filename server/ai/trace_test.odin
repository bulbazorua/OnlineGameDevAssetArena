package ai

import "core:testing"

@(test)
tracing_preserves_private_random_state_and_decisions :: proc(t: ^testing.T) {
    a := agent_reset(11, 3, 42)
    b := a
    config := wander_defaults()
    for tick in u32(0)..<2400 {
        ctx := Decision_Context{entity_id = 11, round_id = 3, tick = tick, can_move = tick >= 90}
        trace: Trace_Buffer
        lhs := agent_decide(&a, ctx, config)
        rhs := agent_decide(&b, ctx, config, &trace)
        testing.expect(t, lhs == rhs && a == b)
        testing.expect(t, trace.count > 0 && trace.truncated == 0)
        for node, index in trace.nodes[:trace.count] {
            testing.expect(t, node.id == index + 1 && node.parent < node.id && node.thread_id > 0)
        }
        result := Action_Result{kind = .Terrain_Blocked if tick % 83 == 0 else .Moved}
        agent_record_result(&a, result, tick, config)
        agent_record_result(&b, result, tick, config)
        testing.expect(t, a == b)
    }
}

@(test)
trace_retains_rejected_candidates_and_reports_capacity_loss :: proc(t: ^testing.T) {
    agent := agent_reset(1, 2, 99)
    agent.wander = {started = true, phase = .Idle}
    trace: Trace_Buffer
    intent := agent_decide(&agent, {entity_id = 1, round_id = 2, can_move = true, position = {500, 500}}, wander_defaults(), &trace)
    testing.expect(t, intent.kind == .Hold && agent.last.reason == .No_Direction)
    rejected := 0
    for node in trace.nodes[:trace.count] {
        if node.metric == "squared_distance / squared_radius" && node.status == .Rejected { rejected += 1 }
    }
    testing.expect(t, rejected == 8)
    for i in 0..<TRACE_NODE_CAPACITY + 7 { trace_add(&trace, 0, .State, .Info, "capacity test") }
    testing.expect(t, trace.count == TRACE_NODE_CAPACITY && trace.truncated > 0)
}
