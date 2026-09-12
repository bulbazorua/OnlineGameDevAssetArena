package ai

import obs "../observations"
import "core:testing"
import "core:math"
import "core:fmt"
import "core:time"

@(private = "file")
navigation_test_context :: proc() -> Decision_Context {
    ctx := Decision_Context{entity_id = 3, round_id = 1, tick = 1, position = {56, 104}, facing = .East,
        can_act = true, turn_ready = true, motion = {64, 8, 1.0 / 60.0}}
    ctx.senses.vision_is_new = true
    ctx.senses.vision = {observer = 3, round_id = 1, sample_id = 1, sample_tick = 1, status = .Sampled,
        pose = {ctx.position, ctx.facing}, profile = {true, 160, 60, 160, 6},
        terrain = {valid = true, origin = {0, 0}, tile_size = 16}}
    for &cell in ctx.senses.vision.terrain.cells { cell = obs.terrain_cell(.Clear) }
    return ctx
}

@(private = "file")
navigation_test_move :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, preferred: Intent = {kind = .Move, direction = {1, 0}}) -> Intent {
    navigation_observe(nav, ctx)
    return navigation_steer(nav, ctx, preferred)
}

@(test)
navigation_passes_a_post_before_contact_and_keeps_its_side :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults()}
    ctx := navigation_test_context()
    ctx.senses.vision.terrain.cells[6 * 13 + 6] = obs.terrain_cell(.Solid)
    first := navigation_test_move(&nav, ctx)
    testing.expect(t, first.kind == .Face && first.facing != .East)
    testing.expect(t, nav.choices[int(Facing.East)].rejection == .Solid)
    testing.expect(t, nav.passing_side != .None && nav.actual_distance == 0)
    side := nav.passing_side
    for tick in u32(2)..=90 {
        ctx.tick = tick
        ctx.position.y = 104 + (0.03 if tick % 2 == 0 else -0.03)
        navigation_test_move(&nav, ctx)
        testing.expect(t, nav.passing_side == side, "near-equal openings caused left-right chatter")
    }
}

@(test)
navigation_wall_ahead_is_not_a_legal_move_but_a_parallel_wall_is :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults()}
    ctx := navigation_test_context()
    for y in 0..<13 { ctx.senses.vision.terrain.cells[y * 13 + 6] = obs.terrain_cell(.Solid) }
    command := navigation_test_move(&nav, ctx)
    testing.expect(t, command.kind != .Move || command.direction.x <= 0.001)
    testing.expect(t, nav.choices[int(Facing.East)].rejection == .Solid)
    nav = {profile = navigation_defaults()}
    ctx = navigation_test_context()
    ctx.position, ctx.senses.vision.pose.position = {40, 88}, {40, 88}
    for x in 0..<13 { ctx.senses.vision.terrain.cells[4 * 13 + x] = obs.terrain_cell(.Solid) }
    command = navigation_test_move(&nav, ctx)
    testing.expect(t, command.kind == .Move && command.direction.x > 0 && command.direction.y == 0)
    testing.expect(t, nav.choices[int(Facing.East)].rejection == .None && nav.urgency == 0, "parallel contact became a false emergency")
}

@(test)
navigation_openings_fit_the_body_and_unknown_ground_is_not_marked_clear :: proc(t: ^testing.T) {
    ctx := navigation_test_context()
    ctx.position, ctx.senses.vision.pose.position = {56, 112}, {56, 112}
    for y in 0..<13 {
        if y != 6 && y != 7 { ctx.senses.vision.terrain.cells[y * 13 + 6] = obs.terrain_cell(.Solid) }
    }
    small := Navigation_Runtime{profile = navigation_defaults()}
    large := small
    small_command := navigation_test_move(&small, ctx)
    ctx.motion.footprint_radius = 17
    navigation_test_move(&large, ctx)
    testing.expect(t, small_command.kind == .Move && small.choices[int(Facing.East)].rejection == .None)
    testing.expect(t, large.choices[int(Facing.East)].rejection == .Solid, "center-ray clearance ignored body width")
    unknown := Navigation_Runtime{profile = navigation_defaults()}
    ctx = navigation_test_context()
    ctx.senses.vision.terrain.cells = {}
    command := navigation_test_move(&unknown, ctx)
    testing.expect(t, unknown.mode == .Inspect && unknown.choices[int(Facing.East)].uncertain)
    testing.expect(t, command.kind == .Move && math.sqrt(search_alignment(command.direction, command.direction)) * ctx.motion.maximum_speed <= unknown.profile.unknown_speed)
}

