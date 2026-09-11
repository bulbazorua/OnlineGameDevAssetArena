package ai

import obs "../observations"

// A fresh instance: no evidence, no attention, nothing inherited from a previous
// occupant of the same slot or from another instance of the same definition.
agent_reset :: proc(entity, round: u32, controller: Controller = .Observe, seed: u32 = 1) -> Agent {
    return Agent{entity_id = entity, round_id = round, controller = controller,
        search = {profile = search_defaults(), random_state = search_seed(seed, entity, round)}}
}

// Mutates only private decision state. The caller alone resolves/executes the intent.
agent_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Observe_Config, trace: ^Trace_Buffer = nil) -> Intent {
    assert(agent.entity_id == ctx.entity_id && agent.round_id == ctx.round_id)
    trace_begin(trace)
    root := trace_add(trace, 0, .Input, .Info, "Received private decision context", "decision_tick / turn_ready", f64(ctx.tick), 1 if ctx.turn_ready else 0)
    state := trace_add(trace, root, .State, .Info, "Read own memory, attention and previous action result", "focused_memories / cue_memories", f64(agent.memory.focused_count), f64(agent.memory.cue_count))
    trace_add(trace, state, .State, .Info, "Read own scent memory", "scent_memories / own_scent_enabled", f64(agent.scent.count), 1 if ctx.own_emitter.enabled else 0)
    trace_add(trace, state, .State, .Unavailable, "Hearing and terrain receptors: not implemented")
    trace_add(trace, state, .State, .Unavailable, "Mood and learned memory: not implemented")
    controller := trace_add(trace, root, .Controller, .Selected, "Run private creature controller")
    reason: Decision_Reason
    switch agent.controller {
    case .Observe: reason = observe_decide(agent, ctx, config, trace, controller)
    case .Search: reason = search_decide(agent, ctx, config, trace, controller)
    }
    agent.last = {tick = ctx.tick, reason = reason, requested = agent.intent}
    switch agent.intent.kind {
    case .Face: trace_add(trace, root, .Decision, .Selected, "Submit Face intent", "desired_facing", f64(agent.intent.facing), 0, obs.facing_direction(agent.intent.facing))
    case .Move: trace_add(trace, root, .Decision, .Selected, "Submit Move intent", direction = agent.intent.direction)
    case .Hold: trace_add(trace, root, .Decision, .Selected, "Submit Hold intent")
    }
    return agent.intent
}

agent_record_result :: proc(agent: ^Agent, result: Action_Result, tick: u32, config: Observe_Config) {
    agent.last.result = result
    switch agent.controller {
    case .Observe: observe_record_result(agent, result)
    case .Search: search_record_result(agent, result, tick)
    }
}
