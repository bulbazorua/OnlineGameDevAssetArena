package ai

agent_reset :: proc(entity, round, seed: u32) -> Agent {
    return Agent{entity_id = entity, round_id = round, random = random_seed(seed, round, entity)}
}

// Mutates only private decision state. The caller alone resolves/executes the intent.
agent_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Wander_Config, trace: ^Trace_Buffer = nil) -> Intent {
    assert(agent.entity_id == ctx.entity_id && agent.round_id == ctx.round_id)
    trace_begin(trace)
    root := trace_add(trace, 0, .Input, .Info, "Received private decision context")
    state := trace_add(trace, root, .State, .Info, "Read own wander state and previous action result")
    trace_add(trace, state, .State, .Unavailable, "Vision, olfaction, hearing and terrain receptors: not implemented")
    trace_add(trace, state, .State, .Unavailable, "Mood and learned memory: not implemented")
    controller := trace_add(trace, root, .Controller, .Selected, "Run idle_wander controller")
    reason: Decision_Reason
    switch agent.controller {
    case .Idle_Wander: reason = wander_decide(agent, ctx, config, trace, controller)
    }
    agent.last = {tick = ctx.tick, reason = reason, requested = agent.intent}
    trace_add(trace, root, .Decision, .Selected, "Submit Move intent" if agent.intent.kind == .Move else "Submit Hold intent", direction = agent.intent.direction)
    return agent.intent
}

agent_record_result :: proc(agent: ^Agent, result: Action_Result, tick: u32, config: Wander_Config) {
    agent.last.result = result
    switch agent.controller {
    case .Idle_Wander: wander_record_result(agent, result, tick, config)
    }
}
