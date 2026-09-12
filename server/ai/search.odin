package ai

import obs "../observations"

search_reason :: proc(state: Search_State) -> Decision_Reason {
    switch state {
    case .Extensive_Search: return .Search_Extensive
    case .Intensive_Search: return .Search_Intensive
    case .Investigate: return .Investigate
    case .Last_Known_Position: return .Last_Known_Position
    case .Pursue: return .Pursue
    }
    unreachable()
}

search_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Observe_Config, trace: ^Trace_Buffer, parent: int) -> Decision_Reason {
    search := &agent.search
    search.position = ctx.position
    observe_note_sample(ctx.senses.vision, ctx.tick, trace, parent)
    observe_update_memory(agent, ctx, config, trace, parent)
    scent_update_memory(agent, ctx, trace, parent)
    if !ctx.can_act {
        agent.intent = {}
        trace_add(trace, parent, .Branch, .Selected, "Actions locked: hold; do not explore")
        return .Locked
    }
    if !search.started { search.heading = Facing(int(search_random(search) * 8)) }
    search_interpret_scent(agent, ctx, trace, parent)
    search_read_evidence(agent, ctx, config)
    search.started = true
    search_expire_blocks(search, ctx.position, ctx.tick)
    search_remember_visit(search, ctx.position, ctx.tick)
    state := trace_add(trace, parent, .State, .Selected, "Choose search state from private evidence", "state / transition", f64(search.state), f64(search.transition), search.center, search.observation_id, u32(search.target))
    if search.evidence == .Scent || search.evidence == .Scent_Memory {
        trace_add(trace, state, .State, .Info, "Acting on a scent reading: class, strength and coarse bearing only", "class / strength", f64(search.scent.class), f64(search.scent.strength),
            obs.facing_direction(search.scent.bearing) if search.scent.bearing_valid else {}, search.scent.observation_id)
    }
    trace_add(trace, state, .State, .Info, "Current belief keeps its original evidence time", "confidence / evidence age ticks", f64(search.confidence), f64(ctx.tick - search.evidence_tick))
    trace_add(trace, state, .State, .Info, "Visited places are not proof that an area is empty", "remembered visits / retention ticks", f64(search.visit_count), f64(search.profile.history_ticks))
    if search.state == .Pursue && distance_between(ctx.position, search.target_position) <= search.profile.pursuit_distance {
        observe_aim_at_position(agent, ctx, search.target_position, "Opponent nearby: hold at observation distance", "Turn toward the observed opponent", trace, state)
        search.leg_active = false
    } else {
        pursuing := search_pursuing_target(search)
        if pursuing || !search.leg_active || tick_due(ctx.tick, search.leg_deadline) { search_choose_heading(search, ctx, trace, state) }
        agent.intent = {kind = .Move, direction = obs.facing_direction(search.heading)}
        if pursuing {
            agent.intent.direction = search_pursuit_direction(search, ctx.position)
            agent.intent.approach = {active = true, position = search.target_position,
                arrival_distance = search.profile.pursuit_distance if search.state == .Pursue else search.profile.arrival_radius,
                clearance = agent.navigation.profile.clearance}
        }
    }
    agent.attention = {state = .Observe if search.target_visible else .Reacquire, evidence = search.evidence,
        subject = search.target, observation_id = search.observation_id, evidence_tick = search.evidence_tick,
        desired_facing = agent.intent.facing if agent.intent.kind == .Face else search.heading}
    return search_reason(search.state)
}

search_record_result :: proc(agent: ^Agent, result: Action_Result, tick: u32) {
    if agent.intent.kind != .Move { return }
    search := &agent.search
    if result.kind == .Terrain_Blocked || result.kind == .Anchor_Limit {
        search_note_blockage(search, tick)
    }
}

@(private)
search_note_blockage :: proc(search: ^Search_Runtime, tick: u32) {
    search.blocked_origin = search.position
    index := int(search.heading)
    search.blocked[index] = true
    search.blocked_until[index] = tick + search.profile.blocked_ticks
    search.blocked_count += 1
    search.leg_active = false
}
