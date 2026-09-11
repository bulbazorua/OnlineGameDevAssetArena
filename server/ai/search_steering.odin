package ai

import obs "../observations"

search_alignment :: proc(a, b: Vector) -> f32 { return a.x * b.x + a.y * b.y }

search_evidence_direction :: proc(search: ^Search_Runtime, position: Vector) -> Vector {
    if search.state == .Investigate { return obs.facing_direction(search.cue_direction) }
    if search.state == .Pursue || search.state == .Last_Known_Position {
        facing, valid := obs.facing_toward(position, search.target_position)
        if valid { return obs.facing_direction(facing) }
    }
    return {}
}

search_choose_heading :: proc(search: ^Search_Runtime, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) {
    profile := search.profile
    search.scored_tick, search.scored_position = ctx.tick, ctx.position
    search.radius = profile.local_radius + (profile.maximum_local_radius - profile.local_radius) * min(1, f32(ctx.tick - search.evidence_tick) / f32(profile.evidence_ticks))
    evidence := search_evidence_direction(search, ctx.position)
    previous := obs.facing_direction(search.heading)
    search.relocating = false
    if search.state == .Extensive_Search {
        exhausted: f32
        for index in 0..<8 { exhausted += search_recent_penalty(search, ctx.position + obs.facing_direction(Facing(index)) * profile.region_size, ctx.tick) / 8 }
        search.relocating = search_random(search) < 0.12 + exhausted * 0.18
        if search.relocating { previous = obs.facing_direction(Facing(int(search_random(search) * 8))); search.relocation_count += 1 }
    }
    best, score := 0, f32(-1e9)
    for index in 0..<8 {
        direction := obs.facing_direction(Facing(index))
        destination := ctx.position + direction * profile.region_size
        choice := Search_Choice{
            persistence = search_alignment(direction, previous) * profile.persistence,
            exploration = search_random(search) * profile.exploration,
            recent_penalty = search_recent_penalty(search, destination, ctx.tick) * profile.history_weight,
            blocked_penalty = 12 if search.blocked[index] else 0,
        }
        switch search.state {
        case .Pursue, .Last_Known_Position:
            choice.evidence = 5 * search_alignment(direction, evidence)
            choice.recent_penalty *= 0.2
        case .Investigate:
            smelled := search.evidence == .Scent || search.evidence == .Scent_Memory
            choice.evidence = (profile.scent_weight if smelled else profile.cue_weight) * search.confidence * search_alignment(direction, evidence)
        case .Intensive_Search:
            choice.persistence *= 0.3
            before := distance_between(ctx.position, search.center)
            after := distance_between(destination, search.center)
            choice.locality = (before - after) / profile.region_size * 4 if after > search.radius else 0
        case .Extensive_Search:
        }
        choice.total = choice.persistence + choice.exploration + choice.evidence + choice.locality - choice.recent_penalty - choice.blocked_penalty
        search.choices[index] = choice
        if choice.total > score { best, score = index, choice.total }
    }
    search.heading = Facing(best)
    for choice, index in search.choices {
        trace_add(trace, parent, .Branch, .Selected if index == best else .Rejected, "Score a local direction from own evidence and visits", "score / recent-visit penalty",
            f64(choice.total), f64(choice.recent_penalty), obs.facing_direction(Facing(index)))
    }
    duration := profile.extensive_leg_ticks
    if search.state == .Intensive_Search || search.state == .Investigate { duration = profile.intensive_leg_ticks }
    if search.state == .Pursue || search.state == .Last_Known_Position { duration = 6 }
    if search.relocating { duration = profile.relocation_ticks }
    search.leg_active, search.leg_deadline = true, ctx.tick + duration
    trace_add(trace, parent, .State, .Selected, "Commit heading until deadline, fresh evidence or blocked movement", "deadline / relocation", f64(search.leg_deadline), 1 if search.relocating else 0, obs.facing_direction(search.heading))
}
