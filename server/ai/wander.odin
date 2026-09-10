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

wander_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Wander_Config) -> Decision_Reason {
    if !ctx.can_move {
        agent.intent = {}
        agent.wander = {}
        return .Locked
    }
    w := &agent.wander
    if !w.started {
        wander_wait(agent, ctx.tick, config)
        w.next_decision = ctx.tick + config.decision_interval
    }
    if w.phase == .Walk {
        if tick_due(ctx.tick, w.deadline) {
            wander_wait(agent, ctx.tick, config)
            return .Walk_Completed
        }
        return .Walking
    }
    if !tick_due(ctx.tick, w.next_decision) { return .Waiting }
    w.next_decision = ctx.tick + config.decision_interval
    if !tick_due(ctx.tick, w.deadline) { return .Waiting }
    directions := DIRECTIONS
    first := int(random_range(&agent.random, 0, 7))
    // Only our own position/anchor; no tilemap or opponent lookup.
    for attempt in 0..<8 {
        direction := directions[(first + attempt) % 8]
        next := ctx.position + direction * (config.speed / 60)
        offset := next - ctx.anchor
        if offset.x * offset.x + offset.y * offset.y > config.roam_radius * config.roam_radius { continue }
        agent.intent = {kind = .Move, direction = direction}
        w.phase = .Walk
        w.deadline = ctx.tick + random_range(&agent.random, config.walk_min_ticks, config.walk_max_ticks)
        return .Choosing_Direction
    }
    wander_wait(agent, ctx.tick, config)
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
