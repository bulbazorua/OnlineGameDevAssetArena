package ai

import "core:math"

@(private)
navigation_record_result :: proc(nav: ^Navigation_Runtime, result: Action_Result, tick: u32) -> bool {
    if !nav.active || nav.dt <= 0 { return false }
    nav.actual_displacement = result.displacement
    nav.actual_distance = math.sqrt(search_alignment(result.displacement, result.displacement))
    nav.velocity = result.displacement / nav.dt
    if !nav.requested_move { nav.failed_ticks = 0; return false }
    if result.kind == .Preparing || result.kind == .Locked { return false }
    along_command := search_alignment(result.displacement, nav.choices[int(nav.heading)].direction)
    if nav.intended_distance > 0.001 && along_command < nav.intended_distance * 0.2 {
        nav.failed_ticks += 1
    } else if nav.actual_distance > 0.001 {
        nav.failed_ticks = 0
    }
    if distance_between(nav.position + result.displacement, nav.progress_origin) >= max(4, nav.memory.tile_size * 0.25) {
        nav.progress_origin, nav.progress_tick = nav.position + result.displacement, tick
    }
    if nav.failed_ticks < nav.profile.blocked_ticks && tick - nav.progress_tick < nav.profile.progress_ticks { return false }
    nav.mode, nav.recovery_pending, nav.committed, nav.passing_side = .Recover, true, false, .None
    nav.failed_ticks, nav.progress_tick, nav.progress_origin = 0, tick, nav.position + result.displacement
    nav.recovery_count += 1
    return true
}

@(private)
navigation_trace :: proc(nav: ^Navigation_Runtime, trace: ^Trace_Buffer, parent: int) {
    if !nav.active || !nav.requested_move { return }
    node := trace_add(trace, parent, .Controller, .Selected, "Steer beneath the current intent using private visible terrain",
        "movement mode / passing side", f64(nav.mode), f64(nav.passing_side), nav.preferred.direction)
    trace_add(trace, node, .Decision, .Selected, "Body-safe passage, speed and collision urgency; candidates are in after.navigation",
        "commanded speed / collision urgency", f64(nav.speed), f64(nav.urgency), nav.choices[int(nav.heading)].direction)
}