@(test)
navigation_cover_approach_brakes_and_stops_before_the_wall :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults(), speed = 64}
    ctx := navigation_test_context()
    ctx.position, ctx.senses.vision.pose.position = {80, 104}, {80, 104}
    for y in 0..<13 { ctx.senses.vision.terrain.cells[y * 13 + 8] = obs.terrain_cell(.Solid) }
    preferred := Intent{kind = .Move, direction = {1, 0},
        approach = {active = true, position = {118, 104}, arrival_distance = 2, clearance = 0}}
    slowed := false
    for tick in u32(1)..=120 {
        ctx.tick = tick
        command := navigation_test_move(&nav, ctx, preferred)
        if command.kind == .Move {
            delta := command.direction * (ctx.motion.maximum_speed * ctx.motion.tick_seconds)
            ctx.position += delta
            navigation_record_result(&nav, {kind = .Moved, displacement = delta, facing = .East}, tick)
            if nav.speed < 60 { slowed = true }
        }
        testing.expect(t, ctx.position.x + ctx.motion.footprint_radius <= 128)
    }
    testing.expectf(t, nav.mode == .Arrived && abs(ctx.position.x - 116) < 0.1 && slowed, "cover stop: position %v, mode %v", ctx.position, nav.mode)
}

@(test)
navigation_stationary_rotation_retains_obstacles_without_false_looming :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults()}
    ctx := navigation_test_context()
    ctx.senses.vision.terrain.cells[6 * 13 + 6] = obs.terrain_cell(.Solid)
    navigation_test_move(&nav, ctx)
    testing.expect(t, nav.urgency == 0)
    ctx.tick, ctx.facing = 7, .West
    ctx.senses.vision.sample_id, ctx.senses.vision.sample_tick = 2, 7
    ctx.senses.vision.pose.facing = .West
    ctx.senses.vision.terrain.cells = {}
    navigation_test_move(&nav, ctx)
    testing.expect(t, obs.terrain_state(navigation_known_cell(&nav, {6, 6}, 7)) == .Solid)
    testing.expect(t, nav.urgency == 0, "self-rotation manufactured closing velocity")
    testing.expect(t, obs.terrain_state(navigation_known_cell(&nav, {6, 6}, 182)) == .Unknown)
}

@(test)
navigation_perceived_closing_rate_brakes_but_stationary_proximity_does_not :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults(), speed = 64, velocity = {64, 0}}
    ctx := navigation_test_context()
    ctx.position, ctx.senses.vision.pose.position = {86, 104}, {86, 104}
    ctx.senses.vision.terrain.cells[6 * 13 + 6] = obs.terrain_cell(.Solid)
    command := navigation_test_move(&nav, ctx)
    testing.expect(t, nav.urgency > 0.5 && command.kind != .Move, "a fast approach did not interrupt movement")
    nav.velocity = {}
    navigation_test_move(&nav, ctx)
    testing.expect(t, nav.urgency == 0)
}

@(test)
navigation_persistent_trap_returns_control_to_search_and_accepts_real_detours :: proc(t: ^testing.T) {
    agent := agent_reset(3, 1, .Search, 42)
    ctx := navigation_test_context()
    ctx.position, ctx.senses.vision.pose.position = {104, 104}, {104, 104}
    for &cell in ctx.senses.vision.terrain.cells { cell = obs.terrain_cell(.Solid) }
    ctx.senses.vision.terrain.cells[6 * 13 + 6] = obs.terrain_cell(.Clear)
    for tick in u32(1)..=260 {
        ctx.tick = tick
        // Keep seeing the enclosure instead of replaying one expired picture.
        ctx.senses.vision_is_new = (tick - 1) % ctx.senses.vision.profile.sample_interval == 0
        if ctx.senses.vision_is_new {
            ctx.senses.vision.sample_id = 1 + (tick - 1) / ctx.senses.vision.profile.sample_interval
            ctx.senses.vision.sample_tick, ctx.senses.vision.delivered_tick = tick, tick
            ctx.senses.vision.pose = {ctx.position, ctx.facing}
        }
        command := agent_decide(&agent, ctx, observe_defaults())
        testing.expect(t, command.kind != .Move, "an enclosed creature was forced forward")
        result := Action_Result{kind = .Held, facing = ctx.facing}
        if command.kind == .Face {
            turn := clamp(obs.facing_step(ctx.facing, command.facing), -1, 1)
            ctx.facing = obs.facing_rotate(ctx.facing, turn)
            result.kind, result.facing = .Turned, ctx.facing
        }
        agent_record_result(&agent, result, tick, observe_defaults())
    }
    testing.expect(t, agent.navigation.recovery_count > 0 && agent.search.blocked_count > 0, "persistent local failure never reached search")
    detour := Navigation_Runtime{profile = navigation_defaults(), active = true, requested_move = true, dt = 1.0 / 60.0,
        intended_distance = 0.5, progress_started = true, heading = .South}
    detour.choices[int(Facing.South)].direction = {0, 1}
    for tick in u32(1)..=500 {
        detour.position.y = f32(tick - 1) * 0.5
        testing.expect(t, !navigation_record_result(&detour, {kind = .Moved, displacement = {0, 0.5}}, tick))
    }
    testing.expect(t, detour.recovery_count == 0, "a useful detour was mistaken for failure")
}

