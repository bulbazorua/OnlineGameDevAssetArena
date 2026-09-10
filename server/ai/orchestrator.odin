package ai

agent_reset :: proc(entity, round, seed: u32) -> Agent {
    return Agent{entity_id = entity, round_id = round, random = random_seed(seed, round, entity)}
}

// Mutates only private decision state. The caller alone resolves/executes the intent.
agent_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Wander_Config) -> Intent {
    assert(agent.entity_id == ctx.entity_id && agent.round_id == ctx.round_id)
    reason: Decision_Reason
    switch agent.controller {
    case .Idle_Wander: reason = wander_decide(agent, ctx, config)
    }
    agent.last = {tick = ctx.tick, reason = reason, requested = agent.intent}
    return agent.intent
}

agent_record_result :: proc(agent: ^Agent, result: Action_Result, tick: u32, config: Wander_Config) {
    agent.last.result = result
    switch agent.controller {
    case .Idle_Wander: wander_record_result(agent, result, tick, config)
    }
}
