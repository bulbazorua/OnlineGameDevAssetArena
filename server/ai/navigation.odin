package ai

import obs "../observations"
import "core:math"

@(private)
navigation_turn :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, desired: Facing, inspecting: bool = false) -> Intent {
    heading := desired
    nav.speed, nav.intended_distance = 0, 0
    nav.mode = .Inspect if inspecting else .Turn
    if obs.facing_step(ctx.facing, heading) == 4 && nav.passing_side == .Left { heading = obs.facing_rotate(ctx.facing, -1) }
    return {kind = .Face, facing = heading}
}

@(private)
navigation_urgency :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, horizon: f32) -> f32 {
    speed := math.sqrt(search_alignment(nav.velocity, nav.velocity))
    if speed < 0.001 { return 0 }
    path := navigation_passage(nav, ctx, nav.velocity / speed, horizon, 0)
    if path.rejection == .None { return 0 }
    stopping := speed * speed / (2 * nav.profile.braking)
    reaction := speed * (ctx.motion.tick_seconds + f32(ctx.senses.vision.profile.sample_interval) * ctx.motion.tick_seconds)
    return clamp((stopping + reaction - path.clearance) / max(stopping + reaction, 0.001), 0, 1)
}

@(private)
navigation_choose :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, preferred: Vector, horizon, comfort: f32) -> int {
    wanted, _ := obs.facing_toward({}, preferred)
    if nav.committed && abs(obs.facing_step(nav.preferred_facing, wanted)) >= 2 { nav.committed, nav.passing_side = false, .None }
    committed := nav.committed && !tick_due(ctx.tick, nav.commitment_until)
    side := nav.passing_side
    if side == .None { side = .Right if ctx.entity_id % 2 == 0 else .Left }
    best, best_score := -1, f32(-1e9)
    for index in 0..<8 {
        facing := Facing(index)
        direction := preferred if facing == wanted else obs.facing_direction(facing)
        choice := navigation_passage(nav, ctx, direction, horizon, comfort)
        choice.score = 4 * search_alignment(direction, preferred) - 0.35 * choice.pressure
        choice.score -= 0.04 * f32(abs(obs.facing_step(ctx.facing, facing)))
        if choice.uncertain { choice.score -= 0.4 }
        turn := obs.facing_step(wanted, facing)
        if turn != 0 && (turn > 0) == (side == .Right) { choice.score += 0.2 }
        if committed && facing == nav.heading { choice.score += 1.5 }
        if nav.committed && turn != 0 && (turn > 0) != (side == .Right) { choice.score -= 1.0 }
        nav.choices[index] = choice
        if choice.rejection == .None && choice.score > best_score { best, best_score = index, choice.score }
    }
    if best < 0 { return -1 }
    heading := Facing(best)
    if heading != wanted {
        if !nav.committed || heading != nav.heading {
            nav.commitment_until = ctx.tick + nav.profile.bout_ticks
        }
        if nav.passing_side == .None {
            nav.passing_side = .Right if obs.facing_step(wanted, heading) > 0 else .Left
        }
        nav.committed = true
    } else if !committed {
        nav.committed, nav.passing_side = false, .None
    }
    nav.heading, nav.preferred_facing = heading, wanted
    return best
}

@(private)
navigation_steer :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, preferred: Intent) -> Intent {
    if preferred.kind == .Move && preferred.approach.active && !nav.preferred.approach.active {
        nav.committed, nav.passing_side = false, .None
    }
    nav.preferred, nav.requested_move, nav.intended_distance = preferred, false, 0
    nav.position, nav.dt = ctx.position, ctx.motion.tick_seconds
    nav.active = ctx.motion.maximum_speed > 0 && ctx.motion.footprint_radius > 0 && ctx.motion.tick_seconds > 0
    if !nav.active || !ctx.can_act || preferred.kind != .Move {
        nav.mode, nav.speed, nav.urgency, nav.progress_started = .Inactive, 0, 0, false
        return preferred
    }
    length := math.sqrt(search_alignment(preferred.direction, preferred.direction))
    if !(length > 0 && length <= 1.001) { return preferred }
    nav.requested_move = true
    if !nav.progress_started {
        nav.progress_started, nav.progress_origin, nav.progress_tick = true, ctx.position, ctx.tick
    }
    if nav.recovery_pending {
        nav.recovery_pending, nav.committed, nav.passing_side = false, false, .None
    }
    direction := preferred.direction / length
    desired_speed := min(1, length) * ctx.motion.maximum_speed
    comfort := nav.profile.clearance
    remaining := f32(1e9)
    if preferred.approach.active {
        remaining = max(0, distance_between(ctx.position, preferred.approach.position) - max(0, preferred.approach.arrival_distance))
        comfort = max(0, preferred.approach.clearance)
        if remaining <= 0.05 {
            nav.mode, nav.speed, nav.requested_move, nav.progress_started = .Arrived, 0, false, false
            return {}
        }
        desired_speed = min(desired_speed, math.sqrt(2 * nav.profile.braking * remaining))
    }
    horizon := min(remaining, max(nav.profile.minimum_lookahead, desired_speed * nav.profile.lookahead_seconds))
    nav.urgency = navigation_urgency(nav, ctx, min(remaining, max(horizon, nav.speed * nav.profile.lookahead_seconds)))
    selected := navigation_choose(nav, ctx, direction, horizon, comfort)
    if selected < 0 {
        side := -1 if nav.passing_side == .Left else 1
        return navigation_turn(nav, ctx, obs.facing_rotate(ctx.facing, side), true)
    }
    choice := nav.choices[selected]
    if nav.heading != ctx.facing { return navigation_turn(nav, ctx, nav.heading, choice.uncertain) }
    if choice.uncertain { desired_speed = min(desired_speed, nav.profile.unknown_speed) }
    if nav.urgency >= 0.95 {
        nav.mode, nav.speed = .Inspect, 0
        return {}
    }
    desired_speed *= 1 - 0.75 * nav.urgency
    change := nav.profile.acceleration if desired_speed > nav.speed else nav.profile.braking
    nav.speed += clamp(desired_speed - nav.speed, -change * nav.dt, change * nav.dt)
    nav.speed = min(nav.speed, remaining / nav.dt)
    nav.mode = .Inspect if choice.uncertain else .Advance
    nav.intended_distance = nav.speed * nav.dt
    command := preferred
    command.direction = choice.direction * (nav.speed / ctx.motion.maximum_speed)
    return command
}