@(test)
navigation_memories_random_streams_and_diagnostics_stay_individual :: proc(t: ^testing.T) {
    ctx := navigation_test_context()
    ctx.senses.vision.terrain.cells[6 * 13 + 6] = obs.terrain_cell(.Solid)
    first := agent_reset(3, 1, .Search, 42)
    second := agent_reset(4, 1, .Search, 42)
    traced := first
    trace: Trace_Buffer
    agent_decide(&first, ctx, observe_defaults())
    agent_decide(&traced, ctx, observe_defaults(), &trace)
    testing.expect(t, first == traced && trace.truncated == 0)
    other := ctx
    other.entity_id, other.senses.vision.observer = 4, 4
    other.senses.vision.terrain.cells = {}
    agent_decide(&second, other, observe_defaults())
    testing.expect(t, obs.terrain_state(navigation_known_cell(&first.navigation, {6, 6}, 1)) == .Solid)
    testing.expect(t, obs.terrain_state(navigation_known_cell(&second.navigation, {6, 6}, 1)) == .Unknown)
    random := first.search.random_state
    for tick in u32(2)..=60 {
        ctx.tick = tick
        navigation_test_move(&first.navigation, ctx)
    }
    testing.expect(t, first.search.random_state == random, "local avoidance consumed the search random stream")
}

@(test)
navigation_checks_seen_height_changes_and_exact_rounded_clearance :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults()}
    ctx := navigation_test_context()
    for y in 0..<13 { ctx.senses.vision.terrain.cells[y * 13 + 6] = obs.terrain_cell(.Clear, 1) }
    navigation_test_move(&nav, ctx)
    testing.expect(t, nav.choices[int(Facing.East)].rejection == .Step)
    ctx.senses.vision.sample_id = 2
    for y in 0..<13 { ctx.senses.vision.terrain.cells[y * 13 + 6] = obs.terrain_cell(.Clear, 1, true) }
    nav = {profile = navigation_defaults()}
    navigation_test_move(&nav, ctx)
    testing.expect(t, nav.choices[int(Facing.East)].rejection == .None)
    tangent := navigation_cell_contact({0, 8}, {1, 0}, {16, 16}, 16, 8, 64)
    collision := navigation_cell_contact({0, 8.5}, {1, 0}, {16, 16}, 16, 8, 64)
    testing.expect(t, tangent == 64 && collision < 64)
}

@(test)
navigation_fixed_work_benchmark :: proc(t: ^testing.T) {
    nav := Navigation_Runtime{profile = navigation_defaults()}
    ctx := navigation_test_context()
    ctx.senses.vision.terrain.cells[6 * 13 + 6] = obs.terrain_cell(.Solid)
    started := time.tick_now()
    for tick in u32(1)..=3600 {
        ctx.tick = tick
        ctx.senses.vision.sample_id, ctx.senses.vision.sample_tick = tick, tick
        navigation_test_move(&nav, ctx)
    }
    fmt.printfln("[navigation] 3600 private local decisions: %v; context %d bytes, agent %d bytes", time.tick_since(started), size_of(Decision_Context), size_of(Agent))
    testing.expect(t, size_of(Decision_Context) < 1024)
}
