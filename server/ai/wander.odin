package ai

Wander_Config :: struct {
    idle_min_ticks, idle_max_ticks: u32,
    walk_min_ticks, walk_max_ticks: u32,
    decision_interval: u32,
    speed, roam_radius: f32,
}
Wander_Phase :: enum { Idle, Walk }
Wander_Runtime :: struct {
    started: bool,
    phase: Wander_Phase,
    deadline, next_decision: u32,
}
// Scenario default; character-authored behavior profiles are a later export contract.
wander_defaults :: proc() -> Wander_Config { return {45, 120, 30, 90, 6, 64, 128} }
wander_config_valid :: proc(c: Wander_Config) -> bool {
    return c.idle_min_ticks > 0 && c.idle_min_ticks <= c.idle_max_ticks && c.idle_max_ticks < 0x80000000 &&
        c.walk_min_ticks > 0 && c.walk_min_ticks <= c.walk_max_ticks && c.walk_max_ticks < 0x80000000 &&
        c.decision_interval > 0 && c.decision_interval <= 60 &&
        c.speed > 0 && c.speed <= 180 && c.roam_radius > 0 && c.roam_radius <= 4096
}
// Clockwise from north, matching the explicit public facing convention.
DIRECTIONS :: [8]Vector{{0,-1}, {0.70710678,-0.70710678}, {1,0}, {0.70710678,0.70710678},
    {0,1}, {-0.70710678,0.70710678}, {-1,0}, {-0.70710678,-0.70710678}}

wander_wait :: proc(agent: ^Agent, tick: u32, config: Wander_Config) {
    agent.wander.started = true
    agent.wander.phase = .Idle
    agent.wander.deadline = tick + random_range(&agent.random, config.idle_min_ticks, config.idle_max_ticks)
    agent.intent = {}
}

wander_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Wander_Config, trace: ^Trace_Buffer = nil, parent: int = 0) -> Decision_Reason {
    gate := trace_condition(trace, parent, "Movement unlocked?", ctx.can_move)
    if !ctx.can_move {
        agent.intent = {}
        agent.wander = {}
        trace_add(trace, gate, .Branch, .Selected, "Summon lock: clear wander state and hold")
        trace_add(trace, parent, .Branch, .Skipped, "Wander branches skipped while locked")
        return .Locked
    }
    w := &agent.wander
    trace_condition(trace, parent, "Wander already initialized?", w.started)
    if !w.started {
        wander_wait(agent, ctx.tick, config)
        w.next_decision = ctx.tick + config.decision_interval
        trace_add(trace, parent, .State, .Selected, "Initialize idle deadline using private RNG", "deadline_tick", f64(w.deadline))
    }
    phase := trace_condition(trace, parent, "Currently walking?", w.phase == .Walk)
    if w.phase == .Walk {
        ended := tick_due(ctx.tick, w.deadline)
        branch := trace_condition(trace, phase, "Walk deadline reached?", ended, "tick / deadline", f64(ctx.tick), f64(w.deadline))
        if ended {
            wander_wait(agent, ctx.tick, config)
            trace_add(trace, branch, .Branch, .Selected, "Walk finished: choose a new idle duration")
            return .Walk_Completed
        }
        trace_add(trace, branch, .Branch, .Selected, "Continue previous walk intent")
        return .Walking
    }
    due := tick_due(ctx.tick, w.next_decision)
    schedule := trace_condition(trace, parent, "Scheduled direction decision due?", due, "tick / next_decision", f64(ctx.tick), f64(w.next_decision))
    if !due {
        trace_add(trace, schedule, .Branch, .Selected, "Retain Hold until the next decision tick")
        return .Waiting
    }
    w.next_decision = ctx.tick + config.decision_interval
    idle_done := tick_due(ctx.tick, w.deadline)
    idle := trace_condition(trace, schedule, "Idle deadline reached?", idle_done, "tick / deadline", f64(ctx.tick), f64(w.deadline))
    if !idle_done {
        trace_add(trace, idle, .Branch, .Selected, "Remain idle")
        return .Waiting
    }
    directions := DIRECTIONS
    first := int(random_range(&agent.random, 0, 7))
    candidates := trace_add(trace, idle, .Branch, .Info, "Evaluate directions from a privately sampled starting index", "first_index", f64(first))
    // Only our own position/anchor; no tilemap or opponent lookup.
    for attempt in 0..<8 {
        direction := directions[(first + attempt) % 8]
        next := ctx.position + direction * (config.speed / 60)
        offset := next - ctx.anchor
        distance_sq := offset.x * offset.x + offset.y * offset.y
        permitted := distance_sq <= config.roam_radius * config.roam_radius
        candidate := trace_condition(trace, candidates, "Candidate remains inside roam radius?", permitted,
            "squared_distance / squared_radius", f64(distance_sq), f64(config.roam_radius * config.roam_radius), direction)
        if !permitted { continue }
        agent.intent = {kind = .Move, direction = direction}
        w.phase = .Walk
        w.deadline = ctx.tick + random_range(&agent.random, config.walk_min_ticks, config.walk_max_ticks)
        trace_add(trace, candidate, .Branch, .Selected, "Choose direction and walk duration", "deadline_tick", f64(w.deadline), direction = direction)
        if attempt < 7 { trace_add(trace, candidates, .Branch, .Skipped, "Remaining directions not evaluated after first eligible candidate", "count", f64(7 - attempt)) }
        return .Choosing_Direction
    }
    wander_wait(agent, ctx.tick, config)
    trace_add(trace, candidates, .Branch, .Selected, "No eligible direction: return to idle")
    return .No_Direction
}

// Tactic-specific feedback stays with the tactic, not the common orchestrator.
wander_record_result :: proc(agent: ^Agent, result: Action_Result, tick: u32, config: Wander_Config) {
    switch result.kind {
    case .Terrain_Blocked, .Anchor_Limit, .Invalid_Request:
        // Cancel a failed request once, then back off rather than probing every frame.
        wander_wait(agent, tick, config)
        agent.last.reason = .Action_Blocked
    case .Locked:
        agent.intent = {}
        agent.wander = {}
    case .Held, .Moved, .Preparing:
    }
}
